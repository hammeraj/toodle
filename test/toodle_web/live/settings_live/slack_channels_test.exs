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

  describe "manage channels modal" do
    setup do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{
          "ok" => true,
          "channels" => [
            %{"id" => "C1", "name" => "general", "is_member" => true},
            %{"id" => "C2", "name" => "eng", "is_member" => true}
          ]
        })
      end)

      :ok
    end

    test "is closed by default, and the Manage button opens it with every channel listed" do
      {:ok, view, html} = live(build_conn(), ~p"/settings")

      refute html =~ "Manage channels"
      assert has_element?(view, "button", "Manage")

      html = render_click(view, "open_slack_channels_modal")

      assert html =~ "Manage channels"
      assert has_element?(view, "#slack-channels-modal", "#general")
      assert has_element?(view, "#slack-channels-modal", "#eng")
    end

    test "toggling a channel off in the modal excludes it from polling and greys it out in the summary" do
      {:ok, view, _html} = live(build_conn(), ~p"/settings")
      render_click(view, "open_slack_channels_modal")

      refute Slack.channel_excluded?("C1")

      html = render_click(view, "toggle_channel_excluded", %{"id" => "C1"})

      assert Slack.channel_excluded?("C1")
      assert html =~ "line-through"

      # Toggling back on re-includes it.
      html = render_click(view, "toggle_channel_excluded", %{"id" => "C1"})
      refute Slack.channel_excluded?("C1")
      refute html =~ "line-through"
    end

    test "close_slack_channels_modal hides the modal again" do
      {:ok, view, _html} = live(build_conn(), ~p"/settings")
      render_click(view, "open_slack_channels_modal")
      assert has_element?(view, "#slack-channels-modal")

      render_click(view, "close_slack_channels_modal")
      refute has_element?(view, "#slack-channels-modal")
    end

    test "an excluded channel is actually skipped by the next poll" do
      Slack.toggle_channel_excluded("C2")

      {:ok, view, _html} = live(build_conn(), ~p"/settings")
      render_click(view, "open_slack_channels_modal")

      html = render(view)
      assert html =~ "line-through"

      Req.Test.stub(Client, fn conn ->
        case conn.request_path do
          "/api/conversations.list" ->
            Req.Test.json(conn, %{
              "ok" => true,
              "channels" => [
                %{"id" => "C1", "name" => "general", "is_member" => true},
                %{"id" => "C2", "name" => "eng", "is_member" => true}
              ]
            })

          "/api/conversations.history" ->
            assert conn.query_params["channel"] == "C1"
            Req.Test.json(conn, %{"ok" => true, "messages" => []})

          "/api/reactions.list" ->
            Req.Test.json(conn, %{"ok" => true, "items" => []})
        end
      end)

      html = render_click(view, "poll_now")
      assert html =~ "Checked 1 channel(s)"
    end
  end
end
