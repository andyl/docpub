defmodule Docpub.WhatsNew do
  @moduledoc """
  Public API for the What's New feature.

  Given the current visitor's signed last-visit cookie value, returns a
  structured summary of vault changes since that visit plus a freshly-stamped
  cookie value the caller should write back on the response.

  This function never raises. On any failure path (missing cookie, tampered
  cookie, unknown commit, not a git repo, git missing) it returns a
  `:no_baseline` summary and a cookie value reflecting the current HEAD.
  """

  alias Docpub.WhatsNew.{Cache, Cookie, Hunk, Summary}

  @doc """
  Summarise vault changes for a visitor.

  Accepts a signed cookie value (or `nil`). Returns `{summary, new_cookie}`
  where `new_cookie` is always a freshly signed cookie reflecting the current
  HEAD so the caller can unconditionally write it back.

  When no HEAD is available (cache disabled / not a git repo) the returned
  cookie is `nil`, so the caller should only set the cookie when non-nil.
  """
  @spec summarize(String.t() | nil) :: {Summary.t(), String.t() | nil}
  def summarize(cookie_value) do
    payload = decode(cookie_value)
    from_sha = payload && payload.last_git_commit

    summary =
      case Cache.summary_for(from_sha) do
        {:ok, s} -> s
        :error -> %Summary{}
      end

    new_cookie =
      case Cache.current_head() do
        {:ok, %{sha: sha}} ->
          Cookie.encode(%{
            last_visit_date: DateTime.to_iso8601(DateTime.utc_now()),
            last_git_commit: sha
          })

        :error ->
          nil
      end

    {summary, new_cookie}
  end

  @doc """
  Returns the post-image line hunks for `path` between `from_sha` and `to_sha`.

  Returns `[]` when the cache is unavailable or the file has no recorded
  changes in that range.
  """
  @spec line_hunks(String.t(), String.t(), String.t()) :: [Hunk.t()]
  def line_hunks(from_sha, to_sha, path) do
    case Cache.line_hunks(from_sha, to_sha, path) do
      {:ok, hunks} -> hunks
      :error -> []
    end
  end

  defp decode(nil), do: nil

  defp decode(value) do
    case Cookie.decode(value) do
      {:ok, payload} -> payload
      :error -> nil
    end
  end
end
