defmodule DocpubWeb.PageControllerTest do
  use DocpubWeb.ConnCase

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "page_ctrl_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    prev = Application.get_env(:docpub, :vault_path)
    Application.put_env(:docpub, :vault_path, tmp_dir)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:docpub, :vault_path, prev),
        else: Application.delete_env(:docpub, :vault_path)

      File.rm_rf!(tmp_dir)
    end)

    :ok
  end

  test "GET / renders vault", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "vault"
  end
end
