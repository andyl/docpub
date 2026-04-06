defmodule Docpub.VaultWatcher do
  @moduledoc """
  Watches the vault directory for file changes using FileSystem (inotify).
  Broadcasts `:vault_changed` events via PubSub so LiveViews can refresh.
  """
  use GenServer

  require Logger

  @pubsub Docpub.PubSub
  @topic "vault:changes"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @impl true
  def init(_opts) do
    vault_path = Docpub.Vault.vault_path()

    if vault_path do
      {:ok, pid} = FileSystem.start_link(dirs: [vault_path])
      FileSystem.subscribe(pid)
      {:ok, %{watcher_pid: pid, vault_path: vault_path}}
    else
      Logger.warning("VaultWatcher: no vault_path configured, watching disabled")
      :ignore
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    unless ignored_event?(path) do
      Logger.debug("Vault file changed: #{path} #{inspect(events)}")
      Phoenix.PubSub.broadcast(@pubsub, @topic, {:vault_changed, path, events})
    end

    {:noreply, state}
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("VaultWatcher: file system watcher stopped")
    {:noreply, state}
  end

  defp ignored_event?(path) do
    basename = Path.basename(path)

    String.starts_with?(basename, ".") or
      String.contains?(path, "/.git/") or
      String.contains?(path, "/node_modules/") or
      String.contains?(path, "/_build/")
  end
end
