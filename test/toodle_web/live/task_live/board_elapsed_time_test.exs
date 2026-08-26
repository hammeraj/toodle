defmodule ToodleWeb.TaskLive.BoardElapsedTimeTest do
  use ToodleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Toodle.{Projects, Repo, Tasks}
  alias Toodle.Tasks.TimeEntry

  test "a task's accumulated elapsed time still shows once it's no longer in progress" do
    {:ok, project} = Projects.create_project(%{name: "Elapsed Project"})
    {:ok, task} = Tasks.create_task(%{project_id: project.id, title: "Eleven second task"})

    {:ok, task} = Tasks.change_status(task, :in_progress)

    backdated = DateTime.utc_now() |> DateTime.add(-11, :second) |> DateTime.truncate(:second)

    Repo.update_all(
      from(te in TimeEntry, where: te.task_id == ^task.id and is_nil(te.ended_at)),
      set: [started_at: backdated]
    )

    {:ok, _task} = Tasks.change_status(task, :complete)

    {:ok, _view, html} = live(build_conn(), ~p"/")

    assert html =~ "00:00:1"
  end

  test "a task that was never started shows an em dash instead of 00:00:00" do
    {:ok, project} = Projects.create_project(%{name: "Never Started Project"})
    {:ok, _task} = Tasks.create_task(%{project_id: project.id, title: "Untouched task"})

    {:ok, _view, html} = live(build_conn(), ~p"/")

    refute html =~ "00:00:00"
  end
end
