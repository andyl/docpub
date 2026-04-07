defmodule DocpubWeb.Plugs.VaultAuthTest do
  use DocpubWeb.ConnCase

  alias DocpubWeb.Plugs.VaultAuth

  describe "when no password is configured" do
    setup do
      prev = Application.get_env(:docpub, :password)
      Application.put_env(:docpub, :password, nil)
      on_exit(fn -> Application.put_env(:docpub, :password, prev) end)
      :ok
    end

    test "passes through without authentication", %{conn: conn} do
      conn = VaultAuth.call(conn, VaultAuth.init([]))
      refute conn.halted
    end
  end

  describe "when password is configured" do
    setup do
      prev = Application.get_env(:docpub, :password)
      Application.put_env(:docpub, :password, "secret")

      on_exit(fn ->
        if prev,
          do: Application.put_env(:docpub, :password, prev),
          else: Application.put_env(:docpub, :password, nil)
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
