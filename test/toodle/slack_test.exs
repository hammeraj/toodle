defmodule Toodle.SlackTest do
  use Toodle.DataCase, async: false

  alias Toodle.{Inbox.Cleanup, Repo, Slack}
  alias Toodle.Llm.Ollama
  alias Toodle.Slack.Client
  alias Toodle.Tasks.Task

  setup do
    Slack.put_token("xoxp-test-token")
    Slack.put_user_id("U123")
    :ok
  end

  test "include_private_channels?/0 defaults to false and round-trips through put/1" do
    refute Slack.include_private_channels?()

    Slack.put_include_private_channels(true)
    assert Slack.include_private_channels?()

    Slack.put_include_private_channels(false)
    refute Slack.include_private_channels?()
  end

  test "include_dms?/0 defaults to false and round-trips through put/1" do
    refute Slack.include_dms?()

    Slack.put_include_dms(true)
    assert Slack.include_dms?()

    Slack.put_include_dms(false)
    refute Slack.include_dms?()
  end

  test "poll_interval_seconds/0 defaults to 60 and round-trips through put/1" do
    assert Slack.poll_interval_seconds() == 60

    Slack.put_poll_interval_seconds(120)
    assert Slack.poll_interval_seconds() == 120
  end

  test "put_poll_interval_seconds/1 floors below the minimum instead of accepting it" do
    Slack.put_poll_interval_seconds(1)
    assert Slack.poll_interval_seconds() == 15
  end

  test "poll/0 requests private channels once that setting is on" do
    Slack.put_include_private_channels(true)

    Req.Test.stub(Client, fn conn ->
      case conn.request_path do
        "/api/conversations.list" ->
          assert conn.query_params["types"] == "public_channel,private_channel"
          Req.Test.json(conn, %{"ok" => true, "channels" => []})

        "/api/reactions.list" ->
          Req.Test.json(conn, %{"ok" => true, "items" => []})
      end
    end)

    assert {:ok, %{channels_checked: 0, tasks_created: 0, reaction_error: nil}} = Slack.poll()
  end

  test "poll/0 surfaces a reactions.list failure instead of silently reporting zero" do
    Req.Test.stub(Client, fn conn ->
      case conn.request_path do
        "/api/conversations.list" -> Req.Test.json(conn, %{"ok" => true, "channels" => []})
        "/api/reactions.list" -> Req.Test.json(conn, %{"ok" => false, "error" => "missing_scope"})
      end
    end)

    assert {:ok, %{tasks_created: 0, reaction_error: "missing_scope"}} = Slack.poll()
  end

  test "poll/0 imports a message reacted to with the configured emoji" do
    Slack.put_reaction_emoji("memo")

    Req.Test.stub(Client, fn conn ->
      case conn.request_path do
        "/api/conversations.list" ->
          Req.Test.json(conn, %{"ok" => true, "channels" => []})

        "/api/reactions.list" ->
          Req.Test.json(conn, %{
            "ok" => true,
            "items" => [
              %{
                "type" => "message",
                "channel" => "C1",
                "message" => %{
                  "ts" => "1700000000.000100",
                  "text" => "buried thread reply",
                  "reactions" => [%{"name" => "memo", "users" => ["U123"]}]
                }
              }
            ]
          })

        "/api/chat.getPermalink" ->
          Req.Test.json(conn, %{"ok" => true, "permalink" => "https://slack.example/link"})
      end
    end)

    assert {:ok, %{tasks_created: 1, reaction_error: nil}} = Slack.poll()
  end

  test "poll/0 does not import a message reacted to with a different emoji" do
    Slack.put_reaction_emoji("memo")

    Req.Test.stub(Client, fn conn ->
      case conn.request_path do
        "/api/conversations.list" ->
          Req.Test.json(conn, %{"ok" => true, "channels" => []})

        "/api/reactions.list" ->
          Req.Test.json(conn, %{
            "ok" => true,
            "items" => [
              %{
                "type" => "message",
                "channel" => "C1",
                "message" => %{
                  "ts" => "1700000000.000200",
                  "text" => "not reacted with the right emoji",
                  "reactions" => [%{"name" => "star", "users" => ["U123"]}]
                }
              }
            ]
          })
      end
    end)

    assert {:ok, %{tasks_created: 0, reaction_error: nil}} = Slack.poll()
  end

  test "list_channels/0 returns channels from the client when configured" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, %{
        "ok" => true,
        "channels" => [%{"id" => "C1", "name" => "eng", "is_member" => true}]
      })
    end)

    assert {:ok, [%{"name" => "eng"}]} = Slack.list_channels()
  end

  describe "direct messages" do
    setup do
      Slack.put_include_dms(true)
      :ok
    end

    test "poll/0 requests DMs once that setting is on" do
      Req.Test.stub(Client, fn conn ->
        case conn.request_path do
          "/api/conversations.list" ->
            assert conn.query_params["types"] == "public_channel,im"
            Req.Test.json(conn, %{"ok" => true, "channels" => []})

          "/api/reactions.list" ->
            Req.Test.json(conn, %{"ok" => true, "items" => []})
        end
      end)

      assert {:ok, %{reaction_error: nil}} = Slack.poll()
    end

    test "every message from the other person in a DM is imported, no @-mention needed" do
      Req.Test.stub(Client, fn conn ->
        case conn.request_path do
          "/api/conversations.list" ->
            Req.Test.json(conn, %{
              "ok" => true,
              "channels" => [%{"id" => "D1", "is_im" => true, "user" => "U9"}]
            })

          "/api/conversations.history" ->
            refute conn.query_params["oldest"]

            # First sighting of this DM seeds the cursor without importing.
            Req.Test.json(conn, %{
              "ok" => true,
              "messages" => [%{"ts" => "1700000000.000100", "user" => "U9", "text" => "hi"}]
            })

          "/api/reactions.list" ->
            Req.Test.json(conn, %{"ok" => true, "items" => []})
        end
      end)

      assert {:ok, %{tasks_created: 0}} = Slack.poll()

      Req.Test.stub(Client, fn conn ->
        case conn.request_path do
          "/api/conversations.list" ->
            Req.Test.json(conn, %{
              "ok" => true,
              "channels" => [%{"id" => "D1", "is_im" => true, "user" => "U9"}]
            })

          "/api/conversations.history" ->
            assert conn.query_params["oldest"] == "1700000000.000100"

            Req.Test.json(conn, %{
              "ok" => true,
              "messages" => [
                %{"ts" => "1700000000.000200", "user" => "U9", "text" => "can you look at this?"},
                %{"ts" => "1700000000.000300", "user" => "U123", "text" => "sure, on it"}
              ]
            })

          "/api/reactions.list" ->
            Req.Test.json(conn, %{"ok" => true, "items" => []})

          "/api/chat.getPermalink" ->
            Req.Test.json(conn, %{"ok" => true, "permalink" => "https://slack.example/link"})
        end
      end)

      # Only the other person's message is imported -- the user's own reply
      # in the same DM is excluded, and neither needed an @-mention.
      assert {:ok, %{tasks_created: 1}} = Slack.poll()

      assert Repo.get_by(Task, slack_message_ts: "1700000000.000200")
      refute Repo.get_by(Task, slack_message_ts: "1700000000.000300")
    end
  end

  describe "thread context for reacted-to replies" do
    setup do
      Slack.put_reaction_emoji("memo")
      Cleanup.put_enabled(true)
      :ok
    end

    defp reaction_item(message) do
      %{
        "ok" => true,
        "items" => [%{"type" => "message", "channel" => "C1", "message" => message}]
      }
    end

    test "a reply's thread is fetched and passed to the model as context, but the stored description stays just the reply" do
      Req.Test.stub(Client, fn conn ->
        case conn.request_path do
          "/api/conversations.list" ->
            Req.Test.json(conn, %{"ok" => true, "channels" => []})

          "/api/reactions.list" ->
            Req.Test.json(
              conn,
              reaction_item(%{
                "ts" => "1700000000.000300",
                "thread_ts" => "1700000000.000100",
                "text" => "yeah let's do that Thursday",
                "reactions" => [%{"name" => "memo", "users" => ["U123"]}]
              })
            )

          "/api/conversations.replies" ->
            assert conn.query_params["ts"] == "1700000000.000100"

            Req.Test.json(conn, %{
              "ok" => true,
              "messages" => [
                %{"ts" => "1700000000.000100", "text" => "can someone bump the retry count?"},
                %{"ts" => "1700000000.000200", "text" => "sure, when?"},
                %{"ts" => "1700000000.000300", "text" => "yeah let's do that Thursday"}
              ]
            })

          "/api/chat.getPermalink" ->
            Req.Test.json(conn, %{"ok" => true, "permalink" => "https://slack.example/link"})
        end
      end)

      Req.Test.stub(Ollama, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"prompt" => prompt} = Jason.decode!(body)

        assert prompt =~ "bump the retry count"
        assert prompt =~ "yeah let's do that Thursday [REACTED TO THIS MESSAGE]"

        Req.Test.json(conn, %{
          "response" => Jason.encode!(%{"title" => "Bump the retry count Thursday"})
        })
      end)

      assert {:ok, %{tasks_created: 1}} = Slack.poll()

      task = Repo.get_by!(Task, slack_message_ts: "1700000000.000300")
      assert task.title == "Bump the retry count Thursday"
      assert task.description == "yeah let's do that Thursday"
    end

    test "a reply with no thread_ts (not actually threaded) skips the extra fetch" do
      Req.Test.stub(Client, fn conn ->
        case conn.request_path do
          "/api/conversations.list" ->
            Req.Test.json(conn, %{"ok" => true, "channels" => []})

          "/api/reactions.list" ->
            Req.Test.json(
              conn,
              reaction_item(%{
                "ts" => "1700000000.000400",
                "text" => "a standalone message",
                "reactions" => [%{"name" => "memo", "users" => ["U123"]}]
              })
            )

          "/api/conversations.replies" ->
            raise "should not fetch thread context for a message with no thread_ts"

          "/api/chat.getPermalink" ->
            Req.Test.json(conn, %{"ok" => true, "permalink" => "https://slack.example/link"})
        end
      end)

      Req.Test.stub(Ollama, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"prompt" => prompt} = Jason.decode!(body)

        refute prompt =~ "REACTED TO THIS MESSAGE"
        Req.Test.json(conn, %{"response" => Jason.encode!(%{"title" => "A standalone message"})})
      end)

      assert {:ok, %{tasks_created: 1}} = Slack.poll()
    end

    test "a long thread is capped to the parent plus the most recent messages" do
      thread_messages =
        for n <- 1..14 do
          %{
            "ts" => "1700000000.0#{String.pad_leading(to_string(n), 5, "0")}",
            "text" => "reply #{n}"
          }
        end

      target = List.last(thread_messages)

      Req.Test.stub(Client, fn conn ->
        case conn.request_path do
          "/api/conversations.list" ->
            Req.Test.json(conn, %{"ok" => true, "channels" => []})

          "/api/reactions.list" ->
            Req.Test.json(
              conn,
              reaction_item(%{
                "ts" => target["ts"],
                "thread_ts" => List.first(thread_messages)["ts"],
                "text" => target["text"],
                "reactions" => [%{"name" => "memo", "users" => ["U123"]}]
              })
            )

          "/api/conversations.replies" ->
            Req.Test.json(conn, %{"ok" => true, "messages" => thread_messages})

          "/api/chat.getPermalink" ->
            Req.Test.json(conn, %{"ok" => true, "permalink" => "https://slack.example/link"})
        end
      end)

      Req.Test.stub(Ollama, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"prompt" => prompt} = Jason.decode!(body)

        # Parent (reply 1) is always kept, and the target (reply 14) is
        # always included since it's the most recent message.
        assert prompt =~ "- reply 1\n"
        assert prompt =~ "reply 14 [REACTED TO THIS MESSAGE]"
        # Middle messages beyond the cap are dropped.
        refute prompt =~ "- reply 2\n"
        refute prompt =~ "- reply 3\n"

        Req.Test.json(conn, %{"response" => Jason.encode!(%{"title" => "Follow up"})})
      end)

      assert {:ok, %{tasks_created: 1}} = Slack.poll()
    end
  end
end
