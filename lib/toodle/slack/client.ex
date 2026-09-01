defmodule Toodle.Slack.Client do
  @moduledoc """
  Minimal Slack Web API client for polling public channels a user is a
  member of, using their own user token (not a bot) — see `Toodle.Slack`
  for why: a user token can read public channel history without the
  workspace having to invite a bot into every channel.
  """

  @endpoint "https://slack.com/api"

  @doc """
  Lists channels the token's user is a member of. Public channels only by
  default; `include_private?: true` also includes private channels
  (`groups:read` / `groups:history`), and `include_dms?: true` also includes
  1:1 direct messages (`im:read` / `im:history`) — each on top of the
  public-channel scopes.
  """
  def list_my_channels(token, include_private? \\ false, include_dms? \\ false) do
    types =
      ["public_channel"]
      |> maybe_add_type("private_channel", include_private?)
      |> maybe_add_type("im", include_dms?)
      |> Enum.join(",")

    request(token, "conversations.list", %{
      types: types,
      exclude_archived: true,
      limit: 200
    })
    |> case do
      {:ok, %{"channels" => channels}} ->
        {:ok, Enum.filter(channels, &member?/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_add_type(types, type, true), do: types ++ [type]
  defp maybe_add_type(types, _type, false), do: types

  # conversations.list only sets `is_member` on channel-shaped results (public
  # and private channels) -- a DM being listed at all already means you're in
  # it, so there's no `is_member` key to check there.
  defp member?(%{"is_im" => true}), do: true
  defp member?(channel), do: channel["is_member"] == true

  @doc "Top-level messages in `channel_id` newer than `oldest_ts` (nil for no lower bound)."
  def channel_history(token, channel_id, oldest_ts) do
    params = %{channel: channel_id, limit: 200}
    params = if oldest_ts, do: Map.put(params, :oldest, oldest_ts), else: params

    case request(token, "conversations.history", params) do
      {:ok, %{"messages" => messages}} -> {:ok, messages}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  All messages in the thread rooted at `thread_ts` in `channel_id`, oldest
  first — the parent (top-level) message is always the first result. Used
  to give the emoji-reaction import more context than the single reacted
  message when it's a buried reply.
  """
  def thread_replies(token, channel_id, thread_ts) do
    case request(token, "conversations.replies", %{channel: channel_id, ts: thread_ts, limit: 200}) do
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

  # retry: false -- a poll (or a "Check now" click, which blocks the LiveView
  # process waiting on this) is written to fall back instantly on any
  # failure; Req's default retry-with-backoff would instead turn one bad
  # response into several seconds of silent hanging first.
  defp request(token, method, params) do
    req =
      [
        base_url: @endpoint,
        url: "/" <> method,
        params: params,
        headers: [{"authorization", "Bearer #{token}"}],
        receive_timeout: 10_000,
        retry: false
      ]
      |> Req.new()
      |> maybe_plug()

    case Req.get(req) do
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

  defp maybe_plug(req) do
    case Application.get_env(:toodle, __MODULE__, [])[:plug] do
      nil -> req
      plug -> Req.merge(req, plug: plug)
    end
  end
end
