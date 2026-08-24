defmodule Toodle.MCP.Server do
  @moduledoc """
  Toodle's embedded MCP server — every tool is a thin adapter over the same
  `Toodle.Tasks`/`Toodle.Projects`/`Toodle.Sprints` contexts the LiveView UI
  uses, so there's exactly one place task/status/timer logic lives.

  Spawned over stdio by `bin/toodle_mcp` (see that script and
  `Toodle.Application` for why this runs as a separate OS process from the
  web app rather than a child of it).
  """

  use Anubis.Server,
    name: "toodle",
    version: "0.1.0",
    capabilities: [:tools]

  component(Toodle.MCP.Tools.ListProjects)
  component(Toodle.MCP.Tools.CreateProject)
  component(Toodle.MCP.Tools.ListSprints)
  component(Toodle.MCP.Tools.ListTasks)
  component(Toodle.MCP.Tools.GetTask)
  component(Toodle.MCP.Tools.CreateTask)
  component(Toodle.MCP.Tools.AddSubtask)
  component(Toodle.MCP.Tools.UpdateTask)
  component(Toodle.MCP.Tools.StartTask)
  component(Toodle.MCP.Tools.PauseTask)
  component(Toodle.MCP.Tools.BlockTask)
  component(Toodle.MCP.Tools.InterruptTask)
  component(Toodle.MCP.Tools.CompleteTask)
  component(Toodle.MCP.Tools.GetTimeTotals)

  @impl true
  def init(_client_info, frame) do
    {:ok, frame}
  end
end
