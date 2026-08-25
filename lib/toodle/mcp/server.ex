defmodule Toodle.MCP.Server do
  @moduledoc """
  Toodle's embedded MCP server — every tool is a thin adapter over the same
  `Toodle.Tasks`/`Toodle.Projects`/`Toodle.Sprints` contexts the LiveView UI
  uses, so there's exactly one place task/status/timer logic lives.

  Runs as a child of `Toodle.Application` alongside the web endpoint (not a
  separate process) and is reachable over Streamable HTTP at `/mcp`, mounted
  in `ToodleWeb.Router` — same running app, same Repo connection pool,
  nothing extra for an MCP client to spawn.
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
  component(Toodle.MCP.Tools.MoveTask)
  component(Toodle.MCP.Tools.StartTask)
  component(Toodle.MCP.Tools.PauseTask)
  component(Toodle.MCP.Tools.BlockTask)
  component(Toodle.MCP.Tools.InterruptTask)
  component(Toodle.MCP.Tools.CompleteTask)
  component(Toodle.MCP.Tools.GetTimeTotals)
  component(Toodle.MCP.Tools.LinkLinearIssue)
  component(Toodle.MCP.Tools.RefreshLinearIssue)
  component(Toodle.MCP.Tools.UnlinkLinearIssue)

  @impl true
  def init(_client_info, frame) do
    {:ok, frame}
  end
end
