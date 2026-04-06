defmodule DocpubWeb.PageController do
  use DocpubWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
