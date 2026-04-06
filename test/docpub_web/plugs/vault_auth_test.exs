defmodule DocpubWeb.Plugs.VaultAuthTest do
  use DocpubWeb.ConnCase

  alias DocpubWeb.Plugs.VaultAuth

  describe "when auth is :none" do
    setup do
      prev = Application.get_env(:docpub, :auth)
      Application.put_env(:docpub, :auth, :none)
      on_exit(fn -> Application.put_env(:docpub, :auth, prev || :none) end)
      :ok
    end

    test "passes through without authentication", %{conn: conn} do
      conn = VaultAuth.call(conn, VaultAuth.init([]))
      refute conn.halted
    end
  end

  describe "when auth is :password" do
    setup do
      prev_auth = Application.get_env(:docpub, :auth)
      prev_pass = Application.get_env(:docpub, :auth_password)
      Application.put_env(:docpub, :auth, :password)
      Application.put_env(:docpub, :auth_password, "secret")

      on_exit(fn ->
        Application.put_env(:docpub, :auth, prev_auth || :none)

        if prev_pass,
          do: Application.put_env(:docpub, :auth_password, prev_pass),
          else: Application.delete_env(:docpub, :auth_password)
      end)

      :ok
    end

    test "redirects unauthenticated requests to login", %{conn: conn} do
      conn =
        conn
        |> Map.put(:request_path, "/doc/README")
        |> init_test_session(%{})
        |> VaultAuth.call(VaultAuth.init([]))

      assert conn.halted
      assert redirected_to(conn) == "/login"
    end

    test "allows authenticated requests through", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{authenticated: true})
        |> VaultAuth.call(VaultAuth.init([]))

      refute conn.halted
    end
  end
end
