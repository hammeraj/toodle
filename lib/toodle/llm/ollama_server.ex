defmodule Toodle.Llm.OllamaServer do
  @moduledoc """
  Supervises a bundled `ollama serve` subprocess, for builds that ship one
  under `priv/ollama/` (macOS only, for now — see `mix.exs`'s
  `bundle_ollama/1` release step). Always part of the supervision tree
  (see `Toodle.Application`), same as `Toodle.Slack.Poller`, but a no-op
  whenever there's nothing bundled to run — a plain `mix phx.server` dev
  build, a Windows build, or any build produced without
  `TOODLE_OLLAMA_BUNDLE_DIR` set. In that case `Toodle.Llm.Ollama` just
  falls back to its previous default (a user's own separately-installed
  Ollama on the standard port).

  Runs on a fixed, non-default port specifically so this never collides
  with a system Ollama the user might also have installed on the standard
  11434.
  """

  use GenServer
  require Logger

  @port 11535
  @relative_bin_dir "ollama/bin"
  @relative_models_dir "ollama/models"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The base URL the bundled server listens on, once running."
  def host, do: "http://127.0.0.1:#{@port}"

  @doc "Whether this build ships a bundled Ollama runtime + model at all."
  def bundled?, do: bin_path() != nil

  @impl true
  def init(_opts) do
    case bin_path() do
      nil ->
        :ignore

      bin ->
        Logger.info("Starting bundled Ollama server from #{bin}")
        port = open_port(bin)
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
      {:os_pid, os_pid} -> System.cmd("kill", [to_string(os_pid)])
      nil -> :ok
    end

    :ok
  end

  defp open_port(bin) do
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

  defp bin_path do
    path = Path.join(bin_dir(), "ollama")
    if File.exists?(path), do: path
  end

  defp bin_dir, do: Path.join(Application.app_dir(:toodle, "priv"), @relative_bin_dir)
  defp models_dir, do: Path.join(Application.app_dir(:toodle, "priv"), @relative_models_dir)
end
