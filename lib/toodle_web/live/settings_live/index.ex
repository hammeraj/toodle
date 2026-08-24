defmodule ToodleWeb.SettingsLive.Index do
  use ToodleWeb, :live_view

  alias Toodle.{Linear, Slack}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:settings}>
      <.header>Settings</.header>

      <div class="max-w-xl space-y-6">
        <section class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-3">
          <h3 class="font-semibold">Linear</h3>
          <p class="text-sm text-base-content/70">
            Paste a personal API key to enable "Refresh from Linear" on linked tasks.
            Read-only — Toodle never writes back to Linear.
          </p>
          <p>
            <span :if={@linear_configured?} class="badge badge-success badge-soft">
              API key configured
            </span>
            <span :if={!@linear_configured?} class="badge badge-ghost">No API key set</span>
          </p>

          <.form for={%{}} phx-submit="save_linear_key" class="flex gap-2">
            <input
              type="password"
              name="api_key"
              placeholder={
                if @linear_configured?,
                  do: "•••••••••••••••• (enter a new key to replace it)",
                  else: "lin_api_..."
              }
              class="input input-bordered flex-1"
            />
            <button type="submit" class="btn btn-primary">Save</button>
          </.form>
        </section>

        <section class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-3">
          <h3 class="font-semibold">Slack</h3>
          <p class="text-sm text-base-content/70">
            Checks public channels you're already in for messages mentioning you, about once a
            minute, and drops each new one into the "Inbox" project — no bot to invite anywhere.
            Ask Claude to triage the inbox to move items to the right project. Top-level channel
            messages only for mentions (no thread replies, no private channels/DMs) — but react
            with the emoji below to <em>any</em> message, including thread replies, to add it
            manually.
          </p>
          <p>
            <span :if={@slack_configured?} class="badge badge-success badge-soft">
              Configured
            </span>
            <span :if={!@slack_configured?} class="badge badge-ghost">Not configured</span>
          </p>

          <.form for={%{}} phx-submit="save_slack_token" class="space-y-2">
            <label class="fieldset">
              <span class="label mb-1">User OAuth token</span>
              <input
                type="password"
                name="token"
                placeholder={
                  if @slack_configured?,
                    do: "•••••••••••••••• (enter a new token to replace it)",
                    else: "xoxp-..."
                }
                class="input input-bordered w-full"
              />
            </label>
            <label class="fieldset">
              <span class="label mb-1">Your Slack user ID</span>
              <input
                type="text"
                name="user_id"
                placeholder={"U0123ABCD — from your Slack profile, \"Copy member ID\""}
                class="input input-bordered w-full"
              />
            </label>
            <label class="fieldset">
              <span class="label mb-1">Manual-add reaction emoji</span>
              <input
                type="text"
                name="reaction_emoji"
                value={@slack_reaction_emoji}
                placeholder="star"
                class="input input-bordered w-full"
              />
            </label>
            <button type="submit" class="btn btn-primary">Save</button>
          </.form>

          <button type="button" phx-click="poll_now" class="btn btn-sm btn-soft">
            <.icon name="hero-arrow-path" class="size-4" /> Check now
          </button>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:linear_configured?, Linear.api_key_configured?())
     |> assign(:slack_configured?, Slack.configured?())
     |> assign(:slack_reaction_emoji, Slack.reaction_emoji())}
  end

  @impl true
  def handle_event("save_linear_key", %{"api_key" => ""}, socket) do
    {:noreply, put_flash(socket, :error, "Enter a key first")}
  end

  def handle_event("save_linear_key", %{"api_key" => key}, socket) do
    {:ok, _setting} = Linear.put_api_key(key)

    {:noreply,
     socket
     |> assign(:linear_configured?, true)
     |> put_flash(:info, "Linear API key saved")}
  end

  def handle_event(
        "save_slack_token",
        %{"token" => token, "user_id" => user_id, "reaction_emoji" => reaction_emoji},
        socket
      ) do
    cond do
      token == "" and !socket.assigns.slack_configured? ->
        {:noreply, put_flash(socket, :error, "Enter a token first")}

      user_id == "" ->
        {:noreply, put_flash(socket, :error, "Enter your Slack user ID first")}

      true ->
        if token != "", do: Slack.put_token(token)
        Slack.put_user_id(user_id)
        if reaction_emoji != "", do: Slack.put_reaction_emoji(reaction_emoji)

        {:noreply,
         socket
         |> assign(:slack_configured?, Slack.configured?())
         |> assign(:slack_reaction_emoji, Slack.reaction_emoji())
         |> put_flash(:info, "Slack settings saved")}
    end
  end

  def handle_event("poll_now", _params, socket) do
    case Slack.poll() do
      {:ok, %{channels_checked: channels, tasks_created: created}} ->
        {:noreply,
         put_flash(socket, :info, "Checked #{channels} channel(s), created #{created} task(s)")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Slack check failed: #{reason}")}
    end
  end
end
