defmodule DocpubWeb.VaultFileControllerTest do
  use DocpubWeb.ConnCase

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "vault_file_ctrl_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.write!(Path.join(tmp_dir, "test.png"), <<137, 80, 78, 71>>)
    File.mkdir_p!(Path.join(tmp_dir, "sub"))
    File.write!(Path.join(tmp_dir, "sub/doc.pdf"), <<37, 80, 68, 70>>)

    prev = Application.get_env(:docpub, :vault_path)
    Application.put_env(:docpub, :vault_path, tmp_dir)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:docpub, :vault_path, prev),
        else: Application.delete_env(:docpub, :vault_path)

      File.rm_rf!(tmp_dir)
    end)

    %{vault_path: tmp_dir}
  end

  describe "show/2" do
    test "serves a file from the vault", %{conn: conn} do
      conn = get(conn, ~p"/vault_file/test.png")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
    end

    test "serves nested files", %{conn: conn} do
      conn = get(conn, ~p"/vault_file/sub/doc.pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
    end

    test "returns 404 for missing files", %{conn: conn} do
      conn = get(conn, ~p"/vault_file/nonexistent.png")

      assert conn.status == 404
    end

    test "rejects path traversal", %{conn: conn} do
      conn = get(conn, "/vault_file/..%2F..%2Fetc%2Fpasswd")

      assert conn.status in [403, 404]
    end
  end
end
