defmodule Toodle.MCP.Tools.UpdateTask do
  @moduledoc "Update a task's editable fields. Use the status tools (start_task, block_task, etc.) to change status."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Tasks
  alias Toodle.MCP.Tools.Support

  schema do
    field(:task_id, :string, required: true)
    field(:title, :string)
    field(:description, :string)
    field(:estimate_hours, :float)
    field(:start_date, :string)
    field(:due_date, :string)
  end

  @impl true
  def execute(%{task_id: task_id} = params, frame) do
    task = Tasks.get_task!(task_id)
    attrs = Map.take(params, [:title, :description, :estimate_hours, :start_date, :due_date])

    case Tasks.update_task(task, attrs) do
      {:ok, updated} ->
        {:reply, Response.tool() |> Response.json(Support.task_summary(updated)), frame}

      {:error, changeset} ->
        {:reply, Response.tool() |> Response.error(Support.changeset_errors(changeset)), frame}
    end
  rescue
    Ecto.NoResultsError ->
      {:reply, Response.tool() |> Response.error("No task with that id"), frame}
  end
end
