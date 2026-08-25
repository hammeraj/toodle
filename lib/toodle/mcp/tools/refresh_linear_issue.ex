defmodule Toodle.MCP.Tools.RefreshLinearIssue do
  @moduledoc """
  Pull the latest title/state/assignee from Linear for a task's linked
  issue. Requires a Linear API key to be set in Settings.
  """

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

    case Linear.refresh(task) do
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
