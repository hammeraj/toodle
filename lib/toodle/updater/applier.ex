defmodule Toodle.Updater.Applier do
  @moduledoc """
  Replaces the running installed app with a freshly-downloaded installer,
  then quits so the new version takes over on relaunch.

  Neither platform lets you overwrite files (or, on Windows, delete a
  directory containing) an executable that's still running, so both paths
  spawn a *detached* helper process before quitting -- one that outlives
  this BEAM entirely, waits a moment for this process to actually exit and
  release its file handles, then does the real work and relaunches.

  Verified hands-on end-to-end on both Windows (real install, real
  reinstall, real relaunch) and macOS (real .app, real backup/swap/relaunch
  via a live remote-console-triggered apply, on Apple Silicon). Both are
  written to fail safe: the original install is never touched until the
  new one has already been staged successfully (macOS's helper runs under
  `set -e`, so a failed `cp` aborts before the existing .app is moved
  aside), so a failure partway through leaves the existing install intact
  rather than gone.
  """

  require Logger

  @doc """
  Removes the `.old` backup `apply_macos/1` leaves behind, if this is
  macOS and one exists. Safe to call unconditionally on every boot: by the
  time this code is running, the *current* install already launched
  successfully, so a backup from whatever update produced it has served
  its purpose (it existed only so a failed relaunch after that update had
  something to fall back to). Windows never creates one (`apply_windows/1`
  reinstalls in place), so this is a no-op there.
  """
  def cleanup_old_backup do
    case :os.type() do
      {:unix, :darwin} -> File.rm_rf(current_app_bundle() <> ".old")
      _other -> :ok
    end
  end

  @doc "Applies `installer_path` (the downloaded .exe/.dmg) and quits this app."
  def apply(installer_path) do
    case :os.type() do
      {:win32, _} -> apply_windows(installer_path)
      {:unix, :darwin} -> apply_macos(installer_path)
      other -> {:error, {:unsupported_platform, other}}
    end
  end

  # `start "" /wait installer.exe /S` runs the NSIS installer silently over
  # the existing install (NSIS remembers the install path via its own
  # registry key, same as any reinstall) and waits for it to finish before
  # relaunching via the same run.vbs the Start Menu shortcut uses.
  defp apply_windows(installer_path) do
    release_root = release_root()
    relaunch_script = Path.join(release_root, "run.vbs")

    helper = """
    @echo off
    rem `timeout` errors out immediately (rather than actually waiting) when
    rem stdin isn't a real console, which it never is for a detached/headless
    rem spawn like this one -- confirmed the hard way: the installer ran
    rem before this process had actually released its file locks, so nothing
    rem got overwritten. ping is the standard workaround; it doesn't care.
    ping -n 4 127.0.0.1 >nul
    start "" /wait "#{installer_path}" /S
    start "" wscript "#{relaunch_script}"
    """

    helper_path = temp_helper_path("bat")
    File.write!(helper_path, helper)

    # The intermediate cmd.exe (the Port's actual tracked child) runs `start`
    # and exits in milliseconds; the helper .bat it launches is a fully
    # independent process by the time quit/0's sleep elapses, so it isn't
    # torn down when this BEAM's own port connections close on exit.
    cmd = System.find_executable("cmd.exe") || "cmd.exe"

    Port.open({:spawn_executable, cmd}, [
      :nouse_stdio,
      args: ["/c", "start", "", "/min", helper_path]
    ])

    quit()
    :ok
  end

  defp apply_macos(dmg_path) do
    with {:ok, mount_point} <- mount(dmg_path),
         {:ok, new_app} <- find_app(mount_point) do
      app_root = current_app_bundle()
      staged = app_root <> ".new"
      backup = app_root <> ".old"
      helper_path = temp_helper_path("sh")
      log_path = temp_helper_path("log")
      our_pid = System.pid()

      script = """
      #!/bin/sh
      # -e: bail on the first failing step rather than plowing ahead. Without
      # it, a failed `cp` (disk full, permissions) would still let a later
      # `mv "#{staged}" "#{app_root}"` run -- and since `mv` moves a source
      # *into* an existing directory rather than replacing it, that silently
      # nests the (incomplete) staged copy inside the still-live app_root
      # instead of leaving the original install alone.
      set -e
      exec >>"#{log_path}" 2>&1
      echo "$(date) starting update apply: #{new_app} -> #{app_root}"
      # Wait for the quitting instance to actually exit (and release its
      # fixed listen port) instead of betting on a fixed delay. A too-short
      # guess here lets the relaunch below race a still-dying old process:
      # the new instance loses the port, crashes immediately on bind, and
      # (since the release runs -heart) gets stuck in a restart loop
      # against the old process that's still alive and holding it --
      # reproduced hands-on by launching two instances concurrently, though
      # not confirmed as the exact cause of the original failed update this
      # was written in response to. Capped at 10s and proceeds regardless
      # so a wedged old process can't block the update forever.
      for _ in $(seq 1 50); do
        kill -0 #{our_pid} 2>/dev/null || break
        sleep 0.2
      done
      rm -rf "#{staged}"
      cp -R "#{new_app}" "#{staged}"
      rm -rf "#{backup}"
      mv "#{app_root}" "#{backup}"
      mv "#{staged}" "#{app_root}"
      open "#{app_root}"
      hdiutil detach "#{mount_point}" -quiet
      echo "$(date) update applied successfully"
      """

      File.write!(helper_path, script)
      File.chmod!(helper_path, 0o755)

      # nohup + background + disown: the shell this Port directly owns exits
      # immediately after backgrounding the real helper, so the helper is
      # already a fully detached process (not a child of this BEAM at all)
      # long before quit/0 actually stops the VM.
      Port.open({:spawn, "nohup \"#{helper_path}\" </dev/null >/dev/null 2>&1 & disown"}, [
        :nouse_stdio
      ])

      quit()
      :ok
    end
  end

  defp mount(dmg_path) do
    mount_point =
      Path.join(System.tmp_dir!(), "toodle_update_mount_#{System.unique_integer([:positive])}")

    File.mkdir_p!(mount_point)

    case System.cmd("hdiutil", ["attach", dmg_path, "-nobrowse", "-mountpoint", mount_point]) do
      {_output, 0} -> {:ok, mount_point}
      {output, _status} -> {:error, "hdiutil attach failed: #{output}"}
    end
  end

  defp find_app(mount_point) do
    case Path.wildcard(Path.join(mount_point, "*.app")) do
      [app | _] -> {:ok, app}
      [] -> {:error, "No .app bundle found in the mounted DMG"}
    end
  end

  # :code.root_dir() *is* the release root already (it contains erts-X,
  # bin/, lib/, releases/ as siblings) -- ".../Toodle.app/Contents/Resources"
  # on macOS's :release_first layout, "C:\Program Files\Toodle" on Windows.
  # Confirmed the hard way: an extra Path.dirname() here silently produced
  # "C:\Program Files\run.vbs" instead of "...\Toodle\run.vbs" in testing.
  defp release_root do
    :code.root_dir() |> List.to_string()
  end

  # Contents/Resources -> Contents -> the .app bundle itself.
  defp current_app_bundle do
    release_root() |> Path.dirname() |> Path.dirname()
  end

  defp temp_helper_path(ext) do
    Path.join(System.tmp_dir!(), "toodle_update_#{System.unique_integer([:positive])}.#{ext}")
  end

  defp quit do
    Task.start(fn ->
      Process.sleep(500)
      Logger.info("Applying update, quitting for relaunch")
      System.stop(0)
    end)
  end
end
