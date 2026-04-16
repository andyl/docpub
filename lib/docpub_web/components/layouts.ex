defmodule DocpubWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DocpubWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :whats_new_summary, :map, default: nil
  attr :whats_new_toast_dismissed, :boolean, default: false
  attr :current_path_uri, :string, default: "/"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign_new(assigns, :site_title, fn -> Docpub.Server.title() end)

    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 h-14 min-h-0 border-b border-base-300 bg-base-100">
      <div class="flex-1">
        <a href="/" class="flex items-center gap-2 text-lg font-bold">
          <.icon name="hero-book-open" class="size-5 text-primary" />{@site_title}
        </a>
      </div>
    </header>

    <div class="flex-1 overflow-hidden">
      {render_slot(@inner_block)}
    </div>

    <.whats_new_toast
      :if={@whats_new_summary}
      summary={@whats_new_summary}
      dismissed={@whats_new_toast_dismissed}
      redirect_to={@current_path_uri}
    />

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
