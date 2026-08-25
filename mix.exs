defmodule Toodle.MixProject do
  use Mix.Project

  def project do
    [
      app: :toodle,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      # This repo is built from both WSL and native Windows (desktop
      # packaging needs a native Windows OTP build). Compiled artifacts
      # aren't portable between the two, so each gets its own build/deps
      # directory rather than fighting over `_build`/`deps`.
      deps_path: deps_path(),
      build_path: build_path(),
      # Desktop.Deployment falls back to generic "ElixirApp" branding
      # (name derived from the :app atom, but a "The X" long name, default
      # description/identifier) when this is unset — pin it explicitly
      # instead of relying on those defaults. macos_layout: :release_first
      # uses the desktop package's wx backend rather than :host_first's
      # native webview host — elixir-desktop/webview is early/unreleased
      # (no Hex package, no tags) and unconditionally requests microphone
      # access on launch for an unrelated demo app's calling feature; wx
      # is the mature, boring, already-proven-out path.
      desktop_package: [
        name: "Toodle",
        name_long: "Toodle",
        identifier: "com.hammeraj.toodle",
        description: "A local-first task manager with MCP, Slack, and Linear integration.",
        icon: "priv/icon.png",
        macos_layout: :release_first
      ]
    ] ++ releases_config()
  end

  # The `desktop` package's own OTP application unconditionally tries to
  # init a native GUI backend (wx) the moment it starts — before any of our
  # own code runs, and with no headless opt-out. That makes it un-bootable
  # on a display-less machine (WSL, CI), so it — and the release/installer
  # config that depends on it — are only declared as dependencies at all on
  # platforms that can actually host a desktop window. WSL/Linux dev keeps
  # using the regular hex `exqlite`/`hackney`.
  defp desktop_platform? do
    case :os.type() do
      {:win32, _} -> true
      {:unix, :darwin} -> true
      _ -> false
    end
  end

  defp deps_path do
    case :os.type() do
      {:win32, _} -> "deps_windows"
      _ -> "deps"
    end
  end

  defp build_path do
    case :os.type() do
      {:win32, _} -> "_build_windows"
      _ -> "_build"
    end
  end

  defp releases_config do
    if desktop_platform?() do
      [
        releases: [
          toodle: [
            applications: [runtime_tools: :permanent, ssl: :permanent],
            steps: [
              :assemble,
              &add_mcp_entrypoint/1,
              &Desktop.Deployment.generate_installer/1
            ]
          ]
        ]
      ]
    else
      []
    end
  end

  # Drops an `mcp` sibling next to the release's own `bin/toodle` launcher.
  # desktop_deployment copies the whole `bin/` dir into the packaged app
  # (Contents/Resources/bin on macOS's :release_first layout, bin\ on
  # Windows), so this ships in every installer without a separate packaging
  # step. It lets Claude talk to the *installed app* directly -- no dev
  # checkout or Elixir install required, just the DMG/installer someone
  # already has.
  #
  # Two things it must do differently from a normal `bin/toodle start`:
  #   - TOODLE_MCP_ONLY=1 (see config/runtime.exs) skips the web/desktop UI
  #     entirely and boots straight into stdio MCP mode instead.
  #   - RELEASE_DISTRIBUTION=none turns off Erlang distribution. Without it,
  #     this process tries to register the same node name as an
  #     already-running GUI instance and gets refused outright -- verified
  #     hands-on (Windows release binary): the GUI app and this MCP-only
  #     process boot concurrently against the same on-disk SQLite database
  #     (already WAL-mode for exactly this) without conflict once
  #     distribution is disabled, but conflict immediately if it isn't.
  defp add_mcp_entrypoint(release) do
    bin_dir = Path.join(release.path, "bin")

    case :os.type() do
      {:win32, _} ->
        File.write!(Path.join(bin_dir, "toodle_mcp.bat"), """
        @echo off
        set TOODLE_MCP_ONLY=1
        set RELEASE_DISTRIBUTION=none
        call "%~dp0toodle.bat" start
        """)

      _ ->
        path = Path.join(bin_dir, "toodle_mcp")

        File.write!(path, """
        #!/usr/bin/env bash
        # Spawned by an MCP client (Claude Desktop/Code) to talk to this
        # installed app over stdio -- see add_mcp_entrypoint/1 in mix.exs.
        set -euo pipefail
        cd "$(dirname "$0")"
        export TOODLE_MCP_ONLY=1
        export RELEASE_DISTRIBUTION=none
        exec ./toodle start
        """)

        File.chmod!(path, 0o755)
    end

    release
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Toodle.Application, []},
      extra_applications:
        [:logger, :runtime_tools, :ssl, :crypto, :sasl, :tools, :inets] ++ asset_apps(Mix.env())
    ]
  end

  # Asset watchers (esbuild/tailwind) only need to be running applications in dev.
  defp asset_apps(:dev), do: [:esbuild, :tailwind]
  defp asset_apps(_), do: []

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.12"},
      {:anubis_mcp, "~> 2.0"},
      {:req, "~> 0.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ] ++ desktop_deps()
  end

  defp desktop_deps do
    if desktop_platform?() do
      [
        {:desktop, github: "elixir-desktop/desktop"},
        {:desktop_deployment, github: "elixir-desktop/deployment"},
        {:exqlite, github: "elixir-desktop/exqlite", override: true},
        # desktop_deployment pulls in httpoison ~> 2.3 -> hackney ~> 1.21,
        # which has known CVEs (incl. one HIGH severity). httpoison 3.0
        # requires the patched hackney 4.x line — force both up.
        {:httpoison, "~> 3.0", override: true},
        {:hackney, "~> 4.0", override: true}
      ]
    else
      []
    end
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind toodle", "esbuild toodle"],
      "assets.deploy": [
        "tailwind toodle --minify",
        "esbuild toodle --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
