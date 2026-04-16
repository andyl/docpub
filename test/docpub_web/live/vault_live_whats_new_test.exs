defmodule DocpubWeb.VaultLiveWhatsNewTest do
  use DocpubWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Docpub.WhatsNew.Cookie

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "vault_wn_live_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    git!(tmp_dir, ["init", "-q", "-b", "main"])
    git!(tmp_dir, ["config", "user.email", "alice@example.com"])
    git!(tmp_dir, ["config", "user.name", "Alice"])
    git!(tmp_dir, ["config", "commit.gpgsign", "false"])

    File.write!(Path.join(tmp_dir, "README.md"), "# Welcome\n")
    File.write!(Path.join(tmp_dir, "notes.md"), "# Notes\n")
    File.mkdir_p!(Path.join(tmp_dir, "subfolder"))
    File.write!(Path.join(tmp_dir, "subfolder/old.md"), "# Old\n")
    git!(tmp_dir, ["add", "."])
    git!(tmp_dir, ["commit", "-q", "-m", "baseline"])
    {baseline, 0} = System.cmd("git", ["-C", tmp_dir, "rev-parse", "HEAD"])
    baseline = String.trim(baseline)

    File.write!(Path.join(tmp_dir, "README.md"), "# Welcome\nUpdated\n")
    File.write!(Path.join(tmp_dir, "subfolder/deep.md"), "# Deep\n")
    git!(tmp_dir, ["add", "."])
    git!(tmp_dir, ["commit", "-q", "-m", "second"])

    prev = Application.get_env(:docpub, :vault_path)
    Application.put_env(:docpub, :vault_path, tmp_dir)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:docpub, :vault_path, prev),
        else: Application.delete_env(:docpub, :vault_path)

      File.rm_rf!(tmp_dir)
    end)

    start_supervised!(Docpub.WhatsNew.Cache)

    %{vault_path: tmp_dir, baseline: baseline}
  end

  defp git!(repo, args) do
    {_, 0} = System.cmd("git", ["-C", repo] ++ args, stderr_to_stdout: true)
  end

  defp conn_with_baseline(conn, baseline) do
    cookie =
      Cookie.encode(%{
        last_visit_date: DateTime.to_iso8601(DateTime.utc_now()),
        last_git_commit: baseline
      })

    conn
    |> Plug.Conn.put_req_header("cookie", "#{Cookie.name()}=#{cookie}")
  end

  describe "banner" do
    test "shows on first view of changed file and includes author", %{
      conn: conn,
      baseline: baseline
    } do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/README")
      assert has_element?(view, "#whats-new-banner")
      assert render(view) =~ "Alice"
    end

    test "absent when current path is unchanged", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/notes")
      refute has_element?(view, "#whats-new-banner")
    end

    test "close hides banner", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/README")
      assert has_element?(view, "#whats-new-banner")

      view |> element("button[phx-click=whats_new_close]") |> render_click()

      refute has_element?(view, "#whats-new-banner")
    end
  end

  describe "sidebar markers" do
    test "marks changed file not yet visited", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/notes")
      assert has_element?(view, "#tree-README\\.md span[title=Updated]")
    end

    test "visiting a changed file removes its marker", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/README")
      refute has_element?(view, "#tree-README\\.md span[title=Updated]")
    end

    test "marks ancestor folder when collapsed", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/notes")
      assert has_element?(view, "#tree-subfolder span[title='Contains recent changes']")
    end
  end
end
