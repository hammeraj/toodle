defmodule Toodle.MCP.Tools.LinkLinearIssue do
  @moduledoc """
  Link a task to a Linear issue by identifier (e.g. "ENG-123") or a pasted
  linear.app issue URL. Only records the link — call refresh_linear_issue
  to pull the issue's title/state/assignee.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.{Linear, Tasks}
  alias Toodle.MCP.Tools.Support

  schema do
    field(:task_id, :string, required: true)

    field(:identifier, :string,
      required: true,
      description: "Linear issue identifier like ENG-123, or a linear.app issue URL"
    )
  end

  @impl true
  def execute(%{task_id: task_id, identifier: identifier}, frame) do
    task = Tasks.get_task!(task_id)

    case Linear.link_task(task, identifier) do
      {:ok, updated} ->
        {:reply, Response.tool() |> Response.json(Support.linear_summary(updated)), frame}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:reply, Response.tool() |> Response.error(Support.changeset_errors(changeset)), frame}

      {:error, message} when is_binary(message) ->
        {:reply, Response.tool() |> Response.error(message), frame}
    end
  rescue
    Ecto.NoResultsError ->
      {:reply, Response.tool() |> Response.error("No task with that id"), frame}
  end
end
