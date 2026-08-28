defmodule Toodle.Llm.OllamaServer do
  @moduledoc """
  Supervises a bundled `ollama serve` subprocess, for builds that ship the
  runtime binary under `priv/ollama/bin/` (macOS only, for now — see
  `mix.exs`'s `bundle_ollama/1` release step). Always part of the
  supervision tree (see `Toodle.Application`), same as
  `Toodle.Slack.Poller`, but a no-op whenever there's nothing bundled to
  run — a plain `mix phx.server` dev build, a Windows build, or any build
  produced without `TOODLE_OLLAMA_BUNDLE_DIR` set. In that case
  `Toodle.Llm.Ollama` just falls back to its previous default (a user's
  own separately-installed Ollama on the standard port).

  Only the ~100MB runtime ships in the release; the model itself (~1GB)
  is *not* bundled — `Toodle.Llm.Ollama.ensure_model/1` pulls it on
  demand, into `models_dir/0` below rather than anywhere under the
  release's own `priv/`, specifically so it survives an app update
  (`Toodle.Updater.Applier` replaces the whole `.app` bundle wholesale on
  every update, which would otherwise force a ~1GB redownload every time
  even when the model itself hasn't changed).

  Runs on a fixed, non-default port specifically so this never collides
  with a system Ollama the user might also have installed on the standard
  11434.
  """

  use GenServer
  require Logger

  alias Toodle.Paths

  @port 11535
  @relative_bin_dir "ollama/bin"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The base URL the bundled server listens on, once running."
  def host, do: "http://127.0.0.1:#{@port}"

  @doc "Whether this build ships a bundled Ollama runtime at all."
  def bundled?, do: bin_path() != nil

  @doc "Where the bundled server keeps pulled models — outside the release bundle, so updates don't touch it."
  def models_dir, do: Path.join(Paths.data_dir(), "ollama/models")

  @impl true
  def init(_opts) do
    case bin_path() do
      nil ->
        :ignore

      bin ->
        Logger.info("Starting bundled Ollama server from #{bin}")
        port = open_port(bin)
        await_ready()
        {:ok, %{port: port}}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    Logger.debug("ollama: #{data}")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("Bundled ollama server exited with status #{status}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{port: port}) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> kill_and_wait(os_pid)
      nil -> :ok
    end

    :ok
  end

  # Waits for the killed subprocess to actually exit rather than firing a
  # signal and immediately returning -- otherwise this GenServer's
  # `terminate/2` (and the app's overall shutdown, e.g.
  # `Toodle.Updater.Applier`'s `System.stop(0)` before a relaunch) can
  # complete while `ollama serve` is still mid-shutdown, orphaning it as a
  # live process still bound to `@port` that the *next* launch then has to
  # contend with. SIGTERM first, SIGKILL if it hasn't died within the
  # polling window -- bounded well under the supervisor's default 5s
  # shutdown budget for this child.
  defp kill_and_wait(os_pid) do
    System.cmd("kill", [to_string(os_pid)])
    wait_for_exit(os_pid, 20)
  end

  defp wait_for_exit(os_pid, 0), do: System.cmd("kill", ["-9", to_string(os_pid)])

  defp wait_for_exit(os_pid, attempts_left) do
    case System.cmd("kill", ["-0", to_string(os_pid)], stderr_to_stdout: true) do
      {_output, 0} ->
        Process.sleep(100)
        wait_for_exit(os_pid, attempts_left - 1)

      {_output, _nonzero} ->
        :ok
    end
  end

  defp open_port(bin) do
    File.mkdir_p!(models_dir())

    Port.open(
      {:spawn_executable, bin},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["serve"],
        env: [
          {~c"OLLAMA_HOST", ~c"127.0.0.1:#{@port}"},
          {~c"OLLAMA_MODELS", String.to_charlist(models_dir())}
        ]
      ]
    )
  end

  @ready_check_interval_ms 100
  @ready_check_attempts 50

  # Spawning the subprocess and it actually binding @port aren't the same
  # moment -- without this, any caller that races to talk to it right after
  # app launch (Settings mounting and immediately checking/pulling the
  # model, for instance) can hit a plain connection-refused before it's had
  # a chance to come up, which looks identical to "Ollama isn't there" even
  # though it's about to be. Blocks this GenServer's init/1 (and so the
  # supervision tree's startup) rather than returning early, so nothing
  # downstream can observe `bundled?/0` as true before the server it points
  # at is actually reachable. Bounded at ~5s and falls through regardless
  # of outcome -- a genuinely broken/quarantined binary shouldn't hang app
  # startup, and every caller already tolerates `{:error, _}` from here on.
  defp await_ready(attempts_left \\ @ready_check_attempts)

  defp await_ready(0) do
    Logger.warning("Bundled Ollama server did not start listening within the startup budget")
  end

  defp await_ready(attempts_left) do
    case :gen_tcp.connect(~c"127.0.0.1", @port, [:binary, active: false], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)

      {:error, _reason} ->
        Process.sleep(@ready_check_interval_ms)
        await_ready(attempts_left - 1)
    end
  end

  defp bin_path do
    path = Path.join(bin_dir(), "ollama")
    if File.exists?(path), do: path
  end

  defp bin_dir, do: Path.join(Application.app_dir(:toodle, "priv"), @relative_bin_dir)
end
