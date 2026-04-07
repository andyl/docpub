defmodule Docpub.ServerTest do
  use ExUnit.Case, async: true

  alias Docpub.Server

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
  end
end
