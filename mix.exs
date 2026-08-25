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
              &make_release_writable/1,
              &stamp_build_sha/1,
              &Desktop.Deployment.generate_installer/1,
              &fixup_rpath_deps/1
            ]
          ]
        ]
      ]
    else
      []
    end
  end

  # Some Erlang distributions (confirmed with Homebrew's arm64 build) ship a
  # few erts/bin scripts (e.g. `start`) read-only, and :assemble preserves
  # that permission bit when it copies erts into the release. Desktop.Deployment's
  # macOS codesigning pass then fails outright the first time it reaches one of
  # those files -- `codesign` needs to write to whatever it signs. Force the
  # whole release tree writable before that step runs; harmless on Windows,
  # where there's nothing to codesign but this step still runs.
  defp make_release_writable(release) do
    case :os.type() do
      {:unix, :darwin} -> System.cmd("chmod", ["-R", "u+w", release.path])
      _ -> :ok
    end

    release
  end

  # Desktop.Deployment bundles every dylib/so a NIF transitively depends on
  # so the app runs without Homebrew installed -- but its dependency walker
  # (Package.MacOS.find_deps) only recognizes and rewrites dependencies
  # recorded as an absolute /opt/homebrew (or /usr/local) path. Some Homebrew
  # formulas record *their own* inter-library dependencies as a bare
  # `@rpath/<name>.dylib` instead (confirmed hands-on: webp 1.6.0's
  # libwebp.7.dylib depends on libsharpyuv.0.dylib this way). Those deps are
  # invisible to the walker, never get bundled, and the app then crashes on
  # launch the instant something dlopen's the referencing library -- for
  # Toodle that's wx's image codec support, so *every* launch. Sweep the
  # finished bundle for exactly this pattern and patch it up the same way
  # Desktop.Deployment handles every other bundled dependency: copy the
  # missing library alongside its referrer and repoint the load command at
  # @loader_path. Re-signs and re-packages only if a patch was actually
  # needed, so this is a no-op the moment upstream (either Homebrew or
  # desktop_deployment) fixes the root cause.
  defp fixup_rpath_deps(release) do
    case :os.type() do
      {:unix, :darwin} -> do_fixup_rpath_deps(release)
      _ -> :ok
    end

    release
  end

  defp do_fixup_rpath_deps(release) do
    build_root = Path.join([release.path, "..", ".."]) |> Path.expand()

    case Path.wildcard(Path.join(build_root, "*.app")) do
      [app_root | _] -> patch_app_bundle(app_root, build_root, release.version)
      [] -> :ok
    end
  end

  defp patch_app_bundle(app_root, build_root, version) do
    if patch_missing_rpath_deps(app_root) do
      alias Desktop.Deployment.Package.MacOS

      IO.puts(
        "Patched @rpath-only dependencies missed by Desktop.Deployment, re-signing and re-packaging"
      )

      developer_id = MacOS.find_developer_id()
      if developer_id, do: MacOS.codesign(app_root), else: MacOS.adhoc_sign(app_root)

      dmg = rebuild_dmg(app_root, build_root, version)
      if developer_id, do: MacOS.package_sign(developer_id, dmg)
    end
  end

  defp patch_missing_rpath_deps(app_root) do
    app_root
    |> macho_files()
    |> Enum.reduce(false, fn object, patched? ->
      dir = Path.dirname(object)

      missing =
        object |> unresolved_rpath_deps() |> Enum.reject(&File.exists?(Path.join(dir, &1)))

      Enum.each(missing, &copy_and_repoint_dep(object, dir, &1))
      patched? or missing != []
    end)
  end

  defp macho_files(app_root) do
    libs = Path.wildcard(Path.join(app_root, "**/*.{dylib,so}"))

    bins =
      Path.join(app_root, "**")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        File.regular?(path) and not String.contains?(Path.basename(path), ".") and
          Bitwise.band(0o100, File.stat!(path).mode) != 0
      end)

    Enum.uniq(libs ++ bins)
  end

  defp unresolved_rpath_deps(object) do
    case System.cmd("otool", ["-L", object]) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.drop(1)
        |> Enum.map(fn line -> line |> String.trim() |> String.split(" ") |> List.first() end)
        |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "@rpath/")))
        |> Enum.map(&String.replace_prefix(&1, "@rpath/", ""))

      _ ->
        []
    end
  end

  defp copy_and_repoint_dep(object, dir, name) do
    source =
      find_on_disk(name) ||
        raise """
        #{object} depends on @rpath/#{name}, which Desktop.Deployment didn't bundle \
        (it only follows absolute-path dependencies), and #{name} wasn't found under \
        /opt/homebrew or /usr/local either. Install it via Homebrew, or extend \
        find_on_disk/1 in mix.exs.
        """

    dest = Path.join(dir, name)
    if not File.exists?(dest), do: File.cp!(source, dest)
    System.cmd("install_name_tool", ["-change", "@rpath/#{name}", "@loader_path/#{name}", object])
  end

  defp find_on_disk(name) do
    [
      "/opt/homebrew/opt/*/lib/#{name}",
      "/opt/homebrew/lib/#{name}",
      "/opt/homebrew/Cellar/*/*/lib/#{name}",
      "/usr/local/opt/*/lib/#{name}",
      "/usr/local/lib/#{name}",
      "/usr/local/Cellar/*/*/lib/#{name}"
    ]
    |> Enum.find_value(fn glob ->
      case Path.wildcard(glob) do
        [path | _] -> path
        [] -> nil
      end
    end)
  end

  # Mirrors Desktop.Deployment.Package.MacOS's own (private) dmg builder --
  # only reached when fixup_rpath_deps/1 actually patched the bundle, so the
  # dmg it already produced reflects the patch too rather than the stale
  # pre-patch copy.
  defp rebuild_dmg(app_root, build_root, version) do
    name = Path.basename(app_root, ".app")
    out_file = Path.join(build_root, "#{name}-#{version}.dmg")
    tmp_file = out_file <> ".tmp.#{:rand.uniform(1_000_000_000)}.dmg"
    volume = Path.join("/Volumes", name)

    File.rm(out_file)

    {_, 0} =
      System.cmd("hdiutil", [
        "create",
        "-srcfolder",
        app_root,
        "-volname",
        name,
        "-fs",
        "HFS+",
        "-layout",
        "NONE",
        "-format",
        "UDRW",
        tmp_file
      ])

    if File.exists?(volume), do: System.cmd("hdiutil", ["detach", volume])
    {_, 0} = System.cmd("hdiutil", ["attach", tmp_file])
    System.cmd("ln", ["-s", "/Applications", Path.join(volume, "Applications")])
    System.cmd("hdiutil", ["detach", volume])
    {_, 0} = System.cmd("hdiutil", ["convert", tmp_file, "-format", "ULFO", "-o", out_file])
    File.rm(tmp_file)

    out_file
  end

  # The CI-published GitHub release reuses a single rolling "latest" tag on
  # every build (see .github/workflows/desktop-build.yml) rather than
  # distinct version tags, so there's no version number for Toodle.Updater
  # to compare against -- only a commit SHA, embedded in that release's
  # body. This stamps the *local* build's own SHA into the release so it has
  # something to compare that against at runtime (Toodle.Updater.local_sha/0).
  defp stamp_build_sha(release) do
    sha =
      case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
        {sha, 0} -> String.trim(sha)
        _ -> "unknown"
      end

    priv_dir = Path.join([release.path, "lib", "toodle-#{release.version}", "priv"])
    File.write!(Path.join(priv_dir, "build_sha.txt"), sha)

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
