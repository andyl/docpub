defmodule DocpubWeb.VaultFileController do
  use DocpubWeb, :controller

  @doc """
  Serves raw files (images, PDFs, etc.) from the vault directory.
  Guards against path traversal.
  """
  def show(conn, %{"path" => path_parts}) do
    relative_path = Path.join(path_parts)
    vault_path = Docpub.Vault.vault_path()
    full_path = Path.join(vault_path, relative_path)

    if path_traversal?(relative_path) or not within_vault?(vault_path, full_path) do
      conn
      |> put_status(:forbidden)
      |> text("Forbidden")
    else
      if File.regular?(full_path) do
        content_type = MIME.from_path(full_path)

        conn
        |> put_resp_content_type(content_type)
        |> send_file(200, full_path)
      else
        conn
        |> put_status(:not_found)
        |> text("Not found")
      end
    end
  end

  defp path_traversal?(path), do: String.contains?(path, "..")

  defp within_vault?(vault_path, full_path) do
    resolved_base = Path.expand(vault_path)
    resolved_full = Path.expand(full_path)
    String.starts_with?(resolved_full, resolved_base)
  end
end
