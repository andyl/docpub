defmodule DocpubWeb.PageController do
  use DocpubWeb, :controller

  def home(conn, _params) do
    initial_page = Application.get_env(:docpub, :initial_page)
    last_visited = get_session(conn, :last_visited_page)

    target =
      cond do
        initial_page -> ~p"/doc/#{String.split(initial_page, "/")}"
        last_visited -> ~p"/doc/#{String.split(last_visited, "/")}"
        true -> ~p"/doc/index"
      end

    redirect(conn, to: target)
  end
end
