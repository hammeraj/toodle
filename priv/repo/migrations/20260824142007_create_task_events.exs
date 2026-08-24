defmodule Toodle.Repo.Migrations.CreateTaskEvents do
  use Ecto.Migration

  def change do
    create table(:task_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false

      add :kind, :string, null: false
      add :reason, :text, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :resolution, :text

      timestamps(type: :utc_datetime)
    end

    create index(:task_events, [:task_id])

    create unique_index(:task_events, [:task_id],
             where: "ended_at IS NULL",
             name: :one_open_task_event_per_task
           )
  end
end
