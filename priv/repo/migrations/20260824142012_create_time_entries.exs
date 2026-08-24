defmodule Toodle.Repo.Migrations.CreateTimeEntries do
  use Ecto.Migration

  def change do
    create table(:time_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false

      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :stop_reason, :string
      add :duration_seconds, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:time_entries, [:task_id])

    create unique_index(:time_entries, [:task_id],
             where: "ended_at IS NULL",
             name: :one_open_time_entry_per_task
           )
  end
end
