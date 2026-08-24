defmodule Toodle.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :text

      timestamps(type: :utc_datetime)
    end
  end
end
