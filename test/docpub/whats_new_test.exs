defmodule Docpub.WhatsNewTest do
  use ExUnit.Case, async: false

  alias Docpub.WhatsNew
  alias Docpub.WhatsNew.{Cookie, Summary}

  setup do
    repo = Path.join(System.tmp_dir!(), "whats_new_facade_#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    git!(repo, ["init", "-q", "-b", "main"])
    git!(repo, ["config", "user.email", "test@example.com"])
    git!(repo, ["config", "user.name", "Test"])
    git!(repo, ["config", "commit.gpgsign", "false"])

    # Baseline commit
    File.write!(Path.join(repo, "intro.md"), "hello\n")
    git!(repo, ["add", "intro.md"])
    git!(repo, ["commit", "-q", "-m", "intro"])
    baseline = rev_parse(repo, "HEAD")

    # Subsequent commit
    File.write!(Path.join(repo, "new.md"), "new page\n")
    git!(repo, ["add", "new.md"])
    git!(repo, ["commit", "-q", "-m", "add new"])
    head = rev_parse(repo, "HEAD")

    previous = Application.get_env(:docpub, :vault_path)
    Application.put_env(:docpub, :vault_path, repo)

    on_exit(fn ->
      Application.put_env(:docpub, :vault_path, previous)
      File.rm_rf!(repo)
    end)

    start_supervised!(Docpub.WhatsNew.Cache)

    %{repo: repo, baseline: baseline, head: head}
  end

  test "nil cookie yields :no_baseline and a fresh cookie for current HEAD", %{head: head} do
    {summary, new_cookie} = WhatsNew.summarize(nil)

    assert %Summary{kind: :no_baseline, files: []} = summary
    assert is_binary(new_cookie)
    assert {:ok, payload} = Cookie.decode(new_cookie)
    assert payload.last_git_commit == head
  end

  test "valid baseline cookie yields a diff summary", %{baseline: baseline, head: head} do
    cookie =
      Cookie.encode(%{
        last_visit_date: DateTime.to_iso8601(DateTime.utc_now()),
        last_git_commit: baseline
      })

    {summary, new_cookie} = WhatsNew.summarize(cookie)

    assert summary.kind == :diff
    assert summary.from_commit == baseline
    assert summary.to_commit == head
    paths = Enum.map(summary.files, & &1.path)
    assert "new.md" in paths

    assert {:ok, payload} = Cookie.decode(new_cookie)
    assert payload.last_git_commit == head
  end

  test "unknown commit in cookie falls back to :no_baseline", %{head: head} do
    cookie =
      Cookie.encode(%{
        last_visit_date: DateTime.to_iso8601(DateTime.utc_now()),
        last_git_commit: "0000000000000000000000000000000000000000"
      })

    {summary, new_cookie} = WhatsNew.summarize(cookie)
    assert summary.kind == :no_baseline

    assert {:ok, payload} = Cookie.decode(new_cookie)
    assert payload.last_git_commit == head
  end

  test "tampered cookie falls back to :no_baseline" do
    {summary, new_cookie} = WhatsNew.summarize("not-a-signed-value")
    assert summary.kind == :no_baseline
    assert is_binary(new_cookie)
  end

  defp git!(repo, args) do
    {_, 0} = System.cmd("git", ["-C", repo] ++ args, stderr_to_stdout: true)
    :ok
  end

  defp rev_parse(repo, rev) do
    {out, 0} = System.cmd("git", ["-C", repo, "rev-parse", rev])
    String.trim(out)
  end
end
