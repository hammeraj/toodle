defmodule ToodleWeb.SettingsLive.Index do
  use ToodleWeb, :live_view

  alias Toodle.{Linear, Projects, Slack, Tasks, Updater}
  alias Toodle.Inbox.Cleanup
  alias Toodle.Llm.{Ollama, OllamaServer}

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
            Checks channels you're already in for messages mentioning you (every message counts
            in a DM, if you turn those on below), and drops each new one into the "Inbox"
            project — no bot to invite anywhere. Ask Claude to triage the inbox to move items to
            the right project. Public channels only unless you turn on private channels below.
            Top-level channel messages only for mentions (no thread replies) — but react with the
            emoji below to <em>any</em> message, including thread replies, to add it manually
            (with surrounding thread context included automatically, for a buried reply that
            doesn't stand on its own).
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
                <li>
                  groups:read
                  <span class="font-sans opacity-70">
                    — list private channels you're in (only if "Include private channels" below is on)
                  </span>
                </li>
                <li>
                  groups:history
                  <span class="font-sans opacity-70">
                    — read mentions in private channels (only if that's on)
                  </span>
                </li>
                <li>
                  im:read
                  <span class="font-sans opacity-70">
                    — list your DMs (only if "Include direct messages" below is on)
                  </span>
                </li>
                <li>
                  im:history
                  <span class="font-sans opacity-70">
                    — read messages in your DMs (only if that's on)
                  </span>
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
            <label class="fieldset">
              <span class="label mb-1">Poll interval (seconds, minimum 15)</span>
              <input
                type="number"
                name="poll_interval_seconds"
                value={@slack_poll_interval_seconds}
                min="15"
                placeholder="60"
                class="input input-bordered w-full"
              />
            </label>
            <button type="submit" class="btn btn-primary">Save</button>
          </.form>

          <div class="space-y-1.5">
            <label class="label cursor-pointer w-fit gap-2">
              <input
                type="checkbox"
                class="toggle toggle-primary toggle-sm"
                checked={@slack_include_private?}
                phx-click="toggle_slack_include_private"
              />
              <span>
                Include private channels — {if @slack_include_private?,
                  do: "Enabled",
                  else: "Disabled"}
              </span>
            </label>
            <label class="label cursor-pointer w-fit gap-2">
              <input
                type="checkbox"
                class="toggle toggle-primary toggle-sm"
                checked={@slack_include_dms?}
                phx-click="toggle_slack_include_dms"
              />
              <span>
                Include direct messages — {if @slack_include_dms?, do: "Enabled", else: "Disabled"}
              </span>
            </label>
          </div>

          <div class="flex gap-2">
            <button type="button" phx-click="poll_now" class="btn btn-sm btn-soft">
              <.icon name="hero-arrow-path" class="size-4" /> Check now
            </button>
            <button type="button" phx-click="refresh_slack_channels" class="btn btn-sm btn-soft">
              <.icon name="hero-arrow-path" class="size-4" /> Refresh channel list
            </button>
          </div>

          <div :if={@slack_configured?} class="text-sm space-y-1">
            <p class="font-medium text-base-content/90">Listening to</p>
            <p :if={@slack_channels == :error} class="text-error">
              Couldn't load the channel list — check your token and scopes.
            </p>
            <p :if={@slack_channels == []} class="text-base-content/60">
              No channels yet — join one in Slack, or turn on private channels/DMs above if the
              ones you want aren't public channels.
            </p>
            <ul :if={is_list(@slack_channels) and @slack_channels != []} class="flex flex-wrap gap-1">
              <li :for={channel <- @slack_channels} class="badge badge-ghost badge-sm font-mono">
                {channel_label(channel)}
              </li>
            </ul>
          </div>
        </section>

        <section class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-3">
          <h3 class="font-semibold">Board</h3>
          <p class="text-sm text-base-content/70">
            Archived tasks are hidden from the board by default.
          </p>

          <label class="label cursor-pointer w-fit gap-2">
            <input
              type="checkbox"
              class="toggle toggle-primary"
              checked={@board_show_archived?}
              phx-click="toggle_board_show_archived"
            />
            <span>{if @board_show_archived?, do: "Showing archived", else: "Hiding archived"}</span>
          </label>
        </section>

        <section class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-3">
          <h3 class="font-semibold">Inbox Cleanup</h3>
          <p :if={@inbox_cleanup_bundled?} class="text-sm text-base-content/70">
            Tidies up incoming Slack messages using a small open-source language model —
            the runtime ships with Toodle, nothing to install. The model itself (~1GB)
            downloads once the first time you turn a guess on below, then runs fully
            offline from then on — including across app updates, since it's kept outside
            the app bundle rather than redownloaded with every update. Each guess below is
            independent and best-effort: falls back to the raw message (and the Inbox
            project, and no due date/estimate) automatically whenever it's off or the model
            can't produce something usable.
          </p>
          <p :if={!@inbox_cleanup_bundled?} class="text-sm text-base-content/70">
            Tidies up incoming Slack messages using a small open-source language model
            running locally via <a href="https://ollama.com" target="_blank" class="link">Ollama</a>
            — nothing leaves your machine. This build doesn't bundle one, so install Ollama
            yourself, run <code class="text-xs">ollama pull {@inbox_cleanup_model}</code>
            (or whichever model you set below), then turn features on below. Each guess is
            independent and best-effort: falls back to the raw message (and the Inbox
            project, and no due date/estimate) automatically whenever Ollama isn't reachable.
          </p>

          <p :if={@inbox_cleanup_bundled?}>
            <span :if={@ollama_model_ready?} class="badge badge-success badge-soft badge-sm">
              Model ready
            </span>
            <span
              :if={!@ollama_model_ready? && @ollama_pulling?}
              class="badge badge-info badge-soft badge-sm"
            >
              Downloading model… (~1GB, one time)
            </span>
            <span
              :if={!@ollama_model_ready? && !@ollama_pulling? && !@ollama_pull_error}
              class="badge badge-ghost badge-sm"
            >
              Model downloads on first use (~1GB, one time)
            </span>
            <span
              :if={!@ollama_model_ready? && !@ollama_pulling? && @ollama_pull_error}
              class="badge badge-error badge-soft badge-sm"
            >
              Model download failed
            </span>
          </p>
          <p
            :if={!@ollama_model_ready? && !@ollama_pulling? && @ollama_pull_error}
            class="text-sm text-error"
          >
            Couldn't download the model: {@ollama_pull_error}
          </p>

          <div class="space-y-1.5">
            <label class="label cursor-pointer w-fit gap-2">
              <input
                type="checkbox"
                class="toggle toggle-primary toggle-sm"
                checked={@inbox_cleanup_enabled?}
                phx-click="toggle_inbox_cleanup"
              />
              <span>Clean up titles — {if @inbox_cleanup_enabled?, do: "Enabled", else: "Disabled"}</span>
            </label>
            <label class="label cursor-pointer w-fit gap-2">
              <input
                type="checkbox"
                class="toggle toggle-primary toggle-sm"
                checked={@inbox_cleanup_auto_project?}
                phx-click="toggle_inbox_cleanup_auto_project"
              />
              <span>
                Guess project — {if @inbox_cleanup_auto_project?, do: "Enabled", else: "Disabled"}
              </span>
            </label>
            <label class="label cursor-pointer w-fit gap-2">
              <input
                type="checkbox"
                class="toggle toggle-primary toggle-sm"
                checked={@inbox_cleanup_auto_metadata?}
                phx-click="toggle_inbox_cleanup_auto_metadata"
              />
              <span>
                Guess due date &amp; estimate — {if @inbox_cleanup_auto_metadata?,
                  do: "Enabled",
                  else: "Disabled"}
              </span>
            </label>
          </div>

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

          <div class="divider my-1" />

          <p class="text-sm font-medium">Try it on a sample message</p>
          <.form for={%{}} phx-submit="preview_inbox_cleanup" class="space-y-2">
            <textarea
              name="text"
              rows="3"
              class="textarea textarea-bordered w-full"
              placeholder="hey can someone look at the staging deploy, its been failing since this morning — should be quick"
            >{@preview_text}</textarea>
            <button type="submit" class="btn btn-sm btn-soft">Preview</button>
          </.form>

          <div :if={@preview_result} class="rounded-lg bg-base-200 p-3 text-sm space-y-1">
            <p>
              <span class="font-semibold">Title:</span>
              <%= if @inbox_cleanup_enabled? do %>
                {@preview_result.title}
                <span :if={@preview_result.title_error} class="text-error">
                  (unchanged — {@preview_result.title_error})
                </span>
              <% else %>
                <span class="text-base-content/50">cleanup is off</span>
              <% end %>
            </p>
            <p>
              <span class="font-semibold">Project:</span>
              <%= if @inbox_cleanup_auto_project? do %>
                {@preview_result.project || "no confident match — stays in Inbox"}
              <% else %>
                <span class="text-base-content/50">guessing is off</span>
              <% end %>
            </p>
            <p>
              <span class="font-semibold">Due date:</span>
              <%= if @inbox_cleanup_auto_metadata? do %>
                {format_date(@preview_result.due_date) || "nothing mentioned"}
              <% else %>
                <span class="text-base-content/50">guessing is off</span>
              <% end %>
            </p>
            <p>
              <span class="font-semibold">Estimate:</span>
              <%= if @inbox_cleanup_auto_metadata? do %>
                {format_estimate(@preview_result.estimate_hours) || "nothing mentioned"}
              <% else %>
                <span class="text-base-content/50">guessing is off</span>
              <% end %>
            </p>
          </div>
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
    bundled? = OllamaServer.bundled?()
    enabled? = Cleanup.enabled?()
    auto_project? = Cleanup.auto_project_enabled?()
    auto_metadata? = Cleanup.auto_metadata_enabled?()
    model = Cleanup.model()
    ready? = bundled? && Ollama.model_present?(model)

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:board_show_archived?, Tasks.show_archived?())
      |> assign(:linear_configured?, Linear.api_key_configured?())
      |> assign(:slack_configured?, Slack.configured?())
      |> assign(:slack_reaction_emoji, Slack.reaction_emoji())
      |> assign(:slack_include_private?, Slack.include_private_channels?())
      |> assign(:slack_include_dms?, Slack.include_dms?())
      |> assign(:slack_poll_interval_seconds, Slack.poll_interval_seconds())
      |> assign(:slack_channels, fetch_slack_channels(Slack.configured?()))
      |> assign(:inbox_cleanup_enabled?, enabled?)
      |> assign(:inbox_cleanup_auto_project?, auto_project?)
      |> assign(:inbox_cleanup_auto_metadata?, auto_metadata?)
      |> assign(:inbox_cleanup_model, model)
      |> assign(:inbox_cleanup_bundled?, bundled?)
      |> assign(:ollama_model_ready?, ready?)
      |> assign(:ollama_pulling?, false)
      |> assign(:ollama_pull_error, nil)
      |> assign(:preview_text, "")
      |> assign(:preview_result, nil)
      |> assign(:build_sha, short_sha(Updater.local_sha()))
      |> assign(:update_status, nil)

    # A feature left on from a previous session whose pull never finished
    # (interrupted quit, prior failure) would otherwise sit forever with no
    # feedback until the user happens to re-save the model field — retry it
    # here so opening Settings is enough to pick it back up.
    socket =
      if !ready? and (enabled? or auto_project? or auto_metadata?) do
        maybe_pull_model(socket)
      else
        socket
      end

    {:ok, socket}
  end

  defp title_and_error({:ok, title}, _fallback), do: {title, nil}
  defp title_and_error({:error, reason}, fallback), do: {fallback, reason}
  defp title_and_error(:disabled, fallback), do: {fallback, nil}

  defp fetch_slack_channels(false), do: []

  defp fetch_slack_channels(true) do
    case Slack.list_channels() do
      {:ok, channels} -> channels
      {:error, _reason} -> :error
    end
  end

  defp channel_label(%{"is_im" => true} = channel), do: "DM: #{channel["user"]}"
  defp channel_label(%{"is_private" => true} = channel), do: "🔒#{channel["name"]}"
  defp channel_label(channel), do: "##{channel["name"]}"

  defp short_sha(nil), do: nil
  defp short_sha(sha), do: String.slice(sha, 0, 7)

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  defp format_estimate(nil), do: nil
  defp format_estimate(hours) when hours == trunc(hours), do: "#{trunc(hours)}h"
  defp format_estimate(hours), do: "#{hours}h"

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
        %{
          "token" => token,
          "user_id" => user_id,
          "reaction_emoji" => reaction_emoji,
          "poll_interval_seconds" => poll_interval_seconds
        },
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

        case Integer.parse(poll_interval_seconds) do
          {seconds, _rest} -> Slack.put_poll_interval_seconds(seconds)
          :error -> :ok
        end

        configured? = Slack.configured?()

        {:noreply,
         socket
         |> assign(:slack_configured?, configured?)
         |> assign(:slack_reaction_emoji, Slack.reaction_emoji())
         |> assign(:slack_poll_interval_seconds, Slack.poll_interval_seconds())
         |> assign(:slack_channels, fetch_slack_channels(configured?))
         |> put_flash(:info, "Slack settings saved")}
    end
  end

  def handle_event("toggle_slack_include_private", _params, socket) do
    include? = !socket.assigns.slack_include_private?
    Slack.put_include_private_channels(include?)

    {:noreply,
     socket
     |> assign(:slack_include_private?, include?)
     |> assign(:slack_channels, fetch_slack_channels(socket.assigns.slack_configured?))}
  end

  def handle_event("toggle_slack_include_dms", _params, socket) do
    include? = !socket.assigns.slack_include_dms?
    Slack.put_include_dms(include?)

    {:noreply,
     socket
     |> assign(:slack_include_dms?, include?)
     |> assign(:slack_channels, fetch_slack_channels(socket.assigns.slack_configured?))}
  end

  def handle_event("refresh_slack_channels", _params, socket) do
    {:noreply,
     assign(socket, :slack_channels, fetch_slack_channels(socket.assigns.slack_configured?))}
  end

  def handle_event("toggle_board_show_archived", _params, socket) do
    show? = !socket.assigns.board_show_archived?
    Tasks.put_show_archived(show?)
    {:noreply, assign(socket, :board_show_archived?, show?)}
  end

  def handle_event("toggle_inbox_cleanup", _params, socket) do
    enabled? = !socket.assigns.inbox_cleanup_enabled?
    Cleanup.put_enabled(enabled?)

    socket = assign(socket, :inbox_cleanup_enabled?, enabled?)
    {:noreply, if(enabled?, do: maybe_pull_model(socket), else: socket)}
  end

  def handle_event("toggle_inbox_cleanup_auto_project", _params, socket) do
    enabled? = !socket.assigns.inbox_cleanup_auto_project?
    Cleanup.put_auto_project_enabled(enabled?)

    socket = assign(socket, :inbox_cleanup_auto_project?, enabled?)
    {:noreply, if(enabled?, do: maybe_pull_model(socket), else: socket)}
  end

  def handle_event("toggle_inbox_cleanup_auto_metadata", _params, socket) do
    enabled? = !socket.assigns.inbox_cleanup_auto_metadata?
    Cleanup.put_auto_metadata_enabled(enabled?)

    socket = assign(socket, :inbox_cleanup_auto_metadata?, enabled?)
    {:noreply, if(enabled?, do: maybe_pull_model(socket), else: socket)}
  end

  def handle_event("save_inbox_cleanup_model", %{"model" => model}, socket) do
    Cleanup.put_model(model)

    {:noreply,
     socket
     |> assign(:inbox_cleanup_model, Cleanup.model())
     |> maybe_pull_model()}
  end

  def handle_event("preview_inbox_cleanup", %{"text" => text}, socket) do
    case String.trim(text) do
      "" ->
        {:noreply, socket |> assign(:preview_text, "") |> assign(:preview_result, nil)}

      text ->
        project_names =
          Projects.list_projects() |> Enum.reject(&(&1.name == "Inbox")) |> Enum.map(& &1.name)

        metadata = Cleanup.suggest_metadata(text)
        {title, title_error} = title_and_error(Cleanup.clean_title_result(text), text)

        result = %{
          title: title,
          title_error: title_error,
          project: Cleanup.suggest_project(text, project_names),
          due_date: metadata.due_date,
          estimate_hours: metadata.estimate_hours
        }

        {:noreply, socket |> assign(:preview_text, text) |> assign(:preview_result, result)}
    end
  end

  def handle_event("poll_now", _params, socket) do
    case Slack.poll() do
      {:ok, %{channels_checked: channels, tasks_created: created, reaction_error: nil}} ->
        {:noreply,
         put_flash(socket, :info, "Checked #{channels} channel(s), created #{created} task(s)")}

      {:ok, %{channels_checked: channels, tasks_created: created, reaction_error: reason}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Checked #{channels} channel(s), created #{created} task(s) — " <>
             "but couldn't check reactions: #{reason}"
         )}

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

  # Kicks off a background pull of the currently-configured model against
  # the bundled server, then refreshes the readiness badge once it lands —
  # a no-op (no network call, badge unaffected) whenever there's no bundled
  # server to pull into. Ollama's own pull is a fast no-op when the model
  # is already present, so this always fires on opt-in/model-change rather
  # than trying to track readiness ourselves beforehand (which would go
  # stale the moment the model name changes).
  defp maybe_pull_model(socket) do
    if socket.assigns.inbox_cleanup_bundled? do
      model = socket.assigns.inbox_cleanup_model
      live_view_pid = self()

      Task.start(fn ->
        result = Ollama.ensure_model(model)
        send(live_view_pid, {:model_pull_finished, model, result})
      end)

      socket |> assign(:ollama_pulling?, true) |> assign(:ollama_pull_error, nil)
    else
      socket
    end
  end

  @impl true
  def handle_info({:model_pull_finished, model, result}, socket) do
    # Only trust this against whatever model is still configured by the
    # time the pull lands — the user may have changed it again mid-pull.
    if model == socket.assigns.inbox_cleanup_model do
      socket =
        socket
        |> assign(:ollama_pulling?, false)
        |> assign(:ollama_model_ready?, Ollama.model_present?(model))

      socket =
        case result do
          :ok -> assign(socket, :ollama_pull_error, nil)
          {:error, reason} -> assign(socket, :ollama_pull_error, reason)
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:update_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:update_status, {:error, to_string(reason)})
     |> put_flash(:error, "Update failed: #{inspect(reason)}")}
  end
end
