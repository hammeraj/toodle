defmodule Toodle.MCP.Tools.CreateProject do
  @moduledoc "Create a new project. A color is picked automatically from an unused palette slot."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Projects
  alias Toodle.MCP.Tools.Support

  schema do
    field(:name, :string, required: true)
    field(:description, :string)
  end

  @impl true
  def execute(params, frame) do
    attrs =
      params
      |> Map.take([:name, :description])
      |> Map.put(:color, Projects.next_unused_color())

    case Projects.create_project(attrs) do
      {:ok, project} ->
        summary = %{id: project.id, name: project.name, description: project.description, color: project.color}
        {:reply, Response.tool() |> Response.json(summary), frame}

      {:error, changeset} ->
        {:reply, Response.tool() |> Response.error(Support.changeset_errors(changeset)), frame}
    end
  end
end
