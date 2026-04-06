defmodule DocpubWeb.AuthController do
  use DocpubWeb, :controller

  def callback(conn, %{"password" => password}) do
    configured_password = Application.get_env(:docpub, :auth_password)

    if Plug.Crypto.secure_compare(password, configured_password || "") do
      return_to = get_session(conn, :return_to) || "/"

      conn
      |> put_session(:authenticated, true)
      |> delete_session(:return_to)
      |> redirect(to: return_to)
    else
      conn
      |> put_flash(:error, "Invalid password")
      |> redirect(to: "/login")
    end
  end

  def logout(conn, _params) do
    conn
    |> delete_session(:authenticated)
    |> redirect(to: "/login")
  end
end
