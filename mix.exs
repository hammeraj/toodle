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
              &disable_distribution/1,
              &stamp_build_sha/1,
              &bundle_ollama/1,
              &Desktop.Deployment.generate_installer/1,
              &patch_macos_bundle/1
            ]
          ]
        ]
      ]
    else
      []
    end
  end

  # Toodle is a single-user local desktop app -- it never needs to cluster
  # with another node, ever. The release's default env.bat/env.sh (rendered
  # at :assemble time) leaves RELEASE_DISTRIBUTION unset, which makes the
  # launcher fall back to `-sname <app>`: a real, connectable Erlang node.
  # Pin RELEASE_DISTRIBUTION=none here instead so it's never one at all.
  #
  # This only actually lands on Windows: win32/run.bat.eex calls env.bat
  # before falling back to sname, so what we write here sticks. macOS's
  # launcher (:release_first's Contents/MacOS/run, from
  # desktop_deployment's rel/linux/run.eex) never sources env.sh at all --
  # it inlines a hardcoded `export RELEASE_DISTRIBUTION=name` instead, so
  # this write is silently ignored there. Confirmed hands-on: with only
  # this step in place, `epmd -names` still showed a live, connectable node
  # after launch. See patch_macos_bundle/1 below for the fix that actually
  # takes effect on macOS.
  defp disable_distribution(release) do
    releases_dir = Path.join([release.path, "releases", release.version])

    File.write!(Path.join(releases_dir, "env.bat"), """
    @echo off
    set RELEASE_DISTRIBUTION=none
    """)

    File.write!(Path.join(releases_dir, "env.sh"), """
    #!/bin/sh
    export RELEASE_DISTRIBUTION=none
    """)

    release
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

  # Two independent post-packaging fixes for the finished macOS .app bundle
  # that both require the same expensive re-sign + re-dmg pass, so they're
  # combined into one step to only pay for that pass once:
  #
  #   1. Desktop.Deployment bundles every dylib/so a NIF transitively
  #      depends on so the app runs without Homebrew installed -- but its
  #      dependency walker (Package.MacOS.find_deps) only recognizes and
  #      rewrites dependencies recorded as an absolute /opt/homebrew (or
  #      /usr/local) path. Some Homebrew formulas record *their own*
  #      inter-library dependencies as a bare `@rpath/<name>.dylib` instead
  #      (confirmed hands-on: webp 1.6.0's libwebp.7.dylib depends on
  #      libsharpyuv.0.dylib this way). Those deps are invisible to the
  #      walker, never get bundled, and the app then crashes on launch the
  #      instant something dlopen's the referencing library -- for Toodle
  #      that's wx's image codec support, so *every* launch.
  #
  #   2. disable_distribution/1 above doesn't actually take effect on macOS
  #      (see its comment) -- the launcher script this platform actually
  #      uses hardcodes RELEASE_DISTRIBUTION=name. Patch that script
  #      directly once it exists (it's generated by
  #      Desktop.Deployment.generate_installer/1, so there's nothing to
  #      patch before this step runs).
  #
  # Both patches are no-ops the moment their root cause is fixed upstream
  # (Homebrew/desktop_deployment for #1, desktop_deployment for #2), and
  # the re-sign/re-dmg pass only runs at all if something was actually
  # patched.
  defp patch_macos_bundle(release) do
    case :os.type() do
      {:unix, :darwin} -> do_patch_macos_bundle(release)
      _ -> :ok
    end

    release
  end

  defp do_patch_macos_bundle(release) do
    build_root = Path.join([release.path, "..", ".."]) |> Path.expand()

    case Path.wildcard(Path.join(build_root, "*.app")) do
      [app_root | _] -> patch_app_bundle(app_root, build_root, release.version)
      [] -> :ok
    end
  end

  defp patch_app_bundle(app_root, build_root, version) do
    patched_deps? = patch_missing_rpath_deps(app_root)
    patched_dist? = patch_run_script_distribution(app_root)

    if patched_deps? or patched_dist? do
      alias Desktop.Deployment.Package.MacOS

      IO.puts(
        "Patched macOS bundle (deps: #{patched_deps?}, distribution: #{patched_dist?}), " <>
          "re-signing and re-packaging"
      )

      developer_id = MacOS.find_developer_id()
      if developer_id, do: MacOS.codesign(app_root), else: MacOS.adhoc_sign(app_root)

      dmg = rebuild_dmg(app_root, build_root, version)
      if developer_id, do: MacOS.package_sign(developer_id, dmg)
    end
  end

  defp patch_run_script_distribution(app_root) do
    run_script = Path.join(app_root, "Contents/MacOS/run")
    content = File.read!(run_script)

    patched =
      String.replace(
        content,
        "export RELEASE_DISTRIBUTION=name",
        "export RELEASE_DISTRIBUTION=none"
      )

    if patched != content do
      File.write!(run_script, patched)
      true
    else
      false
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
  # only reached when patch_macos_bundle/1 actually patched the bundle, so
  # the dmg it already produced reflects the patch too rather than the
  # stale pre-patch copy.
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

  # Embeds a bundled Ollama runtime (see Toodle.Llm.OllamaServer) into the
  # release's priv dir, macOS-only, and only when TOODLE_OLLAMA_BUNDLE_DIR
  # points at a pre-staged `bin/` directory (see
  # .github/workflows/desktop-build.yml's "Fetch bundled Ollama runtime"
  # step -- fetching and stripping the runtime here on every local `mix
  # release` would be both slow and unwanted for anyone not testing this
  # specifically). A no-op release step otherwise, same convention as
  # make_release_writable/1 and disable_distribution/1 above.
  #
  # The model itself is deliberately *not* bundled here -- it's pulled at
  # runtime by Toodle.Llm.Ollama.ensure_model/1 into
  # Toodle.Llm.OllamaServer.models_dir/0, which lives outside the release
  # entirely so it survives updates (Toodle.Updater.Applier replaces this
  # whole .app wholesale on every update; bundling the ~1GB model here
  # would force a redownload of it with every release regardless of
  # whether the model itself had changed).
  #
  # This step runs *before* Desktop.Deployment.generate_installer/1
  # rather than patching the finished .app after the fact (contrast with
  # patch_macos_bundle/1 below): anything already sitting in
  # lib/toodle-<vsn>/priv/ at that point gets carried into the .app and
  # ad-hoc/Developer-ID signed by that same pass, confirmed hands-on
  # against another priv/ NIF (exqlite's sqlite3_nif.so) in the existing
  # baseline build -- no separate re-sign/re-dmg dance needed here.
  defp bundle_ollama(release) do
    case {:os.type(), System.get_env("TOODLE_OLLAMA_BUNDLE_DIR")} do
      {{:unix, :darwin}, dir} when is_binary(dir) and dir != "" -> do_bundle_ollama(release, dir)
      _ -> :ok
    end

    release
  end

  defp do_bundle_ollama(release, source_dir) do
    dest = Path.join([release.path, "lib", "toodle-#{release.version}", "priv", "ollama"])
    File.rm_rf!(dest)
    File.mkdir_p!(dest)

    File.cp_r!(Path.join(source_dir, "bin"), Path.join(dest, "bin"))

    # cp_r! preserves source file modes, but be explicit that the entry
    # points stay executable regardless of how the bundle dir was
    # staged/cached upstream.
    for bin <- ["ollama", "llama-server", "llama-quantize"] do
      path = Path.join([dest, "bin", bin])
      if File.exists?(path), do: File.chmod!(path, 0o755)
    end

    thin_to_arm64(Path.join(dest, "bin"))

    IO.puts("Bundled Ollama runtime from #{source_dir} into #{dest}")
  end

  # Ollama's official macOS release ships these three as universal binaries
  # with the x86_64 slice listed *first* in the fat header -- and unlike a
  # shell or LaunchServices, `Port.open({:spawn_executable, ...})`
  # (Toodle.Llm.OllamaServer's launch mechanism) doesn't reliably resolve a
  # fat binary to the host's native slice, observed hands-on to run the
  # x86_64 slice under Rosetta on real Apple Silicon hardware. That slice
  # needs the exact CPU backend plugins (`libggml-cpu-*.so`) the CI build
  # deliberately strips (see desktop-build.yml) -- producing a
  # "make_cpu_buft_list: no CPU backend found" crash the arm64 slice never
  # hits, since it has its CPU/Metal backend statically compiled in. Since
  # Toodle only ever ships arm64 (see the "Verify arm64 build" CI step),
  # thinning these to arm64-only removes the ambiguity entirely rather than
  # depending on whatever spawned the process picking the right slice.
  # Re-signed along with everything else by the release's own signing pass
  # (see MacOS.codesign/1 and MacOS.adhoc_sign/1), so no re-sign needed
  # here.
  defp thin_to_arm64(bin_dir) do
    for bin <- ["ollama", "llama-server", "llama-quantize"] do
      path = Path.join(bin_dir, bin)

      if File.exists?(path) do
        thinned = path <> ".arm64"
        {_output, 0} = System.cmd("lipo", ["-thin", "arm64", "-output", thinned, path])
        File.rename!(thinned, path)
        File.chmod!(path, 0o755)
      end
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
