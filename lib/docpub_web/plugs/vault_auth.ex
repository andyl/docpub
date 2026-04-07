defmodule DocpubWeb.Plugs.VaultAuth do
  @moduledoc """
  Plug that optionally requires password authentication.
  When `config :docpub, password: "secret"` is set, unauthenticated
  requests are redirected to the login page.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:docpub, :password) do
      if get_session(conn, :authenticated) do
        conn
      else
        conn
        |> put_session(:return_to, conn.request_path)
        |> redirect(to: "/login")
        |> halt()
      end
    else
      conn
    end
  end
end
