defmodule Toodle.MixProject do
  use Mix.Project

  @webview_ref "cac66d8aeeddf488d8046db2fd254ac93b5411cb"

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
      # instead of relying on those defaults.
      desktop_package: [
        name: "Toodle",
        name_long: "Toodle",
        identifier: "com.hammeraj.toodle",
        description: "A local-first task manager with MCP, Slack, and Linear integration.",
        icon: "priv/icon.png"
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

  # The native webview host (used for :host_first macOS packaging) only
  # supports macOS so far — Windows support is unimplemented upstream, and
  # Windows packaging doesn't need it. Pinned to a commit SHA rather than a
  # branch: this dep isn't published to Hex and has no tagged releases yet.
  defp webview_deps do
    if match?({:unix, :darwin}, :os.type()) do
      [{:desktop_webview, github: "elixir-desktop/webview", ref: @webview_ref}]
    else
      []
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
            steps: [:assemble, &Desktop.Deployment.generate_installer/1]
          ]
        ]
      ]
    else
      []
    end
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
        # override: true because desktop_webview's own mix.exs declares
        # `desktop` as a local `path:` dep (for its own monorepo dev setup)
        # with override: true — our git dep must assert the override too or
        # Mix treats the two declarations as an unresolved conflict.
        {:desktop, github: "elixir-desktop/desktop", override: true},
        {:desktop_deployment, github: "elixir-desktop/deployment"},
        {:exqlite, github: "elixir-desktop/exqlite", override: true},
        # desktop_deployment pulls in httpoison ~> 2.3 -> hackney ~> 1.21,
        # which has known CVEs (incl. one HIGH severity). httpoison 3.0
        # requires the patched hackney 4.x line — force both up.
        {:httpoison, "~> 3.0", override: true},
        {:hackney, "~> 4.0", override: true}
      ] ++ webview_deps()
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
