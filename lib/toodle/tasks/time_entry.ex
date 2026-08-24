defmodule Toodle.Tasks.TimeEntry do
  use Toodle.Schema

  alias Toodle.Tasks.Task

  @stop_reasons [:blocked, :interrupted, :paused, :complete, :manual]

  schema "time_entries" do
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :stop_reason, Ecto.Enum, values: @stop_reasons
    field :duration_seconds, :integer

    belongs_to :task, Task

    timestamps()
  end

  def stop_reasons, do: @stop_reasons

  @doc "Starts a new open time entry for a task."
  def open_changeset(time_entry, attrs) do
    time_entry
    |> cast(attrs, [:task_id, :started_at])
    |> validate_required([:task_id, :started_at])
    |> foreign_key_constraint(:task_id)
    |> unique_constraint(:task_id, name: :one_open_time_entry_per_task)
  end

  @doc "Closes an open time entry, recording why it stopped and its duration."
  def close_changeset(time_entry, attrs) do
    time_entry
    |> cast(attrs, [:ended_at, :stop_reason, :duration_seconds])
    |> validate_required([:ended_at, :stop_reason, :duration_seconds])
    |> validate_inclusion(:stop_reason, @stop_reasons)
  end
end
