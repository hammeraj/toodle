defmodule Toodle.Slack do
  @moduledoc """
  Polls Slack for two kinds of things to turn into tasks in the "Inbox"
  project: (1) messages in channels you're already a member of that
  mention you (every message counts as "mentioning you" in a DM — there's
  no @-mention to look for in a 1:1 conversation), and (2) any message —
  including thread replies — that you've manually reacted to with a chosen
  emoji. No bot, no channel invites — authenticates as you via a personal
  Slack user token, since (unlike bot tokens) a user token can read channel
  history without needing to be invited first. Public channels only by
  default; private channels opt in via `include_private_channels?/0`
  (`groups:read` / `groups:history`), and DMs opt in via
  `include_dms?/0` (`im:read` / `im:history`) — each on top of the
  public-channel scopes.

  The mention scan is top-level-channel-messages-only (Slack's channel
  history API doesn't surface thread replies at all, and there's no cheap
  way to watch every thread for new activity). The emoji-reaction scan is
  the intended workaround for that: reacting to a buried thread reply picks
  it up regardless of where it lives. When the reacted message is itself a
  thread reply, title/project/due-date guessing also gets the surrounding
  thread (capped to `@max_thread_context_messages`) so a message that only
  makes sense in context ("yeah let's do that Thursday") doesn't turn into
  a meaningless task on its own.

  Runs on `Toodle.Slack.Poller`'s timer, once every
  `poll_interval_seconds/0` (default 60s, floored at
  `@min_poll_interval_seconds` to stay clear of Slack's rate limits).
  """

  alias Toodle.{Projects, Settings, Tasks}
  alias Toodle.Inbox.Cleanup
  alias Toodle.Slack.Client

  require Logger

  @token_key "slack_user_token"
  @user_id_key "slack_user_id"
  @cursors_key "slack_channel_cursors"
  @reaction_emoji_key "slack_reaction_emoji"
  @include_private_key "slack_include_private_channels"
  @include_dms_key "slack_include_dms"
  @poll_interval_key "slack_poll_interval_seconds"
  @default_reaction_emoji "star"
  @default_poll_interval_seconds 60
  @min_poll_interval_seconds 15
  @title_max_length 120
  @max_thread_context_messages 10

  def configured? do
    present?(token()) and present?(user_id())
  end

  def token, do: Settings.get(@token_key)
  def user_id, do: Settings.get(@user_id_key)
  def reaction_emoji, do: Settings.get(@reaction_emoji_key, @default_reaction_emoji)
  def include_private_channels?, do: Settings.get(@include_private_key) == "true"
  def include_dms?, do: Settings.get(@include_dms_key) == "true"

  def poll_interval_seconds do
    case Settings.get(@poll_interval_key) do
      nil -> @default_poll_interval_seconds
      value -> String.to_integer(value)
    end
  end

  def put_token(token) when is_binary(token), do: Settings.put(@token_key, String.trim(token))

  def put_user_id(user_id) when is_binary(user_id),
    do: Settings.put(@user_id_key, String.trim(user_id))

  def put_reaction_emoji(emoji) when is_binary(emoji) do
    emoji = emoji |> String.trim() |> String.trim(":")
    Settings.put(@reaction_emoji_key, if(emoji == "", do: @default_reaction_emoji, else: emoji))
  end

  def put_include_private_channels(include?) when is_boolean(include?),
    do: Settings.put(@include_private_key, to_string(include?))

  def put_include_dms(include?) when is_boolean(include?),
    do: Settings.put(@include_dms_key, to_string(include?))

  @doc "Sets the poll interval, floored at #{@min_poll_interval_seconds}s to stay clear of Slack's rate limits."
  def put_poll_interval_seconds(seconds) when is_integer(seconds) do
    Settings.put(@poll_interval_key, to_string(max(seconds, @min_poll_interval_seconds)))
  end

  @doc "Runs one poll cycle: check for new mentions and new reactions, create Inbox tasks for them."
  def poll do
    if configured?() do
      do_poll(token(), user_id())
    else
      {:error, "Slack isn't configured yet — add a user token and your Slack user ID in Settings"}
    end
  end

  @doc "Lists the channels currently being polled for mentions, for display in Settings."
  def list_channels do
    if configured?() do
      Client.list_my_channels(token(), include_private_channels?(), include_dms?())
    else
      {:error, "Slack isn't configured yet"}
    end
  end

  defp do_poll(token, user_id) do
    with {:ok, channels} <-
           Client.list_my_channels(token, include_private_channels?(), include_dms?()) do
      cursors = get_cursors()
      results = Enum.map(channels, &poll_channel(token, user_id, &1, Map.get(cursors, &1["id"])))
      mention_created = results |> Enum.map(&elem(&1, 1)) |> Enum.sum()

      {reaction_created, reaction_error} =
        case poll_reactions(token, user_id) do
          {:ok, count} -> {count, nil}
          {:error, reason} -> {0, reason}
        end

      {:ok,
       %{
         channels_checked: length(channels),
         tasks_created: mention_created + reaction_created,
         reaction_error: reaction_error
       }}
    end
  end

  # reactions.list has no timestamp cursor to filter server-side, so every
  # poll re-walks all of it — cheap in practice since it's bounded by how
  # much you personally react, not channel volume. Dedup rides on the same
  # (channel, ts) unique index Tasks already enforces for mention imports,
  # so a message that's both a mention and reacted-to only creates one task.
  defp poll_reactions(token, user_id) do
    case Client.list_all_reactions(token) do
      {:ok, items} ->
        emoji = reaction_emoji()

        created =
          items
          |> Enum.filter(&reacted_with?(&1, emoji, user_id))
          |> Enum.count(&import_reaction(token, &1))

        {:ok, created}

      {:error, reason} ->
        Logger.warning("Slack reactions poll failed: #{reason}")
        {:error, reason}
    end
  end

  defp reacted_with?(
         %{"type" => "message", "message" => %{"reactions" => reactions}},
         emoji,
         user_id
       )
       when is_list(reactions) do
    Enum.any?(reactions, fn r -> r["name"] == emoji and user_id in (r["users"] || []) end)
  end

  defp reacted_with?(_item, _emoji, _user_id), do: false

  defp import_reaction(token, %{"channel" => channel_id, "message" => message}) do
    context = thread_context(token, channel_id, message)
    do_import(token, channel_id, message["ts"], message["text"], context)
  end

  # A reacted-to message that's a thread reply often doesn't stand on its
  # own ("yeah let's do that Thursday") -- pull the surrounding thread so
  # title/project/due-date guessing has something to resolve it against.
  # Skipped for messages that aren't in a thread at all (no `thread_ts`),
  # which is most reactions, so this doesn't cost an extra API call there.
  defp thread_context(token, channel_id, %{"thread_ts" => thread_ts, "ts" => target_ts})
       when is_binary(thread_ts) do
    case Client.thread_replies(token, channel_id, thread_ts) do
      {:ok, messages} when length(messages) > 1 ->
        messages
        |> Enum.filter(&(&1["ts"] && &1["ts"] <= target_ts))
        |> Enum.sort_by(& &1["ts"])
        |> cap_ending_at(@max_thread_context_messages)
        |> format_thread(target_ts)

      {:ok, _messages} ->
        nil

      {:error, reason} ->
        Logger.debug("Slack thread fetch failed, importing without extra context: #{reason}")
        nil
    end
  end

  defp thread_context(_token, _channel_id, _message), do: nil

  # Keeps the thread's parent message plus the most recent messages leading
  # up to (and including) the reacted-to one -- later replies came after
  # whatever prompted the reaction, so they add nothing to understanding it.
  defp cap_ending_at(messages, max) when length(messages) <= max, do: messages

  defp cap_ending_at(messages, max) do
    parent = List.first(messages)
    recent = messages |> Enum.reverse() |> Enum.take(max - 1) |> Enum.reverse()
    [parent | recent]
  end

  defp format_thread(messages, target_ts) do
    messages
    |> Enum.map_join("\n", fn message ->
      text = message["text"] || ""
      if message["ts"] == target_ts, do: "- #{text} [REACTED TO THIS MESSAGE]", else: "- #{text}"
    end)
  end

  # First time seeing this channel: seed the cursor to "now" without
  # importing its backlog, so turning this on doesn't flood the inbox
  # with every historical mention.
  defp poll_channel(token, _user_id, channel, nil) do
    channel_id = channel["id"]

    case Client.channel_history(token, channel_id, nil) do
      {:ok, messages} -> put_cursor(channel_id, newest_ts(messages))
      {:error, _reason} -> :ok
    end

    {channel_id, 0}
  end

  defp poll_channel(token, user_id, channel, cursor) do
    channel_id = channel["id"]

    case Client.channel_history(token, channel_id, cursor) do
      {:ok, []} ->
        {channel_id, 0}

      {:ok, messages} ->
        relevant = Enum.filter(messages, &relevant?(&1, channel, user_id))
        created = Enum.count(relevant, &import_message(token, channel, &1))
        put_cursor(channel_id, newest_ts(messages) || cursor)
        {channel_id, created}

      {:error, _reason} ->
        {channel_id, 0}
    end
  end

  defp newest_ts(messages) do
    messages
    |> Enum.map(& &1["ts"])
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> nil
      timestamps -> Enum.max(timestamps)
    end
  end

  # In a DM there's no @-mention to look for -- every message the other
  # person sends is the whole point of importing that channel at all.
  # Your own outgoing messages are excluded so replying doesn't re-import
  # your side of the conversation.
  defp relevant?(message, %{"is_im" => true}, user_id), do: message["user"] != user_id
  defp relevant?(message, _channel, user_id), do: mentions?(message, "<@#{user_id}>")

  defp mentions?(%{"text" => text}, mention) when is_binary(text),
    do: String.contains?(text, mention)

  defp mentions?(_message, _mention), do: false

  defp import_message(token, channel, message) do
    do_import(token, channel["id"], message["ts"], message["text"])
  end

  defp do_import(token, channel_id, ts, text, thread_context \\ nil) do
    inbox = Projects.get_or_create_inbox!()
    permalink = fetch_permalink(token, channel_id, ts)
    guess_text = guess_text(text, thread_context)
    metadata = Cleanup.suggest_metadata(guess_text)

    attrs = %{
      project_id: suggested_project_id(guess_text, inbox),
      title: Cleanup.clean_title(guess_text, title_from(text)),
      description: text,
      due_date: metadata.due_date,
      estimate_hours: metadata.estimate_hours,
      slack_channel_id: channel_id,
      slack_message_ts: ts,
      slack_permalink: permalink
    }

    case Tasks.create_from_slack(attrs) do
      {:ok, %Tasks.Task{}} -> true
      {:ok, :duplicate} -> false
      {:error, _changeset} -> false
    end
  end

  # The description stays the single reacted message (faithful, concise —
  # the permalink already links back to the full thread on Slack); only
  # title/project/due-date guessing sees the surrounding thread, so a small
  # local model has enough to resolve "let's do that Thursday" without the
  # task's stored text turning into a whole transcript dump.
  defp guess_text(text, nil), do: text

  defp guess_text(_text, thread_context) do
    """
    Thread context, oldest to newest. Base the task on the message marked \
    [REACTED TO THIS MESSAGE] -- use the rest only to understand what it refers to.

    #{thread_context}
    """
  end

  # Falls back to the Inbox project whenever project guessing is off,
  # nothing matched confidently, or there's no other project to pick from
  # yet — every message always has somewhere to land.
  defp suggested_project_id(text, inbox) do
    other_projects = Enum.reject(Projects.list_projects(), &(&1.id == inbox.id))

    case Cleanup.suggest_project(text, Enum.map(other_projects, & &1.name)) do
      nil -> inbox.id
      name -> Enum.find(other_projects, &(&1.name == name)).id
    end
  end

  defp fetch_permalink(token, channel_id, ts) do
    case Client.permalink(token, channel_id, ts) do
      {:ok, url} -> url
      {:error, _reason} -> nil
    end
  end

  defp title_from(nil), do: "Slack mention"

  defp title_from(text) do
    text = String.trim(text)

    if String.length(text) > @title_max_length,
      do: String.slice(text, 0, @title_max_length) <> "…",
      else: text
  end

  defp get_cursors do
    case Settings.get(@cursors_key) do
      nil -> %{}
      json -> Jason.decode!(json)
    end
  end

  defp put_cursor(_channel_id, nil), do: :ok

  defp put_cursor(channel_id, ts) do
    cursors = get_cursors() |> Map.put(channel_id, ts) |> Jason.encode!()
    Settings.put(@cursors_key, cursors)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
