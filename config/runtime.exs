import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/toodle start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :toodle, ToodleWeb.Endpoint, server: true
end

# `bin/toodle_mcp` sets this so the app boots without the web endpoint and
# talks MCP over stdio instead — see lib/toodle/application.ex. Logger must
# not write to stdout in this mode: anything other than MCP protocol frames
# on stdout corrupts the stdio channel from the client's point of view.
if System.get_env("TOODLE_MCP_ONLY") do
  config :toodle, :mcp_only, true
  config :logger, :default_handler, config: [type: :standard_error]
end

# The packaged app always runs in desktop mode (a native window wrapping the
# local-only web endpoint); TOODLE_DESKTOP lets dev mode opt into it too, to
# test the window without a full release build.
desktop_enabled =
  case System.get_env("TOODLE_DESKTOP") do
    "1" -> true
    "0" -> false
    nil -> config_env() == :prod
  end

config :toodle, :desktop_enabled, desktop_enabled

config :toodle, ToodleWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :toodle, ToodleWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/toodle_web/router\.ex$",
        ~r"lib/toodle_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  # Toodle's "prod" is a packaged desktop app, not a public server: local
  # single user, loopback-only, no ops team to hand it a DATABASE_PATH or
  # SECRET_KEY_BASE — so both are resolved automatically instead of required.
  database_path = System.get_env("DATABASE_PATH") || Toodle.Paths.database_path()

  config :toodle, Toodle.Repo,
    database: database_path,
    pool_size: 1,
    journal_mode: :wal,
    busy_timeout: 5000

  secret_key_base = System.get_env("SECRET_KEY_BASE") || Toodle.Paths.secret_key_base()

  config :toodle, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :toodle, ToodleWeb.Endpoint,
    server: true,
    # No `port:` here -- it's OS-assigned (see `http:` below) and unknowable
    # at config time. Nothing reads Endpoint.url/0's port; the desktop
    # window gets the real bound port via Endpoint.server_info/1 instead
    # (see Toodle.Application.desktop_window_url/0).
    url: [host: "localhost", scheme: "http"],
    http: [ip: {127, 0, 0, 1}, port: 0],
    secret_key_base: secret_key_base
end
