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

  test "defaults to sorting by due date, surviving a fresh page load", %{project: project} do
    {:ok, later} =
      Tasks.create_task(%{project_id: project.id, title: "Due later", due_date: ~D[2026-09-20]})

    {:ok, sooner} =
      Tasks.create_task(%{project_id: project.id, title: "Due sooner", due_date: ~D[2026-09-01]})

    {:ok, _view, html} = live(build_conn(), ~p"/")

    sooner_index = :binary.match(html, sooner.title) |> elem(0)
    later_index = :binary.match(html, later.title) |> elem(0)

    assert sooner_index < later_index
  end

  test "sorting by due date orders chronologically within status, but completed always sinks and in-progress always floats",
       %{project: project} do
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

    # Complete the sooner-due task so it would sort first under pure
    # chronological ordering, to prove completed tasks sink to the bottom
    # regardless of due date. Bump the later-due task to in-progress so it
    # floats to the top, also regardless of due date.
    {:ok, sooner} = Tasks.change_status(sooner, :in_progress)
    {:ok, sooner} = Tasks.change_status(sooner, :complete)
    {:ok, _later} = Tasks.change_status(later, :in_progress)

    {:ok, view, _html} = live(build_conn(), ~p"/")

    html = render_change(view, "sort_by", %{"sort_by" => "due_date"})

    later_index = :binary.match(html, later.title) |> elem(0)
    sooner_index = :binary.match(html, sooner.title) |> elem(0)

    assert later_index < sooner_index
  end

  test "sorting by due date orders chronologically within the same status", %{project: project} do
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

    {:ok, view, _html} = live(build_conn(), ~p"/")

    html = render_change(view, "sort_by", %{"sort_by" => "due_date"})

    sooner_index = :binary.match(html, sooner.title) |> elem(0)
    later_index = :binary.match(html, later.title) |> elem(0)

    assert sooner_index < later_index
  end
end
