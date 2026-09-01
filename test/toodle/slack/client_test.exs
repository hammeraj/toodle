defmodule Toodle.Slack.ClientTest do
  use ExUnit.Case, async: true

  alias Toodle.Slack.Client

  test "list_my_channels/2 requests only public channels by default" do
    Req.Test.stub(Client, fn conn ->
      assert conn.query_params["types"] == "public_channel"
      Req.Test.json(conn, %{"ok" => true, "channels" => []})
    end)

    assert {:ok, []} = Client.list_my_channels("token")
  end

  test "list_my_channels/2 includes private channels when asked" do
    Req.Test.stub(Client, fn conn ->
      assert conn.query_params["types"] == "public_channel,private_channel"
      Req.Test.json(conn, %{"ok" => true, "channels" => []})
    end)

    assert {:ok, []} = Client.list_my_channels("token", true)
  end

  test "list_my_channels/3 includes DMs when asked, alongside private channels" do
    Req.Test.stub(Client, fn conn ->
      assert conn.query_params["types"] == "public_channel,private_channel,im"
      Req.Test.json(conn, %{"ok" => true, "channels" => []})
    end)

    assert {:ok, []} = Client.list_my_channels("token", true, true)
  end

  test "list_my_channels/2 keeps only channels the user is a member of" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, %{
        "ok" => true,
        "channels" => [
          %{"id" => "C1", "name" => "general", "is_member" => true},
          %{"id" => "C2", "name" => "random", "is_member" => false}
        ]
      })
    end)

    assert {:ok, [%{"id" => "C1"}]} = Client.list_my_channels("token")
  end

  test "list_my_channels/3 keeps DMs even though they carry no is_member field" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, %{
        "ok" => true,
        "channels" => [
          %{"id" => "D1", "is_im" => true, "user" => "U9"},
          %{"id" => "C2", "name" => "random", "is_member" => false}
        ]
      })
    end)

    assert {:ok, [%{"id" => "D1"}]} = Client.list_my_channels("token", false, true)
  end

  test "list_all_reactions/1 follows pagination cursors" do
    Req.Test.stub(Client, fn conn ->
      case conn.query_params["cursor"] do
        nil ->
          Req.Test.json(conn, %{
            "ok" => true,
            "items" => [%{"type" => "message", "channel" => "C1"}],
            "response_metadata" => %{"next_cursor" => "page2"}
          })

        "page2" ->
          Req.Test.json(conn, %{
            "ok" => true,
            "items" => [%{"type" => "message", "channel" => "C2"}],
            "response_metadata" => %{"next_cursor" => ""}
          })
      end
    end)

    assert {:ok, [%{"channel" => "C1"}, %{"channel" => "C2"}]} =
             Client.list_all_reactions("token")
  end

  test "request/3 surfaces Slack's error string when ok is false" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, %{"ok" => false, "error" => "missing_scope"})
    end)

    assert {:error, "missing_scope"} = Client.list_my_channels("token")
  end

  test "request/3 surfaces a non-200 HTTP status" do
    Req.Test.stub(Client, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, "Slack API returned HTTP 500"} = Client.list_my_channels("token")
  end

  test "request/3 does not retry on a 500 -- a caller blocking on this (Check now) should fail fast" do
    test_pid = self()

    Req.Test.stub(Client, fn conn ->
      send(test_pid, :called)
      Plug.Conn.send_resp(conn, 500, "boom")
    end)

    assert {:error, "Slack API returned HTTP 500"} = Client.list_my_channels("token")

    assert_receive :called
    refute_receive :called, 300
  end

  test "thread_replies/3 requests the thread by channel and parent ts" do
    Req.Test.stub(Client, fn conn ->
      assert conn.query_params["channel"] == "C1"
      assert conn.query_params["ts"] == "1700000000.000100"

      Req.Test.json(conn, %{
        "ok" => true,
        "messages" => [
          %{"ts" => "1700000000.000100", "text" => "parent"},
          %{"ts" => "1700000000.000200", "text" => "reply"}
        ]
      })
    end)

    assert {:ok, [%{"text" => "parent"}, %{"text" => "reply"}]} =
             Client.thread_replies("token", "C1", "1700000000.000100")
  end
end
