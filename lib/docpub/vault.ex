defmodule Docpub.Vault do
  @moduledoc """
  Context module for all vault filesystem operations.
  Walks the vault directory, reads/writes files, builds the file tree,
  and performs full-text search.
  """

  @ignored_dirs ~w(.git .obsidian node_modules _build deps .elixir_ls)
  @markdown_extensions ~w(.md .markdown)
  @image_extensions ~w(.png .jpg .jpeg .gif .svg .webp .bmp)
  @pdf_extensions ~w(.pdf)

  defstruct [:name, :path, :type, :children]

  @type file_type :: :folder | :markdown | :image | :pdf | :other
  @type t :: %__MODULE__{
          name: String.t(),
          path: String.t(),
          type: file_type(),
          children: [t()] | nil
        }

  @doc """
  Returns the configured vault path.
  """
  def vault_path do
    Application.get_env(:docpub, :vault_path, File.cwd!())
  end

  @doc """
  Returns a nested tree structure representing the vault directory.
  Hidden files/dirs and common ignores are filtered out.
  """
  @spec list_tree(String.t()) :: [t()]
  def list_tree(base_path \\ vault_path()) do
    base_path
    |> build_tree("")
    |> sort_tree()
  end

  defp build_tree(base_path, relative_path) do
    full_path = Path.join(base_path, relative_path)

    case File.ls(full_path) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&hidden?/1)
        |> Enum.reduce([], fn entry, acc ->
          entry_relative =
            if relative_path == "", do: entry, else: Path.join(relative_path, entry)

          entry_full = Path.join(base_path, entry_relative)

          cond do
            File.dir?(entry_full) and entry not in @ignored_dirs ->
              children = build_tree(base_path, entry_relative)

              node = %__MODULE__{
                name: entry,
                path: entry_relative,
                type: :folder,
                children: children
              }

              [node | acc]

            File.regular?(entry_full) ->
              node = %__MODULE__{
                name: entry,
                path: entry_relative,
                type: file_type(entry),
                children: nil
              }

              [node | acc]

            true ->
              acc
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp sort_tree(nodes) do
    nodes
    |> Enum.sort_by(fn node -> {sort_order(node.type), String.downcase(node.name)} end)
    |> Enum.map(fn
      %{type: :folder, children: children} = node ->
        %{node | children: sort_tree(children)}

      node ->
        node
    end)
  end

  defp sort_order(:folder), do: 0
  defp sort_order(_), do: 1

  defp hidden?(name), do: String.starts_with?(name, ".")

  defp file_type(name) do
    ext = name |> Path.extname() |> String.downcase()

    cond do
      ext in @markdown_extensions -> :markdown
      ext in @image_extensions -> :image
      ext in @pdf_extensions -> :pdf
      true -> :other
    end
  end

  @doc """
  Reads a file from the vault. Returns `{:ok, content}` or `{:error, reason}`.
  Guards against path traversal.
  """
  @spec read_file(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def read_file(base_path \\ vault_path(), relative_path) do
    with :ok <- validate_path(relative_path),
         full_path <- Path.join(base_path, relative_path),
         :ok <- verify_within_vault(base_path, full_path) do
      File.read(full_path)
    end
  end

  @doc """
  Writes content to an existing or new file in the vault.
  """
  @spec write_file(String.t(), String.t(), String.t()) :: :ok | {:error, atom()}
  def write_file(base_path \\ vault_path(), relative_path, content) do
    with :ok <- validate_path(relative_path),
         full_path <- Path.join(base_path, relative_path),
         :ok <- verify_within_vault(base_path, full_path) do
      full_path |> Path.dirname() |> File.mkdir_p!()
      File.write(full_path, content)
    end
  end

  @doc """
  Creates a new file. Returns `{:error, :eexist}` if the file already exists.
  """
  @spec create_file(String.t(), String.t(), String.t()) :: :ok | {:error, atom()}
  def create_file(base_path \\ vault_path(), relative_path, content) do
    with :ok <- validate_path(relative_path),
         full_path <- Path.join(base_path, relative_path),
         :ok <- verify_within_vault(base_path, full_path) do
      if File.exists?(full_path) do
        {:error, :eexist}
      else
        full_path |> Path.dirname() |> File.mkdir_p!()
        File.write(full_path, content)
      end
    end
  end

  @doc """
  Deletes a file from the vault.
  """
  @spec delete_file(String.t(), String.t()) :: :ok | {:error, atom()}
  def delete_file(base_path \\ vault_path(), relative_path) do
    with :ok <- validate_path(relative_path),
         full_path <- Path.join(base_path, relative_path),
         :ok <- verify_within_vault(base_path, full_path) do
      File.rm(full_path)
    end
  end

  @doc """
  Performs full-text search across all markdown files in the vault.
  Returns a list of `%{path: String.t(), matches: [%{line: integer(), text: String.t(), context: [String.t()]}]}`.
  """
  @spec search(String.t(), String.t()) :: [map()]
  def search(base_path \\ vault_path(), query) do
    query_down = String.downcase(query)

    base_path
    |> list_all_markdown_files("")
    |> Enum.reduce([], fn relative_path, acc ->
      case File.read(Path.join(base_path, relative_path)) do
        {:ok, content} ->
          matches = find_matches(content, query_down)
          if matches == [], do: acc, else: [%{path: relative_path, matches: matches} | acc]

        {:error, _} ->
          acc
      end
    end)
    |> Enum.sort_by(& &1.path)
  end

  defp list_all_markdown_files(base_path, relative_path) do
    full_path = Path.join(base_path, relative_path)

    case File.ls(full_path) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          entry_relative =
            if relative_path == "", do: entry, else: Path.join(relative_path, entry)

          entry_full = Path.join(base_path, entry_relative)

          cond do
            hidden?(entry) or entry in @ignored_dirs ->
              []

            File.dir?(entry_full) ->
              list_all_markdown_files(base_path, entry_relative)

            file_type(entry) == :markdown ->
              [entry_relative]

            true ->
              []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp find_matches(content, query_down) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {line, line_num}, acc ->
      if String.contains?(String.downcase(line), query_down) do
        context =
          lines
          |> Enum.slice(max(line_num - 3, 0), 5)
          |> Enum.map(&String.trim_trailing/1)

        [%{line: line_num, text: String.trim_trailing(line), context: context} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Flattens the file tree into a list of all file entries (no folders).
  Useful for wiki-link resolution.
  """
  @spec flatten_tree([t()]) :: [t()]
  def flatten_tree(tree) do
    Enum.flat_map(tree, fn
      %{type: :folder, children: children} -> flatten_tree(children)
      node -> [node]
    end)
  end

  defp validate_path(path) do
    if String.contains?(path, "..") or String.starts_with?(path, "/") do
      {:error, :invalid_path}
    else
      :ok
    end
  end

  defp verify_within_vault(base_path, full_path) do
    resolved_base = Path.expand(base_path)
    resolved_full = Path.expand(full_path)

    if String.starts_with?(resolved_full, resolved_base) do
      :ok
    else
      {:error, :invalid_path}
    end
  end
end
