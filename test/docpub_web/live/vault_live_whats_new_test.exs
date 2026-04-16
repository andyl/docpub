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

  defp conn_with_no_baseline(conn) do
    # No cookie at all -> :no_baseline summary
    conn
  end

  describe "toast" do
    test "renders when summary has changes", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/README")
      assert has_element?(view, "#whats-new-toast")
      assert render(view) =~ "files changed since your last visit"
    end

    test "absent when summary is :no_baseline", %{conn: conn} do
      {:ok, view, _html} = live(conn_with_no_baseline(conn), "/doc/README")
      refute has_element?(view, "#whats-new-toast")
    end

    test "dismiss event hides the toast", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/README")
      assert has_element?(view, "#whats-new-toast")

      view |> element("button[phx-click=whats_new_dismiss]") |> render_click()

      refute has_element?(view, "#whats-new-toast")
    end
  end

  describe "banner" do
    test "renders when current path is in the change set", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/README")
      assert has_element?(view, "#whats-new-banner")
      assert render(view) =~ "Alice"
    end

    test "absent when current path is unchanged", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/notes")
      refute has_element?(view, "#whats-new-banner")
    end
  end

  describe "sidebar markers" do
    test "marks changed file in tree", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/notes")
      assert has_element?(view, "#tree-README\\.md span[title=Updated]")
    end

    test "marks ancestor folder when collapsed", %{conn: conn, baseline: baseline} do
      {:ok, view, _html} = live(conn_with_baseline(conn, baseline), "/doc/README")
      assert has_element?(view, "#tree-subfolder span[title='Contains recent changes']")
    end
  end
end
