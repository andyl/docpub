defmodule Docpub.MarkdownTest do
  use ExUnit.Case, async: true

  alias Docpub.Markdown
  alias Docpub.Vault

  @file_tree [
    %Vault{name: "README.md", path: "README.md", type: :markdown, children: nil},
    %Vault{name: "notes.md", path: "subfolder/notes.md", type: :markdown, children: nil},
    %Vault{name: "image.png", path: "images/image.png", type: :image, children: nil}
  ]

  describe "render/2" do
    test "renders basic markdown" do
      {:ok, html} = Markdown.render("# Hello\n\nThis is **bold** text.")

      assert html =~ "<h1>"
      assert html =~ "Hello"
      assert html =~ "<strong>bold</strong>"
    end

    test "renders code blocks with syntax highlighting" do
      {:ok, html} = Markdown.render("```elixir\ndefmodule Foo do\nend\n```")

      assert html =~ "language-elixir"
    end

    test "renders GFM tables" do
      md = """
      | Name | Value |
      |------|-------|
      | foo  | bar   |
      """

      {:ok, html} = Markdown.render(md)
      assert html =~ "<table>"
      assert html =~ "<th>"
    end

    test "renders task lists" do
      {:ok, html} = Markdown.render("- [x] Done\n- [ ] Todo")

      assert html =~ ~s(type="checkbox")
    end

    test "handles empty input" do
      {:ok, html} = Markdown.render("")
      assert html == ""
    end
  end

  describe "wiki-link resolution" do
    test "resolves wiki-links to existing files" do
      {:ok, html} = Markdown.render("See [[README]]", file_tree: @file_tree)

      assert html =~ ~s(href="/doc/README")
      assert html =~ ~s(class="vault-link")
    end

    test "resolves wiki-links with display text" do
      {:ok, html} = Markdown.render("See [[README|the readme]]", file_tree: @file_tree)

      assert html =~ ~s(href="/doc/README")
      assert html =~ "the readme"
    end

    test "marks unresolved wiki-links as broken" do
      {:ok, html} = Markdown.render("See [[nonexistent]]", file_tree: @file_tree)

      assert html =~ "vault-link-broken"
      assert html =~ "nonexistent"
    end

    test "resolves wiki-links by path" do
      {:ok, html} = Markdown.render("See [[subfolder/notes]]", file_tree: @file_tree)

      assert html =~ ~s(href="/doc/subfolder/notes")
    end
  end

  describe "image rewriting" do
    test "rewrites Obsidian image embeds" do
      {:ok, html} = Markdown.render("![[photo.png]]", current_dir: "docs")

      assert html =~ ~s(src="/vault_file/docs/photo.png")
    end

    test "rewrites standard markdown images with relative paths" do
      {:ok, html} = Markdown.render("![alt](photo.png)", current_dir: "docs")

      assert html =~ ~s(src="/vault_file/docs/photo.png")
    end

    test "does not rewrite absolute URLs" do
      {:ok, html} = Markdown.render("![alt](https://example.com/img.png)")

      assert html =~ ~s(src="https://example.com/img.png")
    end
  end

  describe "line_marks (What's New)" do
    alias Docpub.WhatsNew.Hunk

    test "stamps data-whats-new on overlapping blocks" do
      md = """
      Para one.

      Para two.

      Para three.
      """

      hunks = [%Hunk{kind: :modified, start_line: 3, end_line: 3}]

      {:ok, html} = Markdown.render(md, line_marks: hunks)

      assert html =~ ~s(data-whats-new="modified")
      assert html =~ ~s(aria-label="Updated since your last visit")
      # Sourcepos attribute should be stripped from output
      refute html =~ "data-sourcepos"
    end

    test "added wins over modified when both overlap" do
      md = "Para A.\n\nPara B.\n"

      hunks = [
        %Hunk{kind: :modified, start_line: 1, end_line: 3},
        %Hunk{kind: :added, start_line: 1, end_line: 1}
      ]

      {:ok, html} = Markdown.render(md, line_marks: hunks)

      assert html =~ ~s(data-whats-new="added")
    end

    test "no-op when line_marks is empty" do
      {:ok, html} = Markdown.render("Hello.\n", line_marks: [])
      refute html =~ "data-whats-new"
      refute html =~ "data-sourcepos"
    end
  end

  describe "mermaid blocks" do
    test "preserves mermaid code blocks for client-side rendering" do
      {:ok, html} = Markdown.render("```mermaid\ngraph TD\n  A-->B\n```")

      assert html =~ ~s(<pre class="mermaid">)
      assert html =~ "graph TD"
      # Should not have syntax highlighting wrapper
      refute html =~ "language-mermaid"
    end
  end
end
