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

  @doc """
  All messages the token's user has reacted to, any emoji, any channel —
  including thread replies (reactions.list isn't scoped to channel history,
  so this is the only way to catch a mention buried in a thread). Paginates
  internally since there's no timestamp cursor to filter server-side.
  """
  def list_all_reactions(token), do: fetch_reactions_page(token, nil, [])

  defp fetch_reactions_page(token, cursor, acc) do
    params = %{limit: 200}
    params = if cursor, do: Map.put(params, :cursor, cursor), else: params

    case request(token, "reactions.list", params) do
      {:ok, %{"items" => items} = body} ->
        acc = acc ++ items

        case get_in(body, ["response_metadata", "next_cursor"]) do
          next when is_binary(next) and next != "" -> fetch_reactions_page(token, next, acc)
          _ -> {:ok, acc}
        end

      {:error, reason} ->
        {:error, reason}
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
