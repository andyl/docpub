defmodule DocpubWeb.WhatsNewController do
  @moduledoc """
  Mark-as-read endpoint for the What's New feature.

  Phoenix LiveView cannot mutate cookies on a websocket frame, so this is a
  regular HTTP POST. It stamps the last-visit cookie to the current HEAD and
  redirects back to a validated local path.
  """
  use DocpubWeb, :controller

  alias Docpub.WhatsNew.{Cache, Cookie}

  def mark_read(conn, params) do
    redirect_to = safe_redirect(params["redirect_to"])

    conn =
      case Cache.current_head() do
        {:ok, %{sha: sha}} ->
          value =
            Cookie.encode(%{
              last_visit_date: DateTime.to_iso8601(DateTime.utc_now()),
              last_git_commit: sha
            })

          put_resp_cookie(conn, Cookie.name(), value, Cookie.options())

        :error ->
          conn
      end

    redirect(conn, to: redirect_to)
  end

  def reset(conn, params) do
    redirect_to = safe_redirect(params["redirect_to"])

    conn
    |> delete_resp_cookie(Cookie.name())
    |> redirect(to: redirect_to)
  end

  defp safe_redirect(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "//") -> "/"
      String.starts_with?(path, "/") -> path
      true -> "/"
    end
  end

  defp safe_redirect(_), do: "/"
end
