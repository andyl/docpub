defmodule Docpub.WhatsNew.Git do
  @moduledoc """
  Thin adapter around the `git` CLI for the What's New feature.

  All functions take the vault repo path explicitly and never raise. When git is
  missing, the path is not a repo, or a command fails, `{:error, reason}` is
  returned so callers can fall back to `:no_baseline`.
  """

  alias Docpub.WhatsNew.FileChange

  @markdown_extensions ~w(.md .markdown)
  @image_extensions ~w(.png .jpg .jpeg .gif .svg .webp .bmp)
  @pdf_extensions ~w(.pdf)

  @surfaced_extensions @markdown_extensions ++ @image_extensions ++ @pdf_extensions

  @type meta :: %{sha: String.t(), author: String.t(), date: DateTime.t()}

  @doc """
  Returns the current HEAD commit metadata for `repo_path`.
  """
  @spec head(String.t()) :: {:ok, meta()} | {:error, atom()}
  def head(repo_path), do: commit_meta(repo_path, "HEAD")

  @doc """
  Returns `true` when the given SHA refers to a commit in `repo_path`.
  """
  @spec commit_exists?(String.t(), String.t()) :: boolean()
  def commit_exists?(repo_path, sha) when is_binary(sha) and sha != "" do
    case run(repo_path, ["cat-file", "-e", sha <> "^{commit}"]) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def commit_exists?(_repo_path, _sha), do: false

  @doc """
  Returns `%{sha, author, date}` for the given commit-ish.
  """
  @spec commit_meta(String.t(), String.t()) :: {:ok, meta()} | {:error, atom()}
  def commit_meta(repo_path, rev) do
    with {:ok, out} <- run(repo_path, ["log", "-1", "--format=%H%x01%an%x01%aI", rev]) do
      parse_meta(String.trim(out))
    end
  end

  @doc """
  Computes per-file changes between `from_sha` and `to_sha`.

  Results are filtered to vault-surfaced extensions (markdown, image, pdf) and
  sorted by `last_commit_date` descending.
  """
  @spec diff_range(String.t(), String.t(), String.t()) ::
          {:ok, [FileChange.t()]} | {:error, atom()}
  def diff_range(repo_path, from_sha, to_sha) do
    with {:ok, name_status} <-
           run(repo_path, [
             "diff",
             "--name-status",
             "-M",
             "-z",
             from_sha <> ".." <> to_sha
           ]),
         {:ok, numstat} <-
           run(repo_path, [
             "diff",
             "--numstat",
             "-M",
             "-z",
             from_sha <> ".." <> to_sha
           ]) do
      entries = parse_name_status(name_status)
      stats = parse_numstat(numstat)

      changes =
        entries
        |> Enum.filter(&surfaced?/1)
        |> Enum.map(fn entry ->
          key = stats_key(entry)
          {added, removed} = Map.get(stats, key, {0, 0})
          build_change(repo_path, entry, added, removed, from_sha, to_sha)
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.last_commit_date, {:desc, DateTime})

      {:ok, changes}
    end
  end

  # --- Internals ---

  defp run(repo_path, args) do
    case System.cmd("git", ["-C", repo_path] ++ args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {_, _} -> {:error, :git_failed}
    end
  rescue
    _ -> {:error, :git_missing}
  end

  defp parse_meta(""), do: {:error, :git_failed}

  defp parse_meta(line) do
    case String.split(line, "\x01") do
      [sha, author, date_str] ->
        case DateTime.from_iso8601(date_str) do
          {:ok, dt, _} -> {:ok, %{sha: sha, author: author, date: dt}}
          _ -> {:error, :bad_date}
        end

      _ ->
        {:error, :bad_meta}
    end
  end

  # `-z` gives NUL-separated records. For R/C entries, the status token is
  # followed by two NUL-separated paths; for others, one path.
  defp parse_name_status(""), do: []

  defp parse_name_status(out) do
    out
    |> String.split("\0", trim: false)
    |> Enum.reject(&(&1 == ""))
    |> consume_name_status([])
    |> Enum.reverse()
  end

  defp consume_name_status([], acc), do: acc

  defp consume_name_status([status, old, new | rest], acc)
       when binary_part(status, 0, 1) in ["R", "C"] do
    consume_name_status(rest, [{:renamed, old, new} | acc])
  end

  defp consume_name_status([status, path | rest], acc) do
    entry =
      case String.first(status) do
        "A" -> {:added, nil, path}
        "M" -> {:modified, nil, path}
        "D" -> {:deleted, path, nil}
        "T" -> {:modified, nil, path}
        _ -> nil
      end

    if entry, do: consume_name_status(rest, [entry | acc]), else: consume_name_status(rest, acc)
  end

  defp consume_name_status(_leftover, acc), do: acc

  # `--numstat -z` emits records of "added\tremoved\t<path>\0" for plain
  # changes, and "added\tremoved\t\0<old>\0<new>\0" for renames/copies.
  defp parse_numstat(""), do: %{}

  defp parse_numstat(out) do
    out
    |> String.split("\0", trim: false)
    |> consume_numstat(%{})
  end

  defp consume_numstat([""], acc), do: acc
  defp consume_numstat([], acc), do: acc

  defp consume_numstat([token | rest], acc) do
    # plain: "added\tremoved\tpath"
    # rename: "added\tremoved\t" then next two are old, new
    case String.split(token, "\t") do
      [added, removed, ""] ->
        case rest do
          [old, new | tail] ->
            consume_numstat(tail, Map.put(acc, {:rename, old, new}, to_counts(added, removed)))

          _ ->
            acc
        end

      [added, removed, path] ->
        consume_numstat(rest, Map.put(acc, {:plain, path}, to_counts(added, removed)))

      _ ->
        consume_numstat(rest, acc)
    end
  end

  defp to_counts("-", "-"), do: {0, 0}

  defp to_counts(a, r) do
    {String.to_integer(to_int(a)), String.to_integer(to_int(r))}
  end

  defp to_int("-"), do: "0"
  defp to_int(v), do: v

  defp stats_key({:renamed, old, new}), do: {:rename, old, new}
  defp stats_key({_change, nil, path}), do: {:plain, path}
  defp stats_key({_change, path, nil}), do: {:plain, path}

  defp surfaced?({:renamed, _old, new}), do: surfaced_path?(new)
  defp surfaced?({_change, nil, path}), do: surfaced_path?(path)
  defp surfaced?({_change, path, nil}), do: surfaced_path?(path)

  defp surfaced_path?(path) do
    path |> Path.extname() |> String.downcase() |> then(&(&1 in @surfaced_extensions))
  end

  defp build_change(repo_path, entry, added, removed, from_sha, to_sha) do
    {change, prev, path} =
      case entry do
        {:renamed, old, new} -> {:renamed, old, new}
        {c, nil, p} -> {c, nil, p}
        {c, p, nil} -> {c, nil, p}
      end

    case last_commit_for_file(repo_path, from_sha, to_sha, path, prev) do
      {:ok, meta} ->
        %FileChange{
          path: path,
          previous_path: prev,
          change: change,
          last_commit_sha: meta.sha,
          last_commit_author: meta.author,
          last_commit_date: meta.date,
          lines_added: added,
          lines_removed: removed
        }

      _ ->
        nil
    end
  end

  defp last_commit_for_file(repo_path, from_sha, to_sha, path, prev) do
    paths = Enum.reject([path, prev], &is_nil/1)

    args =
      [
        "log",
        "-1",
        "--format=%H%x01%an%x01%aI",
        from_sha <> ".." <> to_sha,
        "--"
      ] ++ paths

    case run(repo_path, args) do
      {:ok, out} ->
        trimmed = String.trim(out)
        if trimmed == "", do: {:error, :no_commits}, else: parse_meta(trimmed)

      {:error, _} = err ->
        err
    end
  end
end
