defmodule Toodle.MCP.Tools.ListSprints do
  @moduledoc "List the sprints defined for a project."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Sprints

  schema do
    field(:project_id, :string, required: true)
  end

  @impl true
  def execute(%{project_id: project_id}, frame) do
    sprints =
      Enum.map(Sprints.list_sprints(project_id), fn s ->
        %{
          id: s.id,
          name: s.name,
          start_date: Date.to_iso8601(s.start_date),
          end_date: Date.to_iso8601(s.end_date)
        }
      end)

    {:reply, Response.tool() |> Response.json(sprints), frame}
  end
end
