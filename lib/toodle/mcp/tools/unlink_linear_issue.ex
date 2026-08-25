defmodule Toodle.MCP.Tools.UnlinkLinearIssue do
  @moduledoc "Remove a task's Linear link entirely."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.{Linear, Tasks}
  alias Toodle.MCP.Tools.Support

  schema do
    field(:task_id, :string, required: true)
  end

  @impl true
  def execute(%{task_id: task_id}, frame) do
    task = Tasks.get_task!(task_id)
    {:ok, updated} = Linear.unlink_task(task)
    {:reply, Response.tool() |> Response.json(Support.task_summary(updated)), frame}
  rescue
    Ecto.NoResultsError ->
      {:reply, Response.tool() |> Response.error("No task with that id"), frame}
  end
end
