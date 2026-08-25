defmodule ToodleWeb.Router do
  use ToodleWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ToodleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ToodleWeb do
    pipe_through :browser

    live_session :default do
      live "/", TaskLive.Board, :index
      live "/tasks/new", TaskLive.Form, :new
      live "/tasks/:id", TaskLive.Show, :show
      live "/tasks/:id/edit", TaskLive.Form, :edit

      live "/projects", ProjectLive.Index, :index
      live "/projects/new", ProjectLive.Form, :new
      live "/projects/:id/edit", ProjectLive.Form, :edit

      live "/settings", SettingsLive.Index, :index
    end
  end

  # Same process, same Repo connection pool as the LiveView UI above --
  # Claude talks to whatever Toodle instance is actually running, no
  # separate OS process or transport of its own. See Toodle.MCP.Server.
  scope "/mcp" do
    pipe_through :api

    forward "/", Anubis.Server.Transport.StreamableHTTP.Plug, server: Toodle.MCP.Server
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:toodle, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ToodleWeb.Telemetry
    end
  end
end
