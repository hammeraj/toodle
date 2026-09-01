import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :toodle, Toodle.Repo,
  database: Path.expand("../toodle_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox,
  journal_mode: :wal,
  busy_timeout: 5000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :toodle, ToodleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "TA4IGTTaNdUdFOuJJUYfBRvK9Nn3FDfYMfDr5GqBAkUadkcRgBjPzESr1s+kzDEU",
  server: false

# The Slack poller's background ticks can't get a Sandbox-allowed DB
# connection in tests -- see Toodle.Application.slack_poller_children/0.
config :toodle, :slack_poller_enabled, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Route Ollama requests through Req.Test instead of a real local server.
config :toodle, Toodle.Llm.Ollama, plug: {Req.Test, Toodle.Llm.Ollama}

# Route Slack requests through Req.Test instead of the real Slack API.
config :toodle, Toodle.Slack.Client, plug: {Req.Test, Toodle.Slack.Client}
