defmodule Toodle.Repo.Migrations.AddPausedBlockingAndArchiving do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :archived_at, :utc_datetime
    end

    # Rebuild the title-uniqueness indexes to free up a title once its task is archived.
    drop index(:tasks, [:project_id, :title], name: :unique_top_level_task_title_per_project)
    drop index(:tasks, [:parent_task_id, :title], name: :unique_subtask_title_per_parent)

    create unique_index(:tasks, [:project_id, :title],
             where: "parent_task_id IS NULL AND archived_at IS NULL",
             name: :unique_top_level_task_title_per_project
           )

    create unique_index(:tasks, [:parent_task_id, :title],
             where: "parent_task_id IS NOT NULL AND archived_at IS NULL",
             name: :unique_subtask_title_per_parent
           )

    # `reason` becomes optional now that a block/interrupt can instead (or also)
    # reference another task. SQLite can't relax a NOT NULL constraint in place,
    # and there's no real data yet, so the table is rebuilt rather than altered.
    drop table(:task_events)

    create table(:task_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false
      add :blocking_task_id, references(:tasks, type: :binary_id, on_delete: :nilify_all)

      add :kind, :string, null: false
      add :reason, :text
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :resolution, :text

      timestamps(type: :utc_datetime)
    end

    create index(:task_events, [:task_id])
    create index(:task_events, [:blocking_task_id])

    create unique_index(:task_events, [:task_id],
             where: "ended_at IS NULL",
             name: :one_open_task_event_per_task
           )
  end
end
