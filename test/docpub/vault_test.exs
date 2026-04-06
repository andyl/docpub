defmodule Docpub.VaultTest do
  use ExUnit.Case, async: true

  alias Docpub.Vault

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "vault_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    # Create test vault structure
    File.write!(Path.join(tmp_dir, "README.md"), "# Welcome\n\nHello world")
    File.write!(Path.join(tmp_dir, "notes.md"), "# Notes\n\nSome notes here")
    File.write!(Path.join(tmp_dir, "image.png"), <<0, 1, 2, 3>>)

    File.mkdir_p!(Path.join(tmp_dir, "subfolder"))
    File.write!(Path.join(tmp_dir, "subfolder/deep.md"), "# Deep\n\nNested document")
    File.write!(Path.join(tmp_dir, "subfolder/photo.jpg"), <<4, 5, 6>>)

    File.mkdir_p!(Path.join(tmp_dir, "subfolder/nested"))
    File.write!(Path.join(tmp_dir, "subfolder/nested/leaf.md"), "# Leaf\n\nDeepest level")

    # Hidden files/dirs that should be filtered
    File.write!(Path.join(tmp_dir, ".hidden"), "secret")
    File.mkdir_p!(Path.join(tmp_dir, ".obsidian"))
    File.write!(Path.join(tmp_dir, ".obsidian/config.json"), "{}")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{vault_path: tmp_dir}
  end

  describe "list_tree/1" do
    test "returns nested tree of vault files", %{vault_path: vault_path} do
      tree = Vault.list_tree(vault_path)

      names = Enum.map(tree, & &1.name)
      assert "subfolder" in names
      assert "README.md" in names
      assert "notes.md" in names
      assert "image.png" in names
    end

    test "folders come before files and are sorted", %{vault_path: vault_path} do
      tree = Vault.list_tree(vault_path)

      types = Enum.map(tree, & &1.type)
      folder_idx = Enum.find_index(types, &(&1 == :folder))
      first_file_idx = Enum.find_index(types, &(&1 != :folder))

      assert folder_idx < first_file_idx
    end

    test "filters hidden files and directories", %{vault_path: vault_path} do
      tree = Vault.list_tree(vault_path)
      all_names = tree |> flatten_names()

      refute ".hidden" in all_names
      refute ".obsidian" in all_names
    end

    test "classifies file types correctly", %{vault_path: vault_path} do
      tree = Vault.list_tree(vault_path)
      flat = Vault.flatten_tree(tree)

      readme = Enum.find(flat, &(&1.name == "README.md"))
      assert readme.type == :markdown

      image = Enum.find(flat, &(&1.name == "image.png"))
      assert image.type == :image

      photo = Enum.find(flat, &(&1.name == "photo.jpg"))
      assert photo.type == :image
    end

    test "includes nested children", %{vault_path: vault_path} do
      tree = Vault.list_tree(vault_path)
      subfolder = Enum.find(tree, &(&1.name == "subfolder"))

      assert subfolder.type == :folder
      child_names = Enum.map(subfolder.children, & &1.name)
      assert "deep.md" in child_names
      assert "nested" in child_names
    end
  end

  describe "read_file/2" do
    test "reads an existing file", %{vault_path: vault_path} do
      assert {:ok, content} = Vault.read_file(vault_path, "README.md")
      assert content =~ "# Welcome"
    end

    test "returns error for nonexistent file", %{vault_path: vault_path} do
      assert {:error, :enoent} = Vault.read_file(vault_path, "nonexistent.md")
    end

    test "rejects path traversal", %{vault_path: vault_path} do
      assert {:error, :invalid_path} = Vault.read_file(vault_path, "../etc/passwd")
    end

    test "rejects absolute paths", %{vault_path: vault_path} do
      assert {:error, :invalid_path} = Vault.read_file(vault_path, "/etc/passwd")
    end
  end

  describe "write_file/3" do
    test "writes content to a file", %{vault_path: vault_path} do
      assert :ok = Vault.write_file(vault_path, "README.md", "# Updated\n\nNew content")
      assert {:ok, "# Updated\n\nNew content"} = Vault.read_file(vault_path, "README.md")
    end

    test "creates parent directories if needed", %{vault_path: vault_path} do
      assert :ok = Vault.write_file(vault_path, "new/dir/file.md", "content")
      assert {:ok, "content"} = Vault.read_file(vault_path, "new/dir/file.md")
    end

    test "rejects path traversal", %{vault_path: vault_path} do
      assert {:error, :invalid_path} = Vault.write_file(vault_path, "../evil.md", "bad")
    end
  end

  describe "create_file/3" do
    test "creates a new file", %{vault_path: vault_path} do
      assert :ok = Vault.create_file(vault_path, "new.md", "# New")
      assert {:ok, "# New"} = Vault.read_file(vault_path, "new.md")
    end

    test "errors if file already exists", %{vault_path: vault_path} do
      assert {:error, :eexist} = Vault.create_file(vault_path, "README.md", "overwrite")
    end

    test "rejects path traversal", %{vault_path: vault_path} do
      assert {:error, :invalid_path} = Vault.create_file(vault_path, "../evil.md", "bad")
    end
  end

  describe "delete_file/2" do
    test "deletes an existing file", %{vault_path: vault_path} do
      assert :ok = Vault.delete_file(vault_path, "notes.md")
      assert {:error, :enoent} = Vault.read_file(vault_path, "notes.md")
    end

    test "returns error for nonexistent file", %{vault_path: vault_path} do
      assert {:error, :enoent} = Vault.delete_file(vault_path, "nonexistent.md")
    end

    test "rejects path traversal", %{vault_path: vault_path} do
      assert {:error, :invalid_path} = Vault.delete_file(vault_path, "../important.md")
    end
  end

  describe "search/2" do
    test "finds matching documents", %{vault_path: vault_path} do
      results = Vault.search(vault_path, "welcome")

      assert length(results) == 1
      assert hd(results).path == "README.md"
    end

    test "search is case-insensitive", %{vault_path: vault_path} do
      results = Vault.search(vault_path, "WELCOME")
      assert length(results) == 1
    end

    test "returns empty for no matches", %{vault_path: vault_path} do
      results = Vault.search(vault_path, "zzz_nonexistent_zzz")
      assert results == []
    end

    test "searches nested files", %{vault_path: vault_path} do
      results = Vault.search(vault_path, "Deepest")

      assert length(results) == 1
      assert hd(results).path == "subfolder/nested/leaf.md"
    end

    test "returns match context", %{vault_path: vault_path} do
      results = Vault.search(vault_path, "Hello")

      assert length(results) == 1
      match = hd(hd(results).matches)
      assert match.line > 0
      assert match.text =~ "Hello"
      assert is_list(match.context)
    end
  end

  describe "flatten_tree/1" do
    test "returns all files without folders", %{vault_path: vault_path} do
      tree = Vault.list_tree(vault_path)
      flat = Vault.flatten_tree(tree)

      types = Enum.map(flat, & &1.type)
      refute :folder in types
      assert length(flat) > 0
    end
  end

  defp flatten_names(nodes) do
    Enum.flat_map(nodes, fn
      %{type: :folder, children: children, name: name} -> [name | flatten_names(children)]
      %{name: name} -> [name]
    end)
  end
end
