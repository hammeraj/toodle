defmodule Toodle.Projects do
  @moduledoc "The Projects context — CRUD for projects."

  import Ecto.Query, warn: false
  alias Toodle.Repo
  alias Toodle.Projects.Project

  @palette [
    "#f97316",
    "#3b82f6",
    "#22c55e",
    "#a855f7",
    "#ef4444",
    "#eab308",
    "#06b6d4",
    "#ec4899",
    "#84cc16",
    "#6366f1",
    "#f59e0b",
    "#14b8a6"
  ]

  @doc "Picks a palette color not already used by an active project (random palette pick if they're all taken)."
  def next_unused_color do
    used =
      list_projects()
      |> Enum.map(&(&1.color && String.downcase(&1.color)))
      |> MapSet.new()

    Enum.find(@palette, &(not MapSet.member?(used, &1))) || Enum.random(@palette)
  end

  def list_projects(opts \\ []) do
    Project
    |> maybe_exclude_archived(opts)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  defp maybe_exclude_archived(query, opts) do
    if Keyword.get(opts, :include_archived, false) do
      query
    else
      where(query, [p], is_nil(p.archived_at))
    end
  end

  @inbox_name "Inbox"

  @doc "The catch-all project Slack-sourced tasks land in, auto-created on first use."
  def get_or_create_inbox! do
    query = from(p in Project, where: p.name == ^@inbox_name and is_nil(p.archived_at))

    case Repo.one(query) do
      nil ->
        {:ok, project} =
          create_project(%{
            name: @inbox_name,
            description: "Auto-created for tasks pulled in from Slack mentions.",
            color: next_unused_color()
          })

        project

      project ->
        project
    end
  end

  def get_project!(id), do: Repo.get!(Project, id)

  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def archive_project(%Project{} = project) do
    update_project(project, %{archived_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end
end
