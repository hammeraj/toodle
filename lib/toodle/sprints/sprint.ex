defmodule Toodle.Sprints.Sprint do
  use Toodle.Schema

  alias Toodle.Projects.Project
  alias Toodle.Tasks.Task

  schema "sprints" do
    field :name, :string
    field :start_date, :date
    field :end_date, :date

    belongs_to :project, Project
    has_many :tasks, Task

    timestamps()
  end

  @doc false
  def changeset(sprint, attrs) do
    sprint
    |> cast(attrs, [:project_id, :name, :start_date, :end_date])
    |> validate_required([:project_id, :name, :start_date, :end_date])
    |> foreign_key_constraint(:project_id)
    |> validate_date_order()
  end

  defp validate_date_order(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && Date.compare(end_date, start_date) == :lt do
      add_error(changeset, :end_date, "must be on or after the start date")
    else
      changeset
    end
  end
end
