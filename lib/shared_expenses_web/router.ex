defmodule SharedExpensesWeb.Router do
  use SharedExpensesWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SharedExpensesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"referrer-policy" => "no-referrer"}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SharedExpensesWeb do
    pipe_through :browser

    get "/healthz", HealthController, :show
    live "/", HomeLive
    live "/e/:slug", EventLive
    live "/e/:slug/people", EventPeopleLive
    get "/e/:slug/cover", CoverController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", SharedExpensesWeb do
  #   pipe_through :api
  # end
end
