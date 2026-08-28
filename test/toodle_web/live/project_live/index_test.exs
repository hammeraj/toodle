defmodule ToodleWeb.ProjectLive.IndexTest do
  use ToodleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Toodle.{Projects, Tasks}

  test "each project links to a board prefiltered to just that project" do
    {:ok, project_a} = Projects.create_project(%{name: "Project A"})
    {:ok, project_b} = Projects.create_project(%{name: "Project B"})
    {:ok, _task_a} = Tasks.create_task(%{project_id: project_a.id, title: "Task in A"})
    {:ok, _task_b} = Tasks.create_task(%{project_id: project_b.id, title: "Task in B"})

    {:ok, view, _html} = live(build_conn(), ~p"/projects")

    {:ok, _board_view, board_html} =
      view
      |> element("a[href='/?project_id=#{project_a.id}']", "View Board")
      |> render_click()
      |> follow_redirect(build_conn())

    assert board_html =~ "Task in A"
    refute board_html =~ "Task in B"
  end
end
