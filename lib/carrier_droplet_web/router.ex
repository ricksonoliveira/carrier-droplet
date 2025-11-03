defmodule CarrierDropletWeb.Router do
  use CarrierDropletWeb, :router
  use Phoenix.VerifiedRoutes, endpoint: CarrierDropletWeb.Endpoint, router: __MODULE__

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CarrierDropletWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :require_authenticated_user do
    plug :require_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CarrierDropletWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # OAuth routes
  scope "/auth", CarrierDropletWeb do
    pipe_through :browser

    get "/logout", AuthController, :logout
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
  end

  # Authenticated routes
  scope "/", CarrierDropletWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{CarrierDropletWeb.UserAuth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive
      live "/categories/new", CategoryLive.New
      live "/categories/:id/edit", CategoryLive.Edit
      live "/categories/:id", CategoryLive.Show
    end
  end

  # Oban Web UI (authenticated)
  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user]

    import Oban.Web.Router
    oban_dashboard("/oban")
  end

  # Other scopes may use custom stacks.
  # scope "/api", CarrierDropletWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:carrier_droplet, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CarrierDropletWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Authentication plugs
  defp fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)

    if user_id do
      user = CarrierDroplet.Accounts.get_user(user_id)
      assign(conn, :current_user, user)
    else
      assign(conn, :current_user, nil)
    end
  end

  defp require_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end
end
