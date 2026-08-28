defmodule Toodle.Tasks.SlackImportTest do
  use Toodle.DataCase, async: true

  alias Toodle.{Projects, Tasks}

  test "create_from_slack/1 accepts an optional due date and estimate" do
    {:ok, project} = Projects.create_project(%{name: "Infra"})

    {:ok, task} =
      Tasks.create_from_slack(%{
        project_id: project.id,
        title: "Fix staging deploy",
        description: "raw message",
        due_date: ~D[2026-09-04],
        estimate_hours: 2.0,
        slack_channel_id: "C123",
        slack_message_ts: "1700000000.000100"
      })

    assert task.due_date == ~D[2026-09-04]
    assert task.estimate_hours == 2.0
  end

  test "create_from_slack/1 works without a due date or estimate, same as before" do
    {:ok, project} = Projects.create_project(%{name: "Infra"})

    {:ok, task} =
      Tasks.create_from_slack(%{
        project_id: project.id,
        title: "Fix staging deploy",
        description: "raw message",
        slack_channel_id: "C123",
        slack_message_ts: "1700000000.000200"
      })

    assert task.due_date == nil
    assert task.estimate_hours == nil
  end
end
