defmodule DocpubWeb.Plugs.VaultAuth do
  @moduledoc """
  Plug that optionally requires password authentication.
  When `config :docpub, auth: :password` is set, unauthenticated
  requests are redirected to the login page.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:docpub, :auth, :none) do
      :none ->
        conn

      :password ->
        if get_session(conn, :authenticated) do
          conn
        else
          conn
          |> put_session(:return_to, conn.request_path)
          |> redirect(to: "/login")
          |> halt()
        end
    end
  end
end
