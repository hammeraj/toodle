defmodule Toodle.Repo.Migrations.CreateSprints do
  use Ecto.Migration

  def change do
    create table(:sprints, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :start_date, :date, null: false
      add :end_date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sprints, [:project_id])
  end
end
