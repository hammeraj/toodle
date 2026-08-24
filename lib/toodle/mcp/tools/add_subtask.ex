defmodule Toodle.MCP.Tools.AddSubtask do
  @moduledoc "Add a subtask under an existing top-level task (one level of nesting only)."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Tasks
  alias Toodle.MCP.Tools.Support

  schema do
    field(:parent_task_id, :string, required: true)
    field(:title, :string, required: true)
    field(:description, :string)
    field(:estimate_hours, :float)
  end

  @impl true
  def execute(%{parent_task_id: parent_id} = params, frame) do
    parent = Tasks.get_task!(parent_id)
    attrs = Map.take(params, [:title, :description, :estimate_hours])

    case Tasks.add_subtask(parent, attrs) do
      {:ok, task} ->
        {:reply, Response.tool() |> Response.json(Support.task_summary(task)), frame}

      {:error, changeset} ->
        {:reply, Response.tool() |> Response.error(Support.changeset_errors(changeset)), frame}
    end
  rescue
    Ecto.NoResultsError ->
      {:reply, Response.tool() |> Response.error("No task with that id"), frame}
  end
end
