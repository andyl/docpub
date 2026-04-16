defmodule Docpub.WhatsNew.CacheTest do
  use ExUnit.Case, async: false

  alias Docpub.WhatsNew.Cache

  setup do
    repo = Path.join(System.tmp_dir!(), "wn_cache_#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    git!(repo, ["init", "-q", "-b", "main"])
    git!(repo, ["config", "user.email", "t@t.t"])
    git!(repo, ["config", "user.name", "T"])
    git!(repo, ["config", "commit.gpgsign", "false"])

    File.write!(Path.join(repo, "a.md"), "one\ntwo\n")
    git!(repo, ["add", "a.md"])
    git!(repo, ["commit", "-q", "-m", "first"])
    {from, 0} = System.cmd("git", ["-C", repo, "rev-parse", "HEAD"])
    from = String.trim(from)

    File.write!(Path.join(repo, "a.md"), "one\nTWO\nthree\n")
    git!(repo, ["add", "a.md"])
    git!(repo, ["commit", "-q", "-m", "second"])
    {to, 0} = System.cmd("git", ["-C", repo, "rev-parse", "HEAD"])
    to = String.trim(to)

    prev = Application.get_env(:docpub, :vault_path)
    Application.put_env(:docpub, :vault_path, repo)

    on_exit(fn ->
      Application.put_env(:docpub, :vault_path, prev)
      File.rm_rf!(repo)
    end)

    start_supervised!(Cache)

    %{from: from, to: to}
  end

  defp git!(repo, args), do: {_, 0} = System.cmd("git", ["-C", repo] ++ args)

  test "line_hunks/3 returns hunks and memoizes", %{from: from, to: to} do
    assert {:ok, hunks1} = Cache.line_hunks(from, to, "a.md")
    assert hunks1 != []

    # Second call should return identical structure (memoized).
    assert {:ok, ^hunks1} = Cache.line_hunks(from, to, "a.md")
  end

  test "line_hunks/3 returns [] for unknown path", %{from: from, to: to} do
    assert {:ok, []} = Cache.line_hunks(from, to, "missing.md")
  end
end
