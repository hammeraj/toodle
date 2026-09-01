defmodule ToodleWeb.SettingsLive.SlackChannelsTest do
  use ToodleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Toodle.Slack
  alias Toodle.Slack.Client

  setup do
    Slack.put_token("xoxp-test-token")
    Slack.put_user_id("U123")
    :ok
  end

  test "lists the channels currently being polled, and toggling private channels re-fetches them" do
    Req.Test.stub(Client, fn conn ->
      case conn.query_params["types"] do
        "public_channel" ->
          Req.Test.json(conn, %{
            "ok" => true,
            "channels" => [%{"id" => "C1", "name" => "general", "is_member" => true}]
          })

        "public_channel,private_channel" ->
          Req.Test.json(conn, %{
            "ok" => true,
            "channels" => [
              %{"id" => "C1", "name" => "general", "is_member" => true},
              %{"id" => "C2", "name" => "eng-private", "is_member" => true, "is_private" => true}
            ]
          })
      end
    end)

    {:ok, view, html} = live(build_conn(), ~p"/settings")

    assert html =~ "Listening to"
    assert html =~ "#general"
    refute html =~ "eng-private"
    assert has_element?(view, "span", "Include private channels — Disabled")

    html = render_click(view, "toggle_slack_include_private")

    assert html =~ "Include private channels — Enabled"
    assert html =~ "#general"
    assert html =~ "🔒eng-private"

    assert Slack.include_private_channels?()
  end

  test "shows an error state instead of crashing when the channel list can't be fetched" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, %{"ok" => false, "error" => "invalid_auth"})
    end)

    {:ok, _view, html} = live(build_conn(), ~p"/settings")

    assert html =~ "load the channel list"
  end

  test "poll_now surfaces a reactions-check failure in the flash instead of hiding it" do
    Req.Test.stub(Client, fn conn ->
      case conn.request_path do
        "/api/conversations.list" -> Req.Test.json(conn, %{"ok" => true, "channels" => []})
        "/api/reactions.list" -> Req.Test.json(conn, %{"ok" => false, "error" => "missing_scope"})
      end
    end)

    {:ok, view, _html} = live(build_conn(), ~p"/settings")

    html = render_click(view, "poll_now")

    assert html =~ "check reactions: missing_scope"
  end

  test "toggling direct messages re-fetches the channel list and shows a DM entry" do
    Req.Test.stub(Client, fn conn ->
      case conn.query_params["types"] do
        "public_channel" ->
          Req.Test.json(conn, %{"ok" => true, "channels" => []})

        "public_channel,im" ->
          Req.Test.json(conn, %{
            "ok" => true,
            "channels" => [%{"id" => "D1", "is_im" => true, "user" => "U9"}]
          })
      end
    end)

    {:ok, view, _html} = live(build_conn(), ~p"/settings")

    assert has_element?(view, "span", "Include direct messages — Disabled")

    html = render_click(view, "toggle_slack_include_dms")

    assert html =~ "Include direct messages — Enabled"
    assert html =~ "DM: U9"
    assert Slack.include_dms?()
  end

  test "saving the Slack form persists a custom poll interval" do
    Req.Test.stub(Client, fn conn -> Req.Test.json(conn, %{"ok" => true, "channels" => []}) end)

    {:ok, view, html} = live(build_conn(), ~p"/settings")
    assert html =~ ~s(value="60")

    html =
      render_submit(view, "save_slack_token", %{
        "token" => "",
        "user_id" => "U123",
        "reaction_emoji" => "",
        "poll_interval_seconds" => "120"
      })

    assert html =~ ~s(value="120")
    assert Slack.poll_interval_seconds() == 120
  end

  test "saving the Slack form with too small a poll interval floors it instead of accepting it" do
    Req.Test.stub(Client, fn conn -> Req.Test.json(conn, %{"ok" => true, "channels" => []}) end)

    {:ok, view, _html} = live(build_conn(), ~p"/settings")

    render_submit(view, "save_slack_token", %{
      "token" => "",
      "user_id" => "U123",
      "reaction_emoji" => "",
      "poll_interval_seconds" => "1"
    })

    assert Slack.poll_interval_seconds() == 15
  end
end
