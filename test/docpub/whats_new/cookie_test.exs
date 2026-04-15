defmodule Docpub.WhatsNew.CookieTest do
  use ExUnit.Case, async: true

  alias Docpub.WhatsNew.Cookie

  @payload %{last_visit_date: "2026-04-15T00:00:00Z", last_git_commit: "abc123"}

  test "round-trips a payload" do
    encoded = Cookie.encode(@payload)
    assert {:ok, decoded} = Cookie.decode(encoded)
    assert decoded.last_visit_date == @payload.last_visit_date
    assert decoded.last_git_commit == @payload.last_git_commit
  end

  test "nil/empty values do not verify" do
    assert Cookie.decode(nil) == :error
    assert Cookie.decode("") == :error
  end

  test "tampered values do not verify" do
    encoded = Cookie.encode(@payload)
    tampered = encoded <> "x"
    assert Cookie.decode(tampered) == :error
  end

  test "options include http_only and Lax same-site" do
    opts = Cookie.options()
    assert Keyword.get(opts, :http_only) == true
    assert Keyword.get(opts, :same_site) == "Lax"
    assert Keyword.get(opts, :max_age) == 60 * 60 * 24 * 30
  end
end
