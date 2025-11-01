defmodule CarrierDropletWeb.PageController do
  use CarrierDropletWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
