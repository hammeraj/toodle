defmodule Toodle.Tasks.Task do
  use Toodle.Schema

  import Ecto.Query, only: [from: 2]

  alias Toodle.Repo
  alias Toodle.Projects.Project
  alias Toodle.Sprints.Sprint
  alias Toodle.Tasks.{TaskEvent, TimeEntry}

  @statuses [:not_started, :in_progress, :paused, :blocked, :interrupted, :complete]

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, Ecto.Enum, values: @statuses, default: :not_started
    field :position, :integer, default: 0

    field :estimate_hours, :float
    field :start_date, :date
    field :due_date, :date
    field :completed_at, :utc_datetime
    field :archived_at, :utc_datetime

    field :linear_issue_id, :string
    field :linear_identifier, :string
    field :linear_url, :string
    field :linear_title, :string
    field :linear_state, :string
    field :linear_assignee_name, :string
    field :linear_synced_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :sprint, Sprint
    belongs_to :parent_task, __MODULE__, foreign_key: :parent_task_id

    has_many :subtasks, __MODULE__, foreign_key: :parent_task_id
    has_many :task_events, TaskEvent
    has_many :time_entries, TimeEntry

    timestamps()
  end

  @doc "Statuses a task can be in — see `Toodle.Tasks.StatusMachine` for the transition rules."
  def statuses, do: @statuses

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :project_id,
      :sprint_id,
      :parent_task_id,
      :title,
      :description,
      :estimate_hours,
      :start_date,
      :due_date,
      :position
    ])
    |> validate_required([:project_id, :title])
    |> validate_number(:estimate_hours, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:sprint_id)
    |> foreign_key_constraint(:parent_task_id)
    |> validate_not_self_parent()
    |> validate_title_uniqueness()
  end

  @doc "Status transitions go through here, and only via `Toodle.Tasks.change_status/3`."
  def status_changeset(task, attrs) do
    task
    |> cast(attrs, [:status, :completed_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Archives (or unarchives, passing `archived_at: nil`) a task."
  def archive_changeset(task, attrs) do
    cast(task, attrs, [:archived_at])
  end

  @doc "Links a task to a Linear issue by identifier, before anything has been fetched from Linear yet."
  def linear_link_changeset(task, attrs) do
    cast(task, attrs, [:linear_identifier])
  end

  @doc "Records a fetch from Linear: the canonical id/identifier/url plus title/state/assignee."
  def linear_sync_changeset(task, attrs) do
    task
    |> cast(attrs, [
      :linear_issue_id,
      :linear_identifier,
      :linear_url,
      :linear_title,
      :linear_state,
      :linear_assignee_name,
      :linear_synced_at
    ])
    |> unique_constraint(:linear_issue_id)
  end

  @doc "Removes a task's Linear link entirely."
  def linear_unlink_changeset(task) do
    cast(task, %{}, [])
    |> Ecto.Changeset.change(%{
      linear_issue_id: nil,
      linear_identifier: nil,
      linear_url: nil,
      linear_title: nil,
      linear_state: nil,
      linear_assignee_name: nil,
      linear_synced_at: nil
    })
  end

  defp validate_not_self_parent(changeset) do
    id = changeset.data.id
    parent_id = get_change(changeset, :parent_task_id)

    if id && parent_id && id == parent_id do
      add_error(changeset, :parent_task_id, "can't be its own parent")
    else
      changeset
    end
  end

  # Top-level task titles must be unique within a project; subtask titles
  # must be unique within their parent — enforced here (with a matching
  # partial unique index as the race-safety net) since "duplicate task"
  # is scoped differently depending on nesting.
  defp validate_title_uniqueness(changeset) do
    case get_field(changeset, :parent_task_id) do
      nil ->
        case get_field(changeset, :project_id) do
          nil ->
            changeset

          project_id ->
            changeset
            |> unsafe_validate_unique([:title], Repo,
              query:
                from(t in __MODULE__,
                  where:
                    t.project_id == ^project_id and is_nil(t.parent_task_id) and
                      is_nil(t.archived_at)
                )
            )
            |> unique_constraint(:title, name: :unique_top_level_task_title_per_project)
        end

      parent_id ->
        changeset
        |> unsafe_validate_unique([:title], Repo,
          query: from(t in __MODULE__, where: t.parent_task_id == ^parent_id and is_nil(t.archived_at))
        )
        |> unique_constraint(:title, name: :unique_subtask_title_per_parent)
    end
  end
end
