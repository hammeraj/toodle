defmodule ToodleWeb.SettingsLive.Index do
  use ToodleWeb, :live_view

  alias Toodle.{Linear, Slack, Updater}
  alias Toodle.Inbox.Cleanup

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
          <details class="text-sm text-base-content/70">
            <summary class="cursor-pointer font-medium text-base-content/90">
              How to get a token (required scopes)
            </summary>
            <div class="mt-2 space-y-2">
              <p>
                Create a Slack app at <a
                  href="https://api.slack.com/apps"
                  target="_blank"
                  class="link"
                >api.slack.com/apps</a>,
                then under <strong>OAuth &amp; Permissions</strong>
                add these under <strong>User Token Scopes</strong>
                (not Bot Token Scopes — this app authenticates
                as you, not as a bot, which is why nothing needs inviting to a channel):
              </p>
              <ul class="list-disc list-inside font-mono text-xs space-y-0.5">
                <li>
                  channels:read <span class="font-sans opacity-70">— list channels you're in</span>
                </li>
                <li>
                  channels:history <span class="font-sans opacity-70">— read mention messages</span>
                </li>
                <li>
                  reactions:read
                  <span class="font-sans opacity-70">— find messages you reacted to</span>
                </li>
              </ul>
              <p>
                Install the app to your workspace, then copy the <strong>User OAuth Token</strong>
                (starts with <code>xoxp-</code>) — not the Bot User OAuth Token — into the field
                below. If you add scopes to an app that's already installed, reinstall it; Slack
                won't grant new scopes to an existing token otherwise.
              </p>
              <p>
                Your Slack user ID is on your profile: <strong>⋮ More</strong>
                → <strong>Copy member ID</strong>.
              </p>
            </div>
          </details>
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

        <section class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-3">
          <h3 class="font-semibold">Inbox Cleanup</h3>
          <p :if={@inbox_cleanup_bundled?} class="text-sm text-base-content/70">
            Rewrites messy Slack messages into clean task titles using a small open-source
            language model bundled with Toodle — runs fully offline, nothing to install.
            Falls back to the raw message text automatically if the model can't produce a
            clean title for some reason.
          </p>
          <p :if={!@inbox_cleanup_bundled?} class="text-sm text-base-content/70">
            Rewrites messy Slack messages into clean task titles using a small open-source
            language model running locally via
            <a
              href="https://ollama.com"
              target="_blank"
              class="link"
            >Ollama</a>
            — nothing leaves your machine. This build doesn't bundle one, so install Ollama
            yourself, run <code class="text-xs">ollama pull {@inbox_cleanup_model}</code>
            (or whichever model you set below), then turn this on. Falls back to the raw
            message text automatically whenever Ollama isn't reachable.
          </p>

          <label class="label cursor-pointer w-fit gap-2">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              checked={@inbox_cleanup_enabled?}
              phx-click="toggle_inbox_cleanup"
            />
            <span>{if @inbox_cleanup_enabled?, do: "Enabled", else: "Disabled"}</span>
          </label>

          <.form for={%{}} phx-submit="save_inbox_cleanup_model" class="flex gap-2">
            <input
              type="text"
              name="model"
              value={@inbox_cleanup_model}
              placeholder="qwen2.5:1.5b"
              class="input input-bordered flex-1"
            />
            <button type="submit" class="btn btn-primary">Save</button>
          </.form>
        </section>

        <section class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-3">
          <h3 class="font-semibold">Software Update</h3>
          <p class="text-sm text-base-content/70">
            Checks the latest build published on GitHub. Updating downloads and installs it over
            this app, then restarts.
          </p>
          <p class="text-sm text-base-content/70">
            Running build: <code class="text-xs">{@build_sha || "development build"}</code>
          </p>

          <p :if={@update_status == :up_to_date}>
            <span class="badge badge-success badge-soft">Up to date</span>
          </p>
          <p :if={match?({:available, _}, @update_status)}>
            <span class="badge badge-warning badge-soft">Update available</span>
          </p>
          <p :if={match?({:error, _}, @update_status)} class="text-sm text-error">
            {elem(@update_status, 1)}
          </p>

          <div class="flex gap-2">
            <button
              type="button"
              phx-click="check_for_update"
              class="btn btn-sm btn-soft"
              disabled={@update_status == :checking}
            >
              <.icon name="hero-arrow-path" class="size-4" />
              {if @update_status == :checking, do: "Checking…", else: "Check for updates"}
            </button>
            <button
              :if={match?({:available, _}, @update_status) or @update_status == :applying}
              type="button"
              phx-click="apply_update"
              class="btn btn-sm btn-primary"
              disabled={@update_status == :applying}
            >
              {if @update_status == :applying,
                do: "Downloading…",
                else: "Update & restart"}
            </button>
          </div>
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
     |> assign(:slack_reaction_emoji, Slack.reaction_emoji())
     |> assign(:inbox_cleanup_enabled?, Cleanup.enabled?())
     |> assign(:inbox_cleanup_model, Cleanup.model())
     |> assign(:inbox_cleanup_bundled?, Toodle.Llm.OllamaServer.bundled?())
     |> assign(:build_sha, short_sha(Updater.local_sha()))
     |> assign(:update_status, nil)}
  end

  defp short_sha(nil), do: nil
  defp short_sha(sha), do: String.slice(sha, 0, 7)

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

  def handle_event("toggle_inbox_cleanup", _params, socket) do
    enabled? = !socket.assigns.inbox_cleanup_enabled?
    Cleanup.put_enabled(enabled?)
    {:noreply, assign(socket, :inbox_cleanup_enabled?, enabled?)}
  end

  def handle_event("save_inbox_cleanup_model", %{"model" => model}, socket) do
    Cleanup.put_model(model)
    {:noreply, assign(socket, :inbox_cleanup_model, Cleanup.model())}
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

  def handle_event("check_for_update", _params, socket) do
    case Updater.check() do
      {:ok, :up_to_date} ->
        {:noreply, assign(socket, :update_status, :up_to_date)}

      {:ok, {:update_available, info}} ->
        {:noreply, assign(socket, :update_status, {:available, info})}

      {:error, reason} ->
        {:noreply, assign(socket, :update_status, {:error, to_string(reason)})}
    end
  end

  def handle_event("apply_update", _params, socket) do
    case socket.assigns.update_status do
      {:available, %{asset: asset}} ->
        live_view_pid = self()

        Task.start(fn ->
          case Updater.download_and_apply(asset) do
            # Success quits the app partway through -- nothing left to
            # report back to, this branch only reachable on failure.
            {:error, reason} ->
              send(live_view_pid, {:update_failed, reason})

            :ok ->
              :ok
          end
        end)

        {:noreply, assign(socket, :update_status, :applying)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:update_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:update_status, {:error, to_string(reason)})
     |> put_flash(:error, "Update failed: #{inspect(reason)}")}
  end
end
