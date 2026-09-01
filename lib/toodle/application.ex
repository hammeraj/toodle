defmodule Toodle.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    cleanup_old_update_backup()

    children =
      [
        ToodleWeb.Telemetry,
        Toodle.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:toodle, :ecto_repos), skip: skip_migrations?()}
      ] ++ web_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Toodle.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Best-effort and fire-and-forget: this is just tidying up a leftover
  # backup directory from Toodle.Updater.Applier, never something worth
  # failing app boot over.
  defp cleanup_old_update_backup do
    Task.start(fn ->
      Toodle.Updater.Applier.cleanup_old_backup()
    end)
  end

  defp web_children do
    [
      {DNSCluster, query: Application.get_env(:toodle, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Toodle.PubSub},
      ToodleWeb.Endpoint
    ] ++
      slack_poller_children() ++
      [
        Toodle.Llm.OllamaServer,
        # Mounted into the router at /mcp (see ToodleWeb.Router) rather than
        # run as a separate process -- same Repo connection pool as the
        # LiveView UI, always available whenever this app is running, nothing
        # extra for Claude to spawn.
        # start: true bypasses anubis_mcp's own auto-detection of "is an HTTP
        # server running" (it checks PHX_SERVER/a Phoenix-internal flag that
        # our release boot path never sets, even though the endpoint is
        # unambiguously up by this point) -- we already know it should start,
        # since this is only reached as part of web_children in the first
        # place.
        {Toodle.MCP.Server, transport: {:streamable_http, start: true}}
      ] ++ desktop_children()
  end

  # Skipped in the test environment: the Ecto Sandbox only grants DB access
  # to a test's own (allowed) processes, and this GenServer's first tick
  # fires within a second of boot -- outside any test's allowance, which
  # crashes it repeatedly and can exceed the supervisor's restart intensity,
  # tearing down the whole app (Repo included) mid test run.
  defp slack_poller_children do
    if Application.get_env(:toodle, :slack_poller_enabled, true) do
      [Toodle.Slack.Poller]
    else
      []
    end
  end

  # A native window wrapping the (loopback-only) endpoint above — see
  # config/runtime.exs for when this is enabled. `url:` is a function, not a
  # static string, because the endpoint binds to an OS-assigned port
  # (`http: [port: 0]`) that isn't known until it's started. It must read
  # the port from `Endpoint.config(:http)` (the real, post-bind value), not
  # `Endpoint.url/0` -- that builds from the static `:url` config, which has
  # no way to know the OS-assigned port and previously pointed the window at
  # a hardcoded port 80 that nothing was listening on (silent white screen:
  # the window opened, but every request into it was refused).
  defp desktop_children do
    if desktop_enabled?() do
      [
        {Desktop.Window,
         [
           app: :toodle,
           id: Toodle.Window,
           title: "Toodle",
           size: {1280, 800},
           url: &desktop_window_url/0
         ]}
      ]
    else
      []
    end
  end

  defp desktop_window_url do
    # Endpoint.config(:http) still reports the static `port: 0` from
    # runtime.exs -- Bandit/ThousandIsland don't rewrite it after binding.
    # server_info/1 asks the actual listener socket for the real OS-assigned
    # port instead.
    {:ok, {_ip, port}} = ToodleWeb.Endpoint.server_info(:http)
    "http://localhost:#{port}/"
  end

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
