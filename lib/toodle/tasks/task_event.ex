defmodule Toodle.Tasks.TaskEvent do
  use Toodle.Schema

  alias Toodle.Tasks.Task

  @kinds [:blocked, :interrupted]

  schema "task_events" do
    field :kind, Ecto.Enum, values: @kinds
    field :reason, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :resolution, :string

    belongs_to :task, Task
    belongs_to :blocking_task, Task

    timestamps()
  end

  def kinds, do: @kinds

  @doc "Opens a new block/interrupt event — needs a blocking task reference, a text reason, or both."
  def open_changeset(task_event, attrs) do
    task_event
    |> cast(attrs, [:task_id, :blocking_task_id, :kind, :reason, :started_at])
    |> validate_required([:task_id, :kind, :started_at])
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:blocking_task_id)
    |> unique_constraint(:task_id, name: :one_open_task_event_per_task)
    |> validate_has_blocker()
  end

  @doc "Closes an open block/interrupt event."
  def close_changeset(task_event, attrs) do
    cast(task_event, attrs, [:ended_at, :resolution])
  end

  defp validate_has_blocker(changeset) do
    if get_field(changeset, :blocking_task_id) || present?(get_field(changeset, :reason)) do
      changeset
    else
      add_error(changeset, :reason, "or a blocking task is required")
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
