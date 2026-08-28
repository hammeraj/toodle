defmodule ToodleWeb.SettingsLive.BoardShowArchivedTest do
  use ToodleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Toodle.{Projects, Tasks}

  test "toggling show archived persists across a reload, and the board picks it up" do
    {:ok, project} = Projects.create_project(%{name: "Archived Setting Project"})
    {:ok, task} = Tasks.create_task(%{project_id: project.id, title: "Archived task"})
    {:ok, _task} = Tasks.archive_task(task)

    {:ok, board_view, board_html} = live(build_conn(), ~p"/")
    refute board_html =~ "Archived task"
    refute has_element?(board_view, "input[type=checkbox]")

    {:ok, view, html} = live(build_conn(), ~p"/settings")

    assert html =~ "Board"
    assert has_element?(view, "span", "Hiding archived")

    html = render_click(view, "toggle_board_show_archived")
    assert html =~ "Showing archived"

    {:ok, _reloaded_view, reloaded_html} = live(build_conn(), ~p"/settings")
    assert reloaded_html =~ "Showing archived"

    {:ok, _board_view, board_html} = live(build_conn(), ~p"/")
    assert board_html =~ "Archived task"
  end
end
