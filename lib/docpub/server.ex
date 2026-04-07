defmodule Docpub.Server do
  @moduledoc """
  Shared launcher logic for the Docpub vault viewer server.

  Used by `Mix.Tasks.Docpub.Serve`. Pure data — does not start
  the OTP application itself.
  """

  @switches [
    port: :integer,
    host: :string,
    password: :string,
    initial_page: :string,
    title: :string,
    help: :boolean,
    version: :boolean
  ]

  @default_title "Docpub"

  @doc "Returns the default site title."
  def default_title, do: @default_title

  @doc """
  Returns the configured site title, falling back to the default
  (`#{@default_title}`) when none has been set.
  """
  def title, do: Application.get_env(:docpub, :title) || @default_title

  @doc "Returns the OptionParser switches used by the CLI."
  def switches, do: @switches

  @doc "Returns the version string from `mix.exs` (resolved at compile time)."
  def version, do: unquote(Mix.Project.config()[:version])

  @doc """
  Parses raw argv into one of:

    * `:help`
    * `:version`
    * `{:run, opts, positional}`

  Returns `:help` when no positional argument is given, so that callers
  invoked with no arguments display usage rather than silently serving
  the current working directory.
  """
  def parse_args(args) do
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    cond do
      opts[:help] -> :help
      opts[:version] -> :version
      positional == [] -> :help
      true -> {:run, opts, positional}
    end
  end

  @doc """
  Validates options and writes them into the application environment.

  Returns `{:ok, info}` on success, where `info` is a map describing
  what was configured (used by callers to print a startup banner), or
  `{:error, message}` on validation failure.
  """
  def configure(opts, positional) do
    with {:ok, vault_path} <- resolve_vault_path(positional),
         {:ok, ip} <- maybe_parse_ip(opts[:host]) do
      Application.put_env(:docpub, :vault_path, vault_path)
      Application.put_env(:docpub, :password, opts[:password])
      Application.put_env(:docpub, :title, opts[:title] || @default_title)

      if opts[:initial_page] do
        Application.put_env(:docpub, :initial_page, opts[:initial_page])
      end

      update_endpoint(fn config ->
        config
        |> Keyword.put(:server, true)
        |> maybe_put_http(:port, opts[:port])
        |> maybe_put_http(:ip, ip)
      end)

      {:ok,
       %{
         vault_path: vault_path,
         host: opts[:host] || "localhost",
         port: opts[:port] || 4000,
         password: opts[:password] != nil,
         title: opts[:title] || @default_title
       }}
    end
  end

  defp resolve_vault_path([]),
    do: {:error, "Vault path is required. Pass `.` to serve the current directory."}

  defp resolve_vault_path([path | _]) do
    expanded = Path.expand(path)

    if File.dir?(expanded) do
      {:ok, expanded}
    else
      {:error, "Vault path does not exist or is not a directory: #{expanded}"}
    end
  end

  defp maybe_parse_ip(nil), do: {:ok, nil}
  defp maybe_parse_ip("0.0.0.0"), do: {:ok, {0, 0, 0, 0}}
  defp maybe_parse_ip("localhost"), do: {:ok, {127, 0, 0, 1}}

  defp maybe_parse_ip(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> {:error, "Invalid host address: #{host}"}
    end
  end

  defp update_endpoint(fun) do
    config = Application.get_env(:docpub, DocpubWeb.Endpoint, [])
    Application.put_env(:docpub, DocpubWeb.Endpoint, fun.(config))
  end

  defp maybe_put_http(config, _key, nil), do: config

  defp maybe_put_http(config, key, value) do
    http = config |> Keyword.get(:http, []) |> Keyword.put(key, value)
    Keyword.put(config, :http, http)
  end
end
