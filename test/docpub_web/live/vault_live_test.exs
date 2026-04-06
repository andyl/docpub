defmodule DocpubWeb.VaultLiveTest do
  use DocpubWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "vault_live_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.write!(Path.join(tmp_dir, "README.md"), "# Welcome\n\nHello from the vault")
    File.write!(Path.join(tmp_dir, "notes.md"), "# Notes\n\nSome important notes")
    File.mkdir_p!(Path.join(tmp_dir, "subfolder"))
    File.write!(Path.join(tmp_dir, "subfolder/deep.md"), "# Deep Doc\n\nNested content")

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

  describe "document viewing" do
    test "renders a markdown document", %{conn: conn} do
      {:ok, view, html} = live(conn, "/doc/README")

      assert html =~ "Welcome"
      assert has_element?(view, "#doc-content")
    end

    test "shows not found for missing document", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/doc/nonexistent")

      assert has_element?(view, "#not-found")
    end

    test "renders nested documents", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/doc/subfolder/deep")

      assert html =~ "Deep Doc"
      assert html =~ "Nested content"
    end
  end

  describe "sidebar" do
    test "shows file tree in sidebar", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/doc/README")

      assert has_element?(view, "#file-tree")
    end
  end

  describe "mode toggling" do
    test "switches between view and edit mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/doc/README")

      assert has_element?(view, "#viewer")
      refute has_element?(view, "#editor")

      view |> element("button", "Edit") |> render_click()

      assert has_element?(view, "#editor")
      refute has_element?(view, "#viewer")

      view |> element("button", "Cancel") |> render_click()

      assert has_element?(view, "#viewer")
    end
  end

  describe "document editing" do
    test "saves edited content", %{conn: conn, vault_path: vault_path} do
      {:ok, view, _html} = live(conn, "/doc/README")

      view |> element("button", "Edit") |> render_click()

      view
      |> form("#edit-form", %{content: "# Updated\n\nNew content"})
      |> render_submit()

      assert {:ok, "# Updated\n\nNew content"} = File.read(Path.join(vault_path, "README.md"))
      assert has_element?(view, "#viewer")
    end
  end

  describe "document deletion" do
    test "deletes a document", %{conn: conn, vault_path: vault_path} do
      {:ok, view, _html} = live(conn, "/doc/notes")

      view |> element("button[phx-click=delete]") |> render_click()

      refute File.exists?(Path.join(vault_path, "notes.md"))
    end
  end

  describe "document creation" do
    test "creates a new document", %{conn: conn, vault_path: vault_path} do
      {:ok, view, _html} = live(conn, "/doc/README")

      view
      |> form("form[phx-submit=create]", %{name: "new-doc"})
      |> render_submit()

      assert File.exists?(Path.join(vault_path, "new-doc.md"))
    end
  end

  describe "search" do
    test "finds documents matching query", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/doc/README")

      view
      |> form("form[phx-submit=search]", %{q: "important"})
      |> render_submit()

      assert has_element?(view, "#search-results")
      assert render(view) =~ "notes.md"
    end

    test "shows no results for unmatched query", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/doc/README")

      view
      |> form("form[phx-submit=search]", %{q: "zzz_nomatch_zzz"})
      |> render_submit()

      assert has_element?(view, "#search-results")
      assert render(view) =~ "0 result(s)"
    end

    test "clears search results", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/doc/README")

      view
      |> form("form[phx-submit=search]", %{q: "welcome"})
      |> render_submit()

      assert has_element?(view, "#search-results")

      view |> element("button[phx-click=clear_search]") |> render_click()

      refute has_element?(view, "#search-results")
      assert has_element?(view, "#file-tree")
    end
  end
end
