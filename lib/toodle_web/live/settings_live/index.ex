defmodule ToodleWeb.SettingsLive.Index do
  use ToodleWeb, :live_view

  alias Toodle.Linear

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:settings}>
      <.header>Settings</.header>

      <section class="max-w-xl rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-3">
        <h3 class="font-semibold">Linear</h3>
        <p class="text-sm text-base-content/70">
          Paste a personal API key to enable "Refresh from Linear" on linked tasks.
          Read-only — Toodle never writes back to Linear.
        </p>
        <p>
          <span :if={@api_key_configured?} class="badge badge-success badge-soft">
            API key configured
          </span>
          <span :if={!@api_key_configured?} class="badge badge-ghost">No API key set</span>
        </p>

        <.form for={%{}} phx-submit="save_api_key" class="flex gap-2">
          <input
            type="password"
            name="api_key"
            placeholder={
              if @api_key_configured?,
                do: "•••••••••••••••• (enter a new key to replace it)",
                else: "lin_api_..."
            }
            class="input input-bordered flex-1"
          />
          <button type="submit" class="btn btn-primary">Save</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:api_key_configured?, Linear.api_key_configured?())}
  end

  @impl true
  def handle_event("save_api_key", %{"api_key" => ""}, socket) do
    {:noreply, put_flash(socket, :error, "Enter a key first")}
  end

  def handle_event("save_api_key", %{"api_key" => key}, socket) do
    {:ok, _setting} = Linear.put_api_key(key)

    {:noreply,
     socket
     |> assign(:api_key_configured?, true)
     |> put_flash(:info, "Linear API key saved")}
  end
end
