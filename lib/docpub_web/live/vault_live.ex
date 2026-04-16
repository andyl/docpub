defmodule DocpubWeb.VaultLive do
  use DocpubWeb, :live_view

  alias Docpub.Vault
  alias Docpub.Markdown
  alias Docpub.WhatsNew.Summary

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: Docpub.VaultWatcher.subscribe()

    vault_path = Vault.vault_path()
    tree = Vault.list_tree(vault_path)
    flat_tree = Vault.flatten_tree(tree)
    last_visited = session["last_visited_page"]
    {summary, _new_cookie} = Docpub.WhatsNew.summarize(session["whats_new_cookie"])
    {paths, folders, kinds} = build_whats_new_indexes(summary)

    {:ok,
     assign(socket,
       vault_path: vault_path,
       tree: tree,
       flat_tree: flat_tree,
       current_path: nil,
       current_doc: nil,
       current_path_uri: "/",
       rendered_html: nil,
       raw_content: nil,
       mode: :view,
       sidebar_open: true,
       search_query: "",
       search_results: nil,
       last_visited: last_visited,
       page_title: "Home",
       doc_type: nil,
       new_file_name: "",
       expanded_folders: MapSet.new(),
       whats_new_summary: summary,
       whats_new_paths: paths,
       whats_new_folders: folders,
       whats_new_kinds: kinds
     )}
  end

  defp build_whats_new_indexes(%Summary{kind: :diff, files: files}) do
    paths =
      files
      |> Enum.map(& &1.path)
      |> MapSet.new()

    folders =
      files
      |> Enum.flat_map(&ancestor_dirs(&1.path))
      |> MapSet.new()

    kinds =
      Enum.into(files, %{}, fn fc -> {fc.path, fc} end)

    {paths, folders, kinds}
  end

  defp build_whats_new_indexes(_summary), do: {MapSet.new(), MapSet.new(), %{}}

  defp ancestor_dirs(path) do
    path
    |> Path.dirname()
    |> collect_ancestors([])
  end

  defp collect_ancestors(".", acc), do: acc
  defp collect_ancestors("/", acc), do: acc

  defp collect_ancestors(dir, acc) do
    collect_ancestors(Path.dirname(dir), [dir | acc])
  end

  @impl true
  def handle_params(%{"path" => path_parts} = _params, uri, socket) do
    relative_path = Path.join(path_parts)

    socket =
      socket
      |> assign(current_path_uri: request_path(uri))
      |> load_document(relative_path)
      |> assign(sidebar_open: false)

    {:noreply, socket}
  end

  def handle_params(_params, uri, socket) do
    socket = assign(socket, current_path_uri: request_path(uri))
    initial_page = Application.get_env(:docpub, :initial_page)

    target =
      cond do
        initial_page -> initial_page
        socket.assigns.last_visited -> socket.assigns.last_visited
        true -> nil
      end

    case target do
      nil -> {:noreply, socket}
      path -> {:noreply, push_navigate(socket, to: ~p"/doc/#{String.split(path, "/")}")}
    end
  end

  defp load_document(socket, relative_path) do
    vault_path = socket.assigns.vault_path

    # Try with and without .md extension
    {actual_path, doc_type} = resolve_document_path(vault_path, relative_path)

    case doc_type do
      :markdown ->
        case Vault.read_file(vault_path, actual_path) do
          {:ok, content} ->
            current_dir = Path.dirname(actual_path)
            line_marks = whats_new_line_marks(socket, actual_path)

            {:ok, html} =
              Markdown.render(content,
                file_tree: socket.assigns.flat_tree,
                current_dir: current_dir,
                vault_path: vault_path,
                line_marks: line_marks
              )

            expanded = expand_parents(actual_path, socket.assigns.expanded_folders)

            assign(socket,
              current_path: actual_path,
              current_doc: Path.rootname(actual_path),
              rendered_html: html,
              raw_content: content,
              mode: :view,
              page_title: Path.basename(actual_path, ".md"),
              doc_type: :markdown,
              search_results: nil,
              expanded_folders: expanded
            )

          {:error, _} ->
            assign(socket,
              current_path: actual_path,
              current_doc: relative_path,
              rendered_html: nil,
              raw_content: nil,
              mode: :view,
              page_title: "Not Found",
              doc_type: :not_found,
              search_results: nil
            )
        end

      :image ->
        expanded = expand_parents(actual_path, socket.assigns.expanded_folders)

        assign(socket,
          current_path: actual_path,
          current_doc: relative_path,
          rendered_html: nil,
          raw_content: nil,
          mode: :view,
          page_title: Path.basename(actual_path),
          doc_type: :image,
          search_results: nil,
          expanded_folders: expanded
        )

      :pdf ->
        expanded = expand_parents(actual_path, socket.assigns.expanded_folders)

        assign(socket,
          current_path: actual_path,
          current_doc: relative_path,
          rendered_html: nil,
          raw_content: nil,
          mode: :view,
          page_title: Path.basename(actual_path),
          doc_type: :pdf,
          search_results: nil,
          expanded_folders: expanded
        )

      :not_found ->
        assign(socket,
          current_path: relative_path,
          current_doc: relative_path,
          rendered_html: nil,
          raw_content: nil,
          mode: :view,
          page_title: "Not Found",
          doc_type: :not_found,
          search_results: nil
        )
    end
  end

  defp resolve_document_path(vault_path, relative_path) do
    full = Path.join(vault_path, relative_path)

    cond do
      File.regular?(full) ->
        {relative_path, detect_type(relative_path)}

      File.regular?(full <> ".md") ->
        {relative_path <> ".md", :markdown}

      File.regular?(full <> ".markdown") ->
        {relative_path <> ".markdown", :markdown}

      true ->
        {relative_path, :not_found}
    end
  end

  defp detect_type(path) do
    ext = path |> Path.extname() |> String.downcase()

    cond do
      ext in ~w(.md .markdown) -> :markdown
      ext in ~w(.png .jpg .jpeg .gif .svg .webp .bmp) -> :image
      ext in ~w(.pdf) -> :pdf
      true -> :other
    end
  end

  defp whats_new_line_marks(socket, path) do
    summary = socket.assigns.whats_new_summary

    cond do
      summary.kind != :diff ->
        []

      not MapSet.member?(socket.assigns.whats_new_paths, path) ->
        []

      is_nil(summary.from_commit) or is_nil(summary.to_commit) ->
        []

      true ->
        Docpub.WhatsNew.line_hunks(summary.from_commit, summary.to_commit, path)
    end
  end

  defp request_path(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{path: nil} -> "/"
      %URI{path: path, query: nil} -> path
      %URI{path: path, query: q} -> path <> "?" <> q
    end
  end

  defp request_path(_), do: "/"

  defp expand_parents(path, expanded) do
    path
    |> Path.dirname()
    |> expand_ancestors(expanded)
  end

  defp expand_ancestors(".", expanded), do: expanded

  defp expand_ancestors(dir, expanded) do
    expanded = MapSet.put(expanded, dir)
    expand_ancestors(Path.dirname(dir), expanded)
  end

  @impl true
  def handle_event("toggle_mode", _params, socket) do
    new_mode = if socket.assigns.mode == :view, do: :edit, else: :view
    {:noreply, assign(socket, mode: new_mode)}
  end

  def handle_event("save", %{"content" => content}, socket) do
    vault_path = socket.assigns.vault_path
    current_path = socket.assigns.current_path

    case Vault.write_file(vault_path, current_path, content) do
      :ok ->
        current_dir = Path.dirname(current_path)
        line_marks = whats_new_line_marks(socket, current_path)

        {:ok, html} =
          Markdown.render(content,
            file_tree: socket.assigns.flat_tree,
            current_dir: current_dir,
            vault_path: vault_path,
            line_marks: line_marks
          )

        {:noreply,
         socket
         |> assign(raw_content: content, rendered_html: html, mode: :view)
         |> put_flash(:info, "Document saved")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{reason}")}
    end
  end

  def handle_event("delete", _params, socket) do
    vault_path = socket.assigns.vault_path
    current_path = socket.assigns.current_path

    case Vault.delete_file(vault_path, current_path) do
      :ok ->
        tree = Vault.list_tree(vault_path)
        flat_tree = Vault.flatten_tree(tree)

        {:noreply,
         socket
         |> assign(tree: tree, flat_tree: flat_tree)
         |> put_flash(:info, "Document deleted")
         |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete: #{reason}")}
    end
  end

  def handle_event("create", %{"name" => name}, socket) do
    vault_path = socket.assigns.vault_path

    dir =
      case socket.assigns.current_path do
        nil -> ""
        path -> Path.dirname(path)
      end

    file_name = if String.ends_with?(name, ".md"), do: name, else: name <> ".md"
    relative_path = if dir == ".", do: file_name, else: Path.join(dir, file_name)

    case Vault.create_file(vault_path, relative_path, "# #{Path.rootname(name)}\n") do
      :ok ->
        tree = Vault.list_tree(vault_path)
        flat_tree = Vault.flatten_tree(tree)
        doc_path = Path.rootname(relative_path)

        {:noreply,
         socket
         |> assign(tree: tree, flat_tree: flat_tree, new_file_name: "")
         |> push_navigate(to: ~p"/doc/#{String.split(doc_path, "/")}")}

      {:error, :eexist} ->
        {:noreply, put_flash(socket, :error, "File already exists")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create: #{reason}")}
    end
  end

  def handle_event("search", %{"q" => query}, socket) when byte_size(query) > 0 do
    results = Vault.search(socket.assigns.vault_path, query)
    {:noreply, assign(socket, search_query: query, search_results: results)}
  end

  def handle_event("search", _params, socket) do
    {:noreply, assign(socket, search_query: "", search_results: nil)}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, search_query: "", search_results: nil)}
  end

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, sidebar_open: !socket.assigns.sidebar_open)}
  end

  def handle_event("toggle_folder", %{"path" => path}, socket) do
    expanded = socket.assigns.expanded_folders

    expanded =
      if MapSet.member?(expanded, path) do
        MapSet.delete(expanded, path)
      else
        MapSet.put(expanded, path)
      end

    {:noreply, assign(socket, expanded_folders: expanded)}
  end

  def handle_event("update_new_file_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, new_file_name: name)}
  end

  def handle_event("whats_new_mark_file_read", %{"path" => path}, socket) do
    paths = MapSet.delete(socket.assigns.whats_new_paths, path)
    kinds = Map.delete(socket.assigns.whats_new_kinds, path)

    folders =
      socket.assigns.whats_new_folders
      |> Enum.filter(fn folder -> Enum.any?(paths, &String.starts_with?(&1, folder <> "/")) end)
      |> MapSet.new()

    summary = %{socket.assigns.whats_new_summary | files: Enum.reject(socket.assigns.whats_new_summary.files, &(&1.path == path))}

    {:noreply,
     assign(socket,
       whats_new_paths: paths,
       whats_new_kinds: kinds,
       whats_new_folders: folders,
       whats_new_summary: summary
     )}
  end

  @impl true
  def handle_info({:vault_changed, _path, _events}, socket) do
    vault_path = socket.assigns.vault_path
    tree = Vault.list_tree(vault_path)
    flat_tree = Vault.flatten_tree(tree)

    socket = assign(socket, tree: tree, flat_tree: flat_tree)

    # Reload current document if viewing one
    socket =
      if socket.assigns.current_path do
        load_document(socket, socket.assigns.current_path)
      else
        socket
      end

    {:noreply, socket}
  end

  # Helper to generate doc URL path for a tree node
  def doc_path(node) do
    path =
      case node.type do
        :markdown -> Path.rootname(node.path)
        _ -> node.path
      end

    "/doc/#{path}"
  end

  attr :nodes, :list, required: true
  attr :current_path, :string, default: nil
  attr :expanded, :any, required: true
  attr :depth, :integer, default: 0
  attr :whats_new_paths, :any, default: nil
  attr :whats_new_folders, :any, default: nil
  attr :whats_new_kinds, :map, default: %{}

  def tree_nodes(assigns) do
    assigns =
      assigns
      |> assign_new(:whats_new_paths, fn -> MapSet.new() end)
      |> assign_new(:whats_new_folders, fn -> MapSet.new() end)

    ~H"""
    <ul class={[@depth > 0 && "ml-3"]}>
      <%= for node <- @nodes do %>
        <li>
          <%= if node.type == :folder do %>
            <button
              id={"tree-#{node.path}"}
              phx-click="toggle_folder"
              phx-value-path={node.path}
              class="flex items-center gap-1 w-full px-1 py-0.5 rounded text-sm hover:bg-base-300 text-left"
            >
              <.icon
                name={
                  if MapSet.member?(@expanded, node.path),
                    do: "hero-chevron-down-micro",
                    else: "hero-chevron-right-micro"
                }
                class="size-3 shrink-0"
              />
              <.icon name="hero-folder-micro" class="size-4 shrink-0 text-warning" />
              <span class="truncate flex-1">{node.name}</span>
              <.whats_new_marker
                :if={
                  not MapSet.member?(@expanded, node.path) and
                    MapSet.member?(@whats_new_folders, node.path)
                }
                change={:rollup}
                title="Contains recent changes"
              />
            </button>
            <%= if MapSet.member?(@expanded, node.path) do %>
              <.tree_nodes
                nodes={node.children}
                current_path={@current_path}
                expanded={@expanded}
                depth={@depth + 1}
                whats_new_paths={@whats_new_paths}
                whats_new_folders={@whats_new_folders}
                whats_new_kinds={@whats_new_kinds}
              />
            <% end %>
          <% else %>
            <.link
              id={"tree-#{node.path}"}
              navigate={doc_path(node)}
              class={[
                "flex items-center gap-1 w-full px-1 py-0.5 rounded text-sm hover:bg-base-300",
                @current_path == node.path && "bg-primary/10 text-primary font-medium"
              ]}
            >
              <.icon
                name={file_icon(node.type)}
                class={["size-4 shrink-0", file_icon_class(node.type)]}
              />
              <span class="truncate flex-1">{node.name}</span>
              <.whats_new_marker
                :if={MapSet.member?(@whats_new_paths, node.path)}
                change={Map.get(@whats_new_kinds, node.path, %{change: :modified}).change}
                title={whats_new_marker_title(Map.get(@whats_new_kinds, node.path))}
              />
            </.link>
          <% end %>
        </li>
      <% end %>
    </ul>
    """
  end

  defp whats_new_marker_title(nil), do: nil
  defp whats_new_marker_title(%{change: :added}), do: "Added"
  defp whats_new_marker_title(%{change: :modified}), do: "Updated"
  defp whats_new_marker_title(%{change: :deleted}), do: "Deleted"

  defp whats_new_marker_title(%{change: :renamed, previous_path: prev}) when is_binary(prev),
    do: "Renamed from " <> prev

  defp whats_new_marker_title(%{change: :renamed}), do: "Renamed"

  defp file_icon(:markdown), do: "hero-document-text-micro"
  defp file_icon(:image), do: "hero-photo-micro"
  defp file_icon(:pdf), do: "hero-document-micro"
  defp file_icon(_), do: "hero-document-micro"

  defp file_icon_class(:markdown), do: "text-info"
  defp file_icon_class(:image), do: "text-success"
  defp file_icon_class(:pdf), do: "text-error"
  defp file_icon_class(_), do: "text-base-content/50"
end
