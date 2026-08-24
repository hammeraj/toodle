defmodule Toodle.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sprint_id, references(:sprints, type: :binary_id, on_delete: :nilify_all)
      add :parent_task_id, references(:tasks, type: :binary_id, on_delete: :delete_all)

      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "not_started"
      add :position, :integer, null: false, default: 0

      add :estimate_hours, :float
      add :start_date, :date
      add :due_date, :date
      add :completed_at, :utc_datetime

      add :linear_issue_id, :string
      add :linear_identifier, :string
      add :linear_url, :string
      add :linear_title, :string
      add :linear_state, :string
      add :linear_assignee_name, :string
      add :linear_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:sprint_id])
    create index(:tasks, [:parent_task_id])
    create index(:tasks, [:status])
    create unique_index(:tasks, [:linear_issue_id], where: "linear_issue_id IS NOT NULL")
  end
end
