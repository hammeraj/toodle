defmodule Toodle.Slack.Client do
  @moduledoc """
  Minimal Slack Web API client for polling public channels a user is a
  member of, using their own user token (not a bot) — see `Toodle.Slack`
  for why: a user token can read public channel history without the
  workspace having to invite a bot into every channel.
  """

  @endpoint "https://slack.com/api"

  @doc "Lists public channels the token's user is a member of."
  def list_my_channels(token) do
    request(token, "conversations.list", %{
      types: "public_channel",
      exclude_archived: true,
      limit: 200
    })
    |> case do
      {:ok, %{"channels" => channels}} ->
        {:ok, Enum.filter(channels, & &1["is_member"])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Top-level messages in `channel_id` newer than `oldest_ts` (nil for no lower bound)."
  def channel_history(token, channel_id, oldest_ts) do
    params = %{channel: channel_id, limit: 200}
    params = if oldest_ts, do: Map.put(params, :oldest, oldest_ts), else: params

    case request(token, "conversations.history", params) do
      {:ok, %{"messages" => messages}} -> {:ok, messages}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "A permalink URL for a specific message, for linking back from a task."
  def permalink(token, channel_id, ts) do
    case request(token, "chat.getPermalink", %{channel: channel_id, message_ts: ts}) do
      {:ok, %{"permalink" => url}} -> {:ok, url}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(token, method, params) do
    case Req.get(@endpoint <> "/" <> method,
           params: params,
           headers: [{"authorization", "Bearer #{token}"}],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true} = body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, error}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Slack API returned HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end
end
