defmodule Toodle.Llm.OllamaServerTest do
  use ExUnit.Case, async: true

  alias Toodle.{Paths, Llm.OllamaServer}

  test "bundled?/0 is false when this build ships no priv/ollama/bin/ollama" do
    refute OllamaServer.bundled?()
  end

  test "init/1 returns :ignore (so the supervisor just skips it) when nothing is bundled" do
    assert :ignore = OllamaServer.init([])
  end

  test "models_dir/0 lives outside the release bundle, under the persistent app-data dir" do
    assert OllamaServer.models_dir() == Path.join(Paths.data_dir(), "ollama/models")
    refute String.contains?(OllamaServer.models_dir(), Application.app_dir(:toodle, "priv"))
  end

  test "an exited port schedules a bounded number of restart attempts, then gives up" do
    state = %{port: :fake_port, bin: "/bin/true", restart_count: 0}

    state =
      Enum.reduce(1..5, state, fn expected_count, state ->
        assert {:noreply, state} =
                 OllamaServer.handle_info({:fake_port, {:exit_status, 1}}, state)

        assert state.restart_count == expected_count
        state
      end)

    # One crash beyond the cap stops incrementing (and so stops scheduling
    # further restarts) rather than retrying forever.
    assert {:noreply, ^state} = OllamaServer.handle_info({:fake_port, {:exit_status, 1}}, state)
  end

  test "terminate/2 waits for the killed subprocess to actually exit before returning" do
    port = Port.open({:spawn, "sleep 30"}, [:binary, :exit_status])
    {:os_pid, os_pid} = Port.info(port, :os_pid)

    assert :ok = OllamaServer.terminate(:shutdown, %{port: port})

    # `kill -0` fails once the process is gone -- confirms terminate/2
    # didn't return until the subprocess it started had actually died,
    # rather than firing the signal and racing off (the bug that let
    # `ollama serve` get orphaned across an app-update relaunch).
    {_output, status} = System.cmd("kill", ["-0", to_string(os_pid)], stderr_to_stdout: true)
    assert status != 0
  end
end
