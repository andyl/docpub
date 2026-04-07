defmodule Mix.Tasks.Docpub.Serve do
  @shortdoc "Starts the Docpub vault viewer server"

  @moduledoc """
  Starts the Docpub vault viewer server.

  ## Usage

      mix docpub.serve <vault_path> [options]

  `vault_path` is required. Pass `.` to serve the current directory.
  Running with no arguments prints this help message.

  ## Options

    * `--port` - Port to listen on (default: 4000)
    * `--host` - Host to bind to (default: 127.0.0.1)
    * `--password` - Require password authentication (open access if omitted)
    * `--initial-page` - Initial page to display (e.g., `README`)
    * `--title` - Site title shown in the header and browser tab (default: `Docpub`)
    * `--help` - Show this help message
    * `--version` - Show version

  ## Examples

      mix docpub.serve .
      mix docpub.serve ~/my-vault
      mix docpub.serve ~/my-vault --port 8080
      mix docpub.serve ~/my-vault --host 0.0.0.0 --port 8080
      mix docpub.serve ~/my-vault --password secret
      mix docpub.serve ~/my-vault --initial-page README
      mix docpub.serve ~/my-vault --title "My Notes"
  """
  use Mix.Task

  # Only load config — do NOT start the app. We need to write
  # endpoint options into the application env *before* the
  # endpoint boots, otherwise the --port flag is ignored.
  @requirements ["app.config"]

  alias Docpub.Server

  @impl true
  def run(args) do
    case Server.parse_args(args) do
      :help ->
        Mix.shell().info(@moduledoc)

      :version ->
        Mix.shell().info("Docpub v#{Server.version()}")

      {:run, opts, positional} ->
        case Server.configure(opts, positional) do
          {:ok, info} ->
            print_banner(info)
            {:ok, _} = Application.ensure_all_started(:docpub)
            Process.sleep(:infinity)

          {:error, message} ->
            Mix.raise(message)
        end
    end
  end

  defp print_banner(info) do
    Mix.shell().info("Starting Docpub server...")
    Mix.shell().info("  Vault: #{info.vault_path}")
    Mix.shell().info("  URL:   http://#{info.host}:#{info.port}")
  end
end
