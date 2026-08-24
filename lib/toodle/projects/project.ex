defmodule Toodle.Projects.Project do
  use Toodle.Schema

  import Ecto.Query, only: [from: 2]

  alias Toodle.Repo
  alias Toodle.Sprints.Sprint
  alias Toodle.Tasks.Task

  schema "projects" do
    field :name, :string
    field :description, :string
    field :color, :string
    field :archived_at, :utc_datetime

    has_many :sprints, Sprint
    has_many :tasks, Task

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :color, :archived_at])
    |> validate_required([:name])
    |> unsafe_validate_unique(:name, Repo, query: from(p in __MODULE__, where: is_nil(p.archived_at)))
    |> unique_constraint(:name, name: :unique_active_project_name)
  end
end
