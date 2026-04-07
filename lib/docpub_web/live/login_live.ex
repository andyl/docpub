defmodule DocpubWeb.LoginLive do
  use DocpubWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Login", form: to_form(%{"password" => ""}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-center min-h-[60vh]">
        <div class="card w-full max-w-sm bg-base-200 shadow-xl">
          <div class="card-body">
            <h2 class="card-title justify-center">
              <.icon name="hero-lock-closed" class="size-6" /> Docpub Login
            </h2>
            <.form for={@form} phx-submit="login" class="space-y-4 mt-4">
              <.input field={@form[:password]} type="password" label="Password" required />
              <button type="submit" class="btn btn-primary w-full">Sign in</button>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("login", %{"password" => password}, socket) do
    configured_password = Application.get_env(:docpub, :password)

    if Plug.Crypto.secure_compare(password, configured_password || "") do
      {:noreply,
       socket
       |> put_flash(:info, "Welcome!")
       |> redirect(to: ~p"/auth/callback?password=#{password}")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Invalid password")
       |> assign(form: to_form(%{"password" => ""}))}
    end
  end
end
