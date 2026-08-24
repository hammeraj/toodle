defmodule Toodle.MCP.Tools.ListProjects do
  @moduledoc "List all active (non-archived) projects."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Projects

  schema do
  end

  @impl true
  def execute(_params, frame) do
    projects =
      Enum.map(Projects.list_projects(), fn p ->
        %{id: p.id, name: p.name, description: p.description}
      end)

    {:reply, Response.tool() |> Response.json(projects), frame}
  end
end
