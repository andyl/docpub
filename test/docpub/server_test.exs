defmodule Docpub.ServerTest do
  use ExUnit.Case, async: false

  alias Docpub.Server

  # Helper to set env vars for a test and clean them up afterward.
  defp with_env(vars, fun) do
    Enum.each(vars, fn {k, v} -> System.put_env(k, v) end)

    try do
      fun.()
    after
      Enum.each(vars, fn {k, _} -> System.delete_env(k) end)
    end
  end

  describe "parse_args/1" do
    test "returns :help when no arguments are given" do
      assert Server.parse_args([]) == :help
    end

    test "returns :help when only options are given without a vault path" do
      assert Server.parse_args(["--port", "8080"]) == :help
    end

    test "returns :help when --help is passed" do
      assert Server.parse_args(["--help"]) == :help
      assert Server.parse_args([".", "--help"]) == :help
    end

    test "returns :version when --version is passed" do
      assert Server.parse_args(["--version"]) == :version
    end

    test "returns {:run, opts, positional} when a vault path is given" do
      assert {:run, [], ["."]} = Server.parse_args(["."])
    end

    test "returns {:run, ...} when DOCPUB_PATH is set and no positional arg" do
      tmp = System.tmp_dir!()

      with_env(%{"DOCPUB_PATH" => tmp}, fn ->
        assert {:run, [], []} = Server.parse_args([])
      end)
    end

    test "returns {:run, ...} with options when DOCPUB_PATH is set" do
      tmp = System.tmp_dir!()

      with_env(%{"DOCPUB_PATH" => tmp}, fn ->
        assert {:run, opts, []} = Server.parse_args(["--port", "8080"])
        assert opts[:port] == 8080
      end)
    end

    test "parses options alongside the vault path" do
      assert {:run, opts, ["/tmp/vault"]} =
               Server.parse_args(["/tmp/vault", "--port", "8080", "--host", "0.0.0.0"])

      assert opts[:port] == 8080
      assert opts[:host] == "0.0.0.0"
    end

    test "parses --title" do
      assert {:run, opts, ["/tmp/vault"]} =
               Server.parse_args(["/tmp/vault", "--title", "My Notes"])

      assert opts[:title] == "My Notes"
    end
  end

  describe "merge_env/2" do
    test "falls back to DOCPUB_PATH when no positional arg is given" do
      tmp = System.tmp_dir!()

      with_env(%{"DOCPUB_PATH" => tmp}, fn ->
        {_opts, positional} = Server.merge_env([], [])
        assert positional == [tmp]
      end)
    end

    test "CLI positional arg takes precedence over DOCPUB_PATH" do
      with_env(%{"DOCPUB_PATH" => "/from/env"}, fn ->
        {_opts, positional} = Server.merge_env([], ["/from/cli"])
        assert positional == ["/from/cli"]
      end)
    end

    test "falls back to DOCPUB_PORT" do
      with_env(%{"DOCPUB_PORT" => "9090"}, fn ->
        {opts, _} = Server.merge_env([], [])
        assert opts[:port] == 9090
      end)
    end

    test "CLI --port takes precedence over DOCPUB_PORT" do
      with_env(%{"DOCPUB_PORT" => "9090"}, fn ->
        {opts, _} = Server.merge_env([port: 7070], [])
        assert opts[:port] == 7070
      end)
    end

    test "falls back to DOCPUB_HOST" do
      with_env(%{"DOCPUB_HOST" => "0.0.0.0"}, fn ->
        {opts, _} = Server.merge_env([], [])
        assert opts[:host] == "0.0.0.0"
      end)
    end

    test "falls back to DOCPUB_PASSWORD" do
      with_env(%{"DOCPUB_PASSWORD" => "secret"}, fn ->
        {opts, _} = Server.merge_env([], [])
        assert opts[:password] == "secret"
      end)
    end

    test "falls back to DOCPUB_INITIAL_PAGE" do
      with_env(%{"DOCPUB_INITIAL_PAGE" => "README"}, fn ->
        {opts, _} = Server.merge_env([], [])
        assert opts[:initial_page] == "README"
      end)
    end

    test "falls back to DOCPUB_TITLE" do
      with_env(%{"DOCPUB_TITLE" => "My Wiki"}, fn ->
        {opts, _} = Server.merge_env([], [])
        assert opts[:title] == "My Wiki"
      end)
    end

    test "CLI --title takes precedence over DOCPUB_TITLE" do
      with_env(%{"DOCPUB_TITLE" => "From Env"}, fn ->
        {opts, _} = Server.merge_env([title: "From CLI"], [])
        assert opts[:title] == "From CLI"
      end)
    end

    test "ignores empty env var strings" do
      with_env(%{"DOCPUB_TITLE" => "", "DOCPUB_PATH" => ""}, fn ->
        {opts, positional} = Server.merge_env([], [])
        assert opts[:title] == nil
        assert positional == []
      end)
    end
  end

  describe "configure/2" do
    test "errors when no vault path is provided" do
      assert {:error, message} = Server.configure([], [])
      assert message =~ "Vault path is required"
    end

    test "errors when vault path does not exist" do
      assert {:error, message} = Server.configure([], ["/nonexistent/path/xyzzy"])
      assert message =~ "does not exist"
    end

    test "succeeds with a valid directory" do
      tmp = System.tmp_dir!()
      assert {:ok, info} = Server.configure([], [tmp])
      assert info.vault_path == Path.expand(tmp)
    end

    test "defaults the title to Docpub" do
      tmp = System.tmp_dir!()
      assert {:ok, info} = Server.configure([], [tmp])
      assert info.title == "Docpub"
      assert Application.get_env(:docpub, :title) == "Docpub"
    end

    test "honors a custom --title" do
      tmp = System.tmp_dir!()
      assert {:ok, info} = Server.configure([title: "My Notes"], [tmp])
      assert info.title == "My Notes"
      assert Application.get_env(:docpub, :title) == "My Notes"
    end

    test "configures from DOCPUB_* env vars" do
      tmp = System.tmp_dir!()

      with_env(
        %{"DOCPUB_PATH" => tmp, "DOCPUB_TITLE" => "Env Title", "DOCPUB_PORT" => "9999"},
        fn ->
          assert {:ok, info} = Server.configure([], [])
          assert info.vault_path == Path.expand(tmp)
          assert info.title == "Env Title"
          assert info.port == 9999
        end
      )
    end
  end
end
