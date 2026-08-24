defmodule Toodle.MCP.Tools.GetTask do
  @moduledoc """
  Get full details for a task: description, dates, subtasks, the currently
  open block/interrupt (if any), and total tracked time.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Tasks
  alias Toodle.MCP.Tools.Support

  schema do
    field(:task_id, :string, required: true)
  end

  @impl true
  def execute(%{task_id: task_id}, frame) do
    task = Tasks.get_task_with_details!(task_id)
    {:reply, Response.tool() |> Response.json(Support.task_detail(task)), frame}
  rescue
    Ecto.NoResultsError -> {:reply, Response.tool() |> Response.error("No task with that id"), frame}
  end
end
