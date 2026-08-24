defmodule Toodle.Repo.Migrations.AddUniqueConstraints do
  use Ecto.Migration

  def change do
    create unique_index(:projects, [:name],
             where: "archived_at IS NULL",
             name: :unique_active_project_name
           )

    create unique_index(:tasks, [:project_id, :title],
             where: "parent_task_id IS NULL",
             name: :unique_top_level_task_title_per_project
           )

    create unique_index(:tasks, [:parent_task_id, :title],
             where: "parent_task_id IS NOT NULL",
             name: :unique_subtask_title_per_parent
           )
  end
end
