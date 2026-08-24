defmodule Toodle.MCP.Tools.GetTimeTotals do
  @moduledoc "Get total tracked time for a single task, or summed across a whole project."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Tasks

  schema do
    field(:task_id, :string, description: "Get the total for this one task")
    field(:project_id, :string, description: "Sum totals across every task in this project")
  end

  @impl true
  def execute(%{task_id: task_id}, frame) when is_binary(task_id) do
    total = Tasks.total_active_seconds(task_id)

    {:reply, Response.tool() |> Response.json(%{task_id: task_id, total_active_seconds: total}),
     frame}
  rescue
    Ecto.NoResultsError ->
      {:reply, Response.tool() |> Response.error("No task with that id"), frame}
  end

  def execute(%{project_id: project_id}, frame) when is_binary(project_id) do
    tasks =
      Tasks.list_tasks(project_id: project_id, top_level_only: false, include_archived: true)

    total = Enum.reduce(tasks, 0, &(&2 + Tasks.total_active_seconds(&1.id)))

    {:reply,
     Response.tool()
     |> Response.json(%{
       project_id: project_id,
       total_active_seconds: total,
       task_count: length(tasks)
     }), frame}
  end

  def execute(_params, frame) do
    {:reply, Response.tool() |> Response.error("Provide task_id or project_id"), frame}
  end
end
