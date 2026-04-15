defmodule Docpub.WhatsNew.GitTest do
  use ExUnit.Case, async: true

  alias Docpub.WhatsNew.Git

  setup do
    repo = Path.join(System.tmp_dir!(), "whats_new_git_#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    git!(repo, ["init", "-q", "-b", "main"])
    git!(repo, ["config", "user.email", "test@example.com"])
    git!(repo, ["config", "user.name", "Test"])
    git!(repo, ["config", "commit.gpgsign", "false"])

    on_exit(fn -> File.rm_rf!(repo) end)

    %{repo: repo}
  end

  describe "head/1 and commit_exists?/2" do
    test "returns HEAD meta after a commit", %{repo: repo} do
      sha = commit(repo, "README.md", "hello", "first")
      assert {:ok, %{sha: ^sha, author: "Test", date: %DateTime{}}} = Git.head(repo)
      assert Git.commit_exists?(repo, sha)
      refute Git.commit_exists?(repo, "0000000000000000000000000000000000000000")
    end

    test "returns error for a non-repo directory" do
      dir = Path.join(System.tmp_dir!(), "not_repo_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      assert {:error, _} = Git.head(dir)
      refute Git.commit_exists?(dir, "abc")
    end
  end

  describe "diff_range/3" do
    test "detects added, modified, and deleted markdown files", %{repo: repo} do
      _ = commit(repo, "a.md", "one", "add a")
      from = commit(repo, "b.md", "two", "add b")
      File.write!(Path.join(repo, "a.md"), "one updated\nsecond line\n")
      git!(repo, ["add", "a.md"])
      git!(repo, ["commit", "-q", "-m", "modify a"])
      git!(repo, ["rm", "-q", "b.md"])
      git!(repo, ["commit", "-q", "-m", "delete b"])
      to = rev_parse(repo, "HEAD")

      {:ok, files} = Git.diff_range(repo, from, to)
      by_path = Map.new(files, &{&1.path, &1})

      assert %{change: :modified, lines_added: added} = by_path["a.md"]
      assert added >= 1
      assert %{change: :deleted} = by_path["b.md"]
    end

    test "ignores non-surfaced extensions", %{repo: repo} do
      from = commit(repo, "a.md", "one", "add a")
      _ = commit(repo, "notes.txt", "ignored", "add txt")
      to = rev_parse(repo, "HEAD")

      {:ok, files} = Git.diff_range(repo, from, to)
      paths = Enum.map(files, & &1.path)
      refute "notes.txt" in paths
    end

    test "detects renames", %{repo: repo} do
      from = commit(repo, "old.md", "same content across rename\nline 2\nline 3\n", "add old")
      git!(repo, ["mv", "old.md", "new.md"])
      git!(repo, ["commit", "-q", "-m", "rename"])
      to = rev_parse(repo, "HEAD")

      {:ok, files} = Git.diff_range(repo, from, to)
      assert [change] = files
      assert change.change == :renamed
      assert change.path == "new.md"
      assert change.previous_path == "old.md"
    end

    test "equal HEAD yields empty list", %{repo: repo} do
      sha = commit(repo, "a.md", "one", "only")
      assert {:ok, []} = Git.diff_range(repo, sha, sha)
    end
  end

  # --- helpers ---

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo] ++ args, stderr_to_stdout: true)
    out
  end

  defp commit(repo, path, content, message) do
    full = Path.join(repo, path)
    full |> Path.dirname() |> File.mkdir_p!()
    File.write!(full, content)
    git!(repo, ["add", path])
    git!(repo, ["commit", "-q", "-m", message])
    rev_parse(repo, "HEAD")
  end

  defp rev_parse(repo, rev) do
    {out, 0} = System.cmd("git", ["-C", repo, "rev-parse", rev])
    String.trim(out)
  end
end
