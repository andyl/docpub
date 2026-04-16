defmodule Docpub.WhatsNew.Cache do
  @moduledoc """
  GenServer that caches the current HEAD of the vault repo and memoises
  per-(from) change summaries.

  Refreshes HEAD on a 30s timer and on `:vault_changed` PubSub events from
  `Docpub.VaultWatcher`. Returns `:ignore` from `init/1` when the vault path
  is missing or not a git repo.
  """
  use GenServer

  require Logger

  alias Docpub.WhatsNew.{Git, Hunk, Summary}

  @refresh_interval_ms 30_000
  @cache_cap 64

  # --- public API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns `{:ok, %{sha, date}}` for the current HEAD, or `:error` if the cache
  is unavailable (no vault / not a git repo).
  """
  @spec current_head() :: {:ok, %{sha: String.t(), date: DateTime.t()}} | :error
  def current_head do
    call(:current_head, :error)
  end

  @doc """
  Returns the cached (or freshly computed) summary for a given `from_sha`.

  The `from_sha` may be `nil`, in which case a `:no_baseline` summary is
  returned. When the cache is unavailable, `:error` is returned so the caller
  can fall back to `:no_baseline`.
  """
  @spec summary_for(String.t() | nil) :: {:ok, Summary.t()} | :error
  def summary_for(from_sha) do
    call({:summary_for, from_sha}, :error)
  end

  @doc """
  Returns the cached (or freshly computed) post-image line hunks for `path`
  between `from_sha` and `to_sha`. Returns `:error` when the cache is
  unavailable.
  """
  @spec line_hunks(String.t(), String.t(), String.t()) :: {:ok, [Hunk.t()]} | :error
  def line_hunks(from_sha, to_sha, path) do
    call({:line_hunks, from_sha, to_sha, path}, :error)
  end

  defp call(msg, fallback) do
    GenServer.call(__MODULE__, msg)
  catch
    :exit, _ -> fallback
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    vault_path = Docpub.Vault.vault_path()

    cond do
      is_nil(vault_path) ->
        Logger.info("WhatsNew.Cache: no vault_path configured, cache disabled")
        :ignore

      not File.dir?(Path.join(vault_path, ".git")) and
          not File.regular?(Path.join(vault_path, ".git")) ->
        Logger.info("WhatsNew.Cache: vault is not a git repository, cache disabled")
        :ignore

      true ->
        _ = Docpub.VaultWatcher.subscribe()
        schedule_refresh()

        state = %{
          vault_path: vault_path,
          head: nil,
          head_date: nil,
          summaries: %{},
          order: [],
          hunks: %{},
          hunks_order: []
        }

        {:ok, refresh_head(state)}
    end
  end

  @impl true
  def handle_call(:current_head, _from, state) do
    reply =
      case state.head do
        nil -> :error
        sha -> {:ok, %{sha: sha, date: state.head_date}}
      end

    {:reply, reply, state}
  end

  def handle_call({:summary_for, _from_sha}, _from, %{head: nil} = state) do
    {:reply, :error, state}
  end

  def handle_call({:summary_for, from_sha}, _from, state) do
    case Map.fetch(state.summaries, from_sha) do
      {:ok, summary} ->
        {:reply, {:ok, summary}, touch(state, from_sha)}

      :error ->
        summary = compute_summary(state, from_sha)
        new_state = store(state, from_sha, summary)
        {:reply, {:ok, summary}, new_state}
    end
  end

  def handle_call({:line_hunks, from_sha, to_sha, path}, _from, state) do
    key = {from_sha, to_sha, path}

    case Map.fetch(state.hunks, key) do
      {:ok, hunks} ->
        {:reply, {:ok, hunks}, touch_hunks(state, key)}

      :error ->
        case Git.line_hunks(state.vault_path, from_sha, to_sha, path) do
          {:ok, hunks} ->
            {:reply, {:ok, hunks}, store_hunks(state, key, hunks)}

          {:error, _} ->
            {:reply, {:ok, []}, state}
        end
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    {:noreply, refresh_head(state)}
  end

  def handle_info({:vault_changed, _path, _events}, state) do
    {:noreply, refresh_head(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- internals ---

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp refresh_head(state) do
    case Git.head(state.vault_path) do
      {:ok, %{sha: sha, date: date}} ->
        if sha == state.head do
          state
        else
          %{
            state
            | head: sha,
              head_date: date,
              summaries: %{},
              order: [],
              hunks: %{},
              hunks_order: []
          }
        end

      _ ->
        state
    end
  end

  defp compute_summary(state, nil) do
    case Git.commit_meta(state.vault_path, "HEAD~5") do
      {:ok, meta} -> compute_summary(state, meta.sha)
      _ -> no_baseline(state)
    end
  end

  defp compute_summary(state, from_sha) do
    with true <- Git.commit_exists?(state.vault_path, from_sha) || :unknown,
         {:ok, from_meta} <- Git.commit_meta(state.vault_path, from_sha),
         {:ok, files} <- Git.diff_range(state.vault_path, from_sha, state.head) do
      build_summary(state, from_meta, files)
    else
      _ -> no_baseline(state)
    end
  end

  defp build_summary(state, from_meta, []) do
    %Summary{
      kind: :empty,
      from_commit: from_meta.sha,
      to_commit: state.head,
      from_date: from_meta.date,
      to_date: state.head_date,
      files: [],
      counts: Summary.counts_from([])
    }
  end

  defp build_summary(state, from_meta, files) do
    %Summary{
      kind: :diff,
      from_commit: from_meta.sha,
      to_commit: state.head,
      from_date: from_meta.date,
      to_date: state.head_date,
      files: files,
      counts: Summary.counts_from(files)
    }
  end

  defp no_baseline(state) do
    %Summary{
      kind: :no_baseline,
      from_commit: nil,
      to_commit: state.head,
      from_date: nil,
      to_date: state.head_date,
      files: [],
      counts: Summary.counts_from([])
    }
  end

  defp store(state, from_sha, summary) do
    order = [from_sha | Enum.reject(state.order, &(&1 == from_sha))]
    summaries = Map.put(state.summaries, from_sha, summary)

    {order, summaries} =
      if length(order) > @cache_cap do
        {kept, [evict]} = Enum.split(order, @cache_cap)
        {kept, Map.delete(summaries, evict)}
      else
        {order, summaries}
      end

    %{state | summaries: summaries, order: order}
  end

  defp touch(state, from_sha) do
    %{state | order: [from_sha | Enum.reject(state.order, &(&1 == from_sha))]}
  end

  defp store_hunks(state, key, hunks) do
    order = [key | Enum.reject(state.hunks_order, &(&1 == key))]
    map = Map.put(state.hunks, key, hunks)

    {order, map} =
      if length(order) > @cache_cap do
        {kept, [evict]} = Enum.split(order, @cache_cap)
        {kept, Map.delete(map, evict)}
      else
        {order, map}
      end

    %{state | hunks: map, hunks_order: order}
  end

  defp touch_hunks(state, key) do
    %{state | hunks_order: [key | Enum.reject(state.hunks_order, &(&1 == key))]}
  end
end
