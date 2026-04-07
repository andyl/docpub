defmodule Mix.Tasks.Docpub.Serve do
  @moduledoc """
  Starts the Docpub vault viewer server.

  ## Usage

      mix docpub.serve [vault_path] [options]

  ## Options

    * `--port` - Port to listen on (default: 4000)
    * `--host` - Host to bind to (default: 127.0.0.1)
    * `--auth` - Authentication mode: none or password (default: none)
    * `--auth-password` - Password for authentication (required when --auth=password)
    * `--initial-page` - Initial page to display (e.g., "README")
    * `--help` - Show this help message
    * `--version` - Show version

  ## Examples

      mix docpub.serve ~/my-vault
      mix docpub.serve ~/my-vault --port 8080
      mix docpub.serve ~/my-vault --auth password --auth-password secret
  """
  use Mix.Task

  @version Mix.Project.config()[:version]

  @switches [
    port: :integer,
    host: :string,
    auth: :string,
    auth_password: :string,
    initial_page: :string,
    help: :boolean,
    version: :boolean
  ]

  @impl true
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    cond do
      opts[:help] ->
        Mix.shell().info(@moduledoc)

      opts[:version] ->
        Mix.shell().info("Docpub v#{@version}")

      true ->
        configure_and_start(opts, positional)
    end
  end

  defp configure_and_start(opts, positional) do
    vault_path =
      case positional do
        [path | _] -> Path.expand(path)
        [] -> File.cwd!()
      end

    unless File.dir?(vault_path) do
      Mix.raise("Vault path does not exist or is not a directory: #{vault_path}")
    end

    Application.put_env(:docpub, :vault_path, vault_path)

    # Enable the HTTP server (not enabled by default in dev)
    endpoint_config = Application.get_env(:docpub, DocpubWeb.Endpoint, [])
    Application.put_env(:docpub, DocpubWeb.Endpoint, Keyword.put(endpoint_config, :server, true))

    if opts[:initial_page] do
      Application.put_env(:docpub, :initial_page, opts[:initial_page])
    end

    auth = parse_auth(opts[:auth])
    Application.put_env(:docpub, :auth, auth)

    if auth == :password do
      password =
        opts[:auth_password] || Mix.raise("--auth-password is required when --auth=password")

      Application.put_env(:docpub, :auth_password, password)
    end

    # Set PORT env var so config/runtime.exs (which runs when the app starts,
    # after this task) picks it up instead of overwriting our Application.put_env.
    if opts[:port] do
      System.put_env("PORT", to_string(opts[:port]))
    end

    if opts[:host] do
      endpoint_config = Application.get_env(:docpub, DocpubWeb.Endpoint, [])
      http_config = Keyword.get(endpoint_config, :http, [])
      http_config = Keyword.put(http_config, :ip, parse_ip(opts[:host]))
      endpoint_config = Keyword.put(endpoint_config, :http, http_config)
      Application.put_env(:docpub, DocpubWeb.Endpoint, endpoint_config)
    end

    Mix.shell().info("Starting Docpub server...")
    Mix.shell().info("  Vault: #{vault_path}")
    Mix.shell().info("  URL:   http://#{opts[:host] || "localhost"}:#{opts[:port] || 4000}")

    Mix.Tasks.Run.run(["--no-halt"])
  end

  defp parse_auth(nil), do: :none
  defp parse_auth("none"), do: :none
  defp parse_auth("password"), do: :password
  defp parse_auth(other), do: Mix.raise("Invalid auth mode: #{other}. Use 'none' or 'password'.")

  defp parse_ip("0.0.0.0"), do: {0, 0, 0, 0}
  defp parse_ip("localhost"), do: {127, 0, 0, 1}

  defp parse_ip(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> ip
      {:error, _} -> Mix.raise("Invalid host address: #{host}")
    end
  end
end
