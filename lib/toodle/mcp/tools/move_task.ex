defmodule Toodle.MCP.Tools.MoveTask do
  @moduledoc """
  Move a task to a different project — e.g. triaging the auto-created
  "Inbox" project that Slack-mention tasks land in.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Tasks
  alias Toodle.MCP.Tools.Support

  schema do
    field(:task_id, :string, required: true)
    field(:project_id, :string, required: true)
  end

  @impl true
  def execute(%{task_id: task_id, project_id: project_id}, frame) do
    task = Tasks.get_task!(task_id)

    case Tasks.update_task(task, %{project_id: project_id}) do
      {:ok, updated} ->
        {:reply, Response.tool() |> Response.json(Support.task_summary(updated)), frame}

      {:error, changeset} ->
        {:reply, Response.tool() |> Response.error(Support.changeset_errors(changeset)), frame}
    end
  rescue
    Ecto.NoResultsError -> {:reply, Response.tool() |> Response.error("No task with that id"), frame}
  end
end
