defmodule Docpub.WhatsNew.Cookie do
  @moduledoc """
  Signed cookie helpers for the What's New last-visit marker.

  The payload is a map with the visitor's last-visit commit SHA and ISO8601
  timestamp, signed with `Phoenix.Token` against the endpoint's secret so the
  cookie is tamper-proof.
  """

  @name "_docpub_last_visit"
  @salt "docpub.whats_new.last_visit"
  @max_age_seconds 60 * 60 * 24 * 30

  @endpoint DocpubWeb.Endpoint

  @type payload :: %{last_visit_date: String.t(), last_git_commit: String.t()}

  @doc "Cookie name."
  @spec name() :: String.t()
  def name, do: @name

  @doc "Cookie options suitable for `Plug.Conn.put_resp_cookie/4`."
  @spec options() :: keyword()
  def options do
    [
      max_age: @max_age_seconds,
      http_only: true,
      same_site: "Lax",
      secure: secure?()
    ]
  end

  @doc "Cookie max-age in seconds."
  @spec max_age() :: non_neg_integer()
  def max_age, do: @max_age_seconds

  @doc "Encode `payload` as a signed cookie value."
  @spec encode(payload()) :: String.t()
  def encode(%{last_visit_date: _, last_git_commit: _} = payload) do
    Phoenix.Token.sign(@endpoint, @salt, payload)
  end

  @doc """
  Decode a signed cookie value.

  Returns `{:ok, payload}` on success or `:error` when the value is missing,
  tampered, or expired.
  """
  @spec decode(String.t() | nil) :: {:ok, payload()} | :error
  def decode(nil), do: :error
  def decode(""), do: :error

  def decode(value) when is_binary(value) do
    case Phoenix.Token.verify(@endpoint, @salt, value, max_age: @max_age_seconds) do
      {:ok, %{last_visit_date: _, last_git_commit: _} = payload} -> {:ok, payload}
      _ -> :error
    end
  end

  def decode(_), do: :error

  defp secure? do
    Application.get_env(:docpub, DocpubWeb.Endpoint, [])
    |> Keyword.get(:url, [])
    |> Keyword.get(:scheme) == "https"
  end
end
