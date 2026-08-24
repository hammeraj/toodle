defmodule Toodle.Repo.Migrations.AddSlackFieldsToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :slack_channel_id, :string
      add :slack_message_ts, :string
      add :slack_permalink, :string
    end

    create unique_index(:tasks, [:slack_channel_id, :slack_message_ts],
             where: "slack_message_ts IS NOT NULL",
             name: :unique_slack_message_per_task
           )
  end
end
