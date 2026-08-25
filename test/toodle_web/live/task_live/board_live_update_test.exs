defmodule ToodleWeb.TaskLive.BoardLiveUpdateTest do
  use ToodleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Toodle.{Projects, Tasks}

  test "a task created out-of-band (as an MCP tool would) appears on the board without a refresh" do
    {:ok, project} = Projects.create_project(%{name: "Live Update Project"})

    {:ok, view, html} = live(build_conn(), ~p"/")
    refute html =~ "MCP-created task"

    {:ok, _task} =
      Tasks.create_task(%{
        project_id: project.id,
        title: "MCP-created task"
      })

    assert render(view) =~ "MCP-created task"
  end
end
