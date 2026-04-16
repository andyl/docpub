defmodule DocpubWeb.WhatsNewControllerTest do
  use DocpubWeb.ConnCase, async: false

  alias Docpub.WhatsNew.Cookie

  setup do
    repo = Path.join(System.tmp_dir!(), "whats_new_ctl_#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    {_, 0} = System.cmd("git", ["-C", repo, "init", "-q", "-b", "main"])
    {_, 0} = System.cmd("git", ["-C", repo, "config", "user.email", "test@example.com"])
    {_, 0} = System.cmd("git", ["-C", repo, "config", "user.name", "Test"])
    {_, 0} = System.cmd("git", ["-C", repo, "config", "commit.gpgsign", "false"])
    File.write!(Path.join(repo, "intro.md"), "hi\n")
    {_, 0} = System.cmd("git", ["-C", repo, "add", "intro.md"])
    {_, 0} = System.cmd("git", ["-C", repo, "commit", "-q", "-m", "first"])

    {head_sha, 0} = System.cmd("git", ["-C", repo, "rev-parse", "HEAD"])
    head = String.trim(head_sha)

    previous = Application.get_env(:docpub, :vault_path)
    Application.put_env(:docpub, :vault_path, repo)

    on_exit(fn ->
      Application.put_env(:docpub, :vault_path, previous)
      File.rm_rf!(repo)
    end)

    start_supervised!(Docpub.WhatsNew.Cache)

    %{head: head}
  end

  test "POST /whats-new/mark-read sets cookie to current HEAD and redirects", %{
    conn: conn,
    head: head
  } do
    conn = post(conn, "/whats-new/mark-read", %{"redirect_to" => "/doc/intro"})

    assert redirected_to(conn) == "/doc/intro"
    assert %{value: value} = conn.resp_cookies[Cookie.name()]
    assert {:ok, payload} = Cookie.decode(value)
    assert payload.last_git_commit == head
  end

  test "rejects open-redirect URLs (//evil.com)", %{conn: conn} do
    conn = post(conn, "/whats-new/mark-read", %{"redirect_to" => "//evil.com/x"})
    assert redirected_to(conn) == "/"
  end

  test "rejects scheme-bearing redirect URLs", %{conn: conn} do
    conn = post(conn, "/whats-new/mark-read", %{"redirect_to" => "https://evil.com/x"})
    assert redirected_to(conn) == "/"
  end

  test "defaults to / when redirect_to is missing", %{conn: conn} do
    conn = post(conn, "/whats-new/mark-read", %{})
    assert redirected_to(conn) == "/"
  end
end
