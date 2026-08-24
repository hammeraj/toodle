defmodule Toodle.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :color, :string
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end
  end
end
