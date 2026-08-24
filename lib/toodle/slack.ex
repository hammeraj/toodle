defmodule Toodle.Slack do
  @moduledoc """
  Polls Slack for two kinds of things to turn into tasks in the "Inbox"
  project: (1) messages in public channels you're already a member of that
  mention you, and (2) any message — including thread replies — that you've
  manually reacted to with a chosen emoji. No bot, no channel invites —
  authenticates as you via a personal Slack user token, since (unlike bot
  tokens) a user token can read public channel history without needing to
  be invited first.

  The mention scan is top-level-channel-messages-only (Slack's channel
  history API doesn't surface thread replies at all, and there's no cheap
  way to watch every thread for new activity). The emoji-reaction scan is
  the intended workaround for that: reacting to a buried thread reply picks
  it up regardless of where it lives.
  """

  alias Toodle.{Projects, Settings, Tasks}
  alias Toodle.Slack.Client

  @token_key "slack_user_token"
  @user_id_key "slack_user_id"
  @cursors_key "slack_channel_cursors"
  @reaction_emoji_key "slack_reaction_emoji"
  @default_reaction_emoji "star"
  @title_max_length 120

  def configured? do
    present?(token()) and present?(user_id())
  end

  def token, do: Settings.get(@token_key)
  def user_id, do: Settings.get(@user_id_key)
  def reaction_emoji, do: Settings.get(@reaction_emoji_key, @default_reaction_emoji)

  def put_token(token) when is_binary(token), do: Settings.put(@token_key, String.trim(token))
  def put_user_id(user_id) when is_binary(user_id), do: Settings.put(@user_id_key, String.trim(user_id))

  def put_reaction_emoji(emoji) when is_binary(emoji) do
    emoji = emoji |> String.trim() |> String.trim(":")
    Settings.put(@reaction_emoji_key, if(emoji == "", do: @default_reaction_emoji, else: emoji))
  end

  @doc "Runs one poll cycle: check for new mentions and new reactions, create Inbox tasks for them."
  def poll do
    if configured?() do
      do_poll(token(), user_id())
    else
      {:error, "Slack isn't configured yet — add a user token and your Slack user ID in Settings"}
    end
  end

  defp do_poll(token, user_id) do
    with {:ok, channels} <- Client.list_my_channels(token) do
      cursors = get_cursors()
      results = Enum.map(channels, &poll_channel(token, user_id, &1, Map.get(cursors, &1["id"])))
      mention_created = results |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      reaction_created = poll_reactions(token, user_id)
      {:ok, %{channels_checked: length(channels), tasks_created: mention_created + reaction_created}}
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
        items |> Enum.filter(&reacted_with?(&1, emoji, user_id)) |> Enum.count(&import_reaction(token, &1))

      {:error, _reason} ->
        0
    end
  end

  defp reacted_with?(%{"type" => "message", "message" => %{"reactions" => reactions}}, emoji, user_id)
       when is_list(reactions) do
    Enum.any?(reactions, fn r -> r["name"] == emoji and user_id in (r["users"] || []) end)
  end

  defp reacted_with?(_item, _emoji, _user_id), do: false

  defp import_reaction(token, %{"channel" => channel_id, "message" => message}) do
    do_import(token, channel_id, message["ts"], message["text"])
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
        mention = "<@#{user_id}>"
        mentioning = Enum.filter(messages, &mentions?(&1, mention))
        created = Enum.count(mentioning, &import_message(token, channel, &1))
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

  defp mentions?(%{"text" => text}, mention) when is_binary(text), do: String.contains?(text, mention)
  defp mentions?(_message, _mention), do: false

  defp import_message(token, channel, message) do
    do_import(token, channel["id"], message["ts"], message["text"])
  end

  defp do_import(token, channel_id, ts, text) do
    inbox = Projects.get_or_create_inbox!()
    permalink = fetch_permalink(token, channel_id, ts)

    attrs = %{
      project_id: inbox.id,
      title: title_from(text),
      description: text,
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
