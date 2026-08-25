defmodule Toodle.MCP.Tools.CreateTask do
  @moduledoc "Create a new top-level task in a project."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Tasks
  alias Toodle.MCP.Tools.Support

  schema do
    field(:project_id, :string, required: true)
    field(:title, :string, required: true)
    field(:description, :string)
    field(:estimate_hours, {:either, {:integer, :float}})
    field(:start_date, :string, description: "ISO8601 date, e.g. 2026-09-01")
    field(:due_date, :string, description: "ISO8601 date, e.g. 2026-09-05")
  end

  @impl true
  def execute(params, frame) do
    attrs =
      Map.take(params, [
        :project_id,
        :title,
        :description,
        :estimate_hours,
        :start_date,
        :due_date
      ])

    case Tasks.create_task(attrs) do
      {:ok, task} ->
        {:reply, Response.tool() |> Response.json(Support.task_summary(task)), frame}

      {:error, changeset} ->
        {:reply, Response.tool() |> Response.error(Support.changeset_errors(changeset)), frame}
    end
  end
end
