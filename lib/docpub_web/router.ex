defmodule DocpubWeb.Router do
  use DocpubWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DocpubWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :vault_auth do
    plug DocpubWeb.Plugs.VaultAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes (login, auth callback)
  scope "/", DocpubWeb do
    pipe_through :browser

    live "/login", LoginLive
    get "/auth/callback", AuthController, :callback
    post "/auth/logout", AuthController, :logout
  end

  # Protected routes
  scope "/", DocpubWeb do
    pipe_through [:browser, :vault_auth]

    get "/vault_file/*path", VaultFileController, :show
    live "/doc/*path", VaultLive
    live "/", VaultLive
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:docpub, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DocpubWeb.Telemetry
    end
  end
end
