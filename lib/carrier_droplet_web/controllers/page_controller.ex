defmodule CarrierDropletWeb.PageController do
  use CarrierDropletWeb, :controller

  def home(conn, _params) do
    # Redirect to dashboard if already logged in
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/dashboard")
    else
      render(conn, :home)
    end
  end
end
