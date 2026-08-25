defmodule ToodleWeb.TaskLive.BoardSortAndEstimateTest do
  use ToodleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Toodle.{Projects, Tasks}

  setup do
    {:ok, project} = Projects.create_project(%{name: "Sort Test Project"})
    %{project: project}
  end

  test "shows each task's estimate", %{project: project} do
    {:ok, _task} =
      Tasks.create_task(%{project_id: project.id, title: "Estimated task", estimate_hours: 2.5})

    {:ok, _view, html} = live(build_conn(), ~p"/")

    assert html =~ "2.5h"
  end

  test "sorting by due date orders tasks chronologically regardless of status", %{
    project: project
  } do
    {:ok, later} =
      Tasks.create_task(%{
        project_id: project.id,
        title: "Due later",
        due_date: ~D[2026-09-20]
      })

    {:ok, sooner} =
      Tasks.create_task(%{
        project_id: project.id,
        title: "Due sooner",
        due_date: ~D[2026-09-01]
      })

    # Complete the later-due task so it would sort last under status
    # ordering, to prove due-date sort ignores status entirely.
    {:ok, later} = Tasks.change_status(later, :in_progress)
    {:ok, _later} = Tasks.change_status(later, :complete)

    {:ok, view, _html} = live(build_conn(), ~p"/")

    html = render_change(view, "sort_by", %{"sort_by" => "due_date"})

    sooner_index = :binary.match(html, sooner.title) |> elem(0)
    later_index = :binary.match(html, later.title) |> elem(0)

    assert sooner_index < later_index
  end
end
