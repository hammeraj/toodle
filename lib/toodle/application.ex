defmodule Toodle.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ToodleWeb.Telemetry,
        Toodle.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:toodle, :ecto_repos), skip: skip_migrations?()}
      ] ++ web_children() ++ mcp_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Toodle.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # `bin/toodle_mcp` boots this app with `:mcp_only` set so it can talk MCP
  # over stdio without also trying to bind port 4000 alongside a
  # simultaneously-running `mix phx.server` — see config/runtime.exs.
  defp web_children do
    if mcp_only?() do
      []
    else
      [
        {DNSCluster, query: Application.get_env(:toodle, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Toodle.PubSub},
        ToodleWeb.Endpoint,
        Toodle.Slack.Poller
      ] ++ desktop_children()
    end
  end

  # A native window wrapping the (loopback-only) endpoint above — see
  # config/runtime.exs for when this is enabled. `url: &ToodleWeb.Endpoint.url/0`
  # is a function, not a static string, because the endpoint binds to an
  # OS-assigned port (`http: [port: 0]`) that isn't known until it's started.
  defp desktop_children do
    if desktop_enabled?() do
      [
        {Desktop.Window,
         [
           app: :toodle,
           id: Toodle.Window,
           title: "Toodle",
           size: {1280, 800},
           url: &ToodleWeb.Endpoint.url/0
         ]}
      ]
    else
      []
    end
  end

  defp mcp_children do
    if mcp_only?(), do: [{Toodle.MCP.Server, transport: :stdio}], else: []
  end

  defp mcp_only?, do: Application.get_env(:toodle, :mcp_only, false)
  defp desktop_enabled?, do: Application.get_env(:toodle, :desktop_enabled, false)

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ToodleWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
