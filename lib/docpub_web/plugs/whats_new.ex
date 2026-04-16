defmodule DocpubWeb.Plugs.WhatsNew do
  @moduledoc """
  Reads the signed What's New last-visit cookie, computes the change summary,
  assigns it to the conn, and stamps a refreshed cookie on the response.

  LiveViews and controllers downstream can read `conn.assigns.whats_new`.
  """
  import Plug.Conn

  alias Docpub.WhatsNew
  alias Docpub.WhatsNew.Cookie

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    cookie_value = conn.req_cookies[Cookie.name()]

    {summary, new_cookie} = WhatsNew.summarize(cookie_value)

    conn
    |> assign(:whats_new, summary)
    |> put_session(:whats_new_summary, summary)
    |> maybe_put_cookie(new_cookie)
  end

  defp maybe_put_cookie(conn, nil), do: conn

  defp maybe_put_cookie(conn, value) do
    put_resp_cookie(conn, Cookie.name(), value, Cookie.options())
  end
end
