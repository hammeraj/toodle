defmodule Toodle.Sprints do
  @moduledoc "The Sprints context — CRUD for date-boxed sprints within a project."

  import Ecto.Query, warn: false
  alias Toodle.Repo
  alias Toodle.Sprints.Sprint

  def list_sprints(project_id) do
    Sprint
    |> where([s], s.project_id == ^project_id)
    |> order_by([s], desc: s.start_date)
    |> Repo.all()
  end

  def get_sprint!(id), do: Repo.get!(Sprint, id)

  def create_sprint(attrs \\ %{}) do
    %Sprint{}
    |> Sprint.changeset(attrs)
    |> Repo.insert()
  end

  def update_sprint(%Sprint{} = sprint, attrs) do
    sprint
    |> Sprint.changeset(attrs)
    |> Repo.update()
  end

  def delete_sprint(%Sprint{} = sprint) do
    Repo.delete(sprint)
  end

  def change_sprint(%Sprint{} = sprint, attrs \\ %{}) do
    Sprint.changeset(sprint, attrs)
  end
end
