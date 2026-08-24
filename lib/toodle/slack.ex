defmodule Toodle.Slack do
  @moduledoc """
  Polls public Slack channels you're already a member of for messages that
  mention you, creating a task in the "Inbox" project for each new one.
  No bot, no channel invites — authenticates as you via a personal Slack
  user token, since (unlike bot tokens) a user token can read public
  channel history without needing to be invited first.

  Scope for now: top-level channel messages only (no thread replies), and
  public channels only.
  """

  alias Toodle.{Projects, Settings, Tasks}
  alias Toodle.Slack.Client

  @token_key "slack_user_token"
  @user_id_key "slack_user_id"
  @cursors_key "slack_channel_cursors"
  @title_max_length 120

  def configured? do
    present?(token()) and present?(user_id())
  end

  def token, do: Settings.get(@token_key)
  def user_id, do: Settings.get(@user_id_key)

  def put_token(token) when is_binary(token), do: Settings.put(@token_key, String.trim(token))
  def put_user_id(user_id) when is_binary(user_id), do: Settings.put(@user_id_key, String.trim(user_id))

  @doc "Runs one poll cycle: check each member channel for new mentions, create Inbox tasks for them."
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
      created = results |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      {:ok, %{channels_checked: length(channels), tasks_created: created}}
    end
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
    inbox = Projects.get_or_create_inbox!()
    permalink = fetch_permalink(token, channel["id"], message["ts"])

    attrs = %{
      project_id: inbox.id,
      title: title_from(message["text"]),
      description: message["text"],
      slack_channel_id: channel["id"],
      slack_message_ts: message["ts"],
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
