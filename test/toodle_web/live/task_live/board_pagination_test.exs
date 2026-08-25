defmodule ToodleWeb.TaskLive.BoardPaginationTest do
  use ToodleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Toodle.{Projects, Tasks}

  test "paginates the board at 15 tasks per page" do
    {:ok, project} = Projects.create_project(%{name: "Pagination Project"})

    for n <- 1..17 do
      {:ok, _task} =
        Tasks.create_task(%{
          project_id: project.id,
          title: "Task #{String.pad_leading("#{n}", 2, "0")}"
        })
    end

    {:ok, view, html} = live(build_conn(), ~p"/")

    assert html =~ "Page 1 of 2 (17 tasks)"
    assert html =~ "Task 01"
    refute html =~ "Task 16"

    html = render_click(view, "paginate", %{"page" => "2"})

    assert html =~ "Task 16"
    assert html =~ "Task 17"
    refute html =~ "Task 01"
  end
end
