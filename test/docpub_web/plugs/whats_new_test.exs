defmodule DocpubWeb.Plugs.WhatsNewTest do
  use DocpubWeb.ConnCase, async: false

  alias Docpub.WhatsNew.{Cookie, Summary}
  alias DocpubWeb.Plugs.WhatsNew, as: Plug

  setup do
    repo = Path.join(System.tmp_dir!(), "whats_new_plug_#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    {_, 0} = System.cmd("git", ["-C", repo, "init", "-q", "-b", "main"])
    {_, 0} = System.cmd("git", ["-C", repo, "config", "user.email", "test@example.com"])
    {_, 0} = System.cmd("git", ["-C", repo, "config", "user.name", "Test"])
    {_, 0} = System.cmd("git", ["-C", repo, "config", "commit.gpgsign", "false"])
    File.write!(Path.join(repo, "a.md"), "hi\n")
    {_, 0} = System.cmd("git", ["-C", repo, "add", "a.md"])
    {_, 0} = System.cmd("git", ["-C", repo, "commit", "-q", "-m", "first"])

    previous = Application.get_env(:docpub, :vault_path)
    Application.put_env(:docpub, :vault_path, repo)

    on_exit(fn ->
      Application.put_env(:docpub, :vault_path, previous)
      File.rm_rf!(repo)
    end)

    start_supervised!(Docpub.WhatsNew.Cache)
    :ok
  end

  test "assigns a summary and stamps a signed cookie on the response", %{conn: conn} do
    conn = Plug.call(conn, Plug.init([]))

    assert %Summary{} = conn.assigns.whats_new

    assert %{value: value} = conn.resp_cookies[Cookie.name()]
    assert is_binary(value)
    assert {:ok, _payload} = Cookie.decode(value)
  end
end
