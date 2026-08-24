defmodule ToodleWeb.TaskLive.Show do
  use ToodleWeb, :live_view

  alias Toodle.{Linear, Tasks}
  alias Toodle.Tasks.StatusMachine

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:board}>
      <.header>
        {@task.title}
        <:subtitle>{@task.project.name}{if @task.sprint, do: " · #{@task.sprint.name}"}</:subtitle>
        <:actions>
          <.button navigate={~p"/"}>
            <.icon name="hero-arrow-left" /> Board
          </.button>
          <.button navigate={~p"/tasks/#{@task}/edit"}>
            <.icon name="hero-pencil-square" /> Edit
          </.button>
          <.button
            :if={@task.status == :complete and is_nil(@task.archived_at)}
            phx-click="archive"
            data-confirm="Archive this task?"
          >
            <.icon name="hero-archive-box" /> Archive
          </.button>
          <.button
            phx-click="delete"
            data-confirm="Delete this task and all its subtasks? This can't be undone."
          >
            <.icon name="hero-trash" /> Delete
          </.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mt-6">
        <div class="lg:col-span-2 space-y-6">
          <section class="rounded-2xl border border-base-300 bg-base-100 p-5 space-y-3 shadow-sm">
            <div class="flex items-center justify-between">
              <span class={["badge badge-lg badge-soft", status_badge_class(@task.status)]}>
                {humanize(@task.status)}
              </span>
              <span :if={@task.status == :in_progress} class="font-mono text-sm font-medium">
                {format_duration(@elapsed)}
              </span>
            </div>

            <p :if={@task.description} class="text-sm opacity-80">{@task.description}</p>

            <.form for={%{}} phx-submit="transition" class="space-y-2">
              <div :if={@needs_blocker?} class="space-y-1">
                <select name="blocking_task_id" class="select select-bordered select-sm w-full">
                  <option value="">Blocked/interrupted by another task? (optional)</option>
                  <option :for={{label, id} <- @blocking_task_options} value={id}>{label}</option>
                </select>
                <textarea
                  name="reason"
                  class="textarea textarea-bordered w-full text-sm"
                  placeholder="Or describe why (a task reference or a note is required)"
                />
              </div>
              <textarea
                :if={@task.status in [:blocked, :interrupted]}
                name="resolution"
                class="textarea textarea-bordered w-full text-sm"
                placeholder="Resolution notes (optional)"
              />
              <div class="flex flex-wrap gap-2">
                <button
                  :for={next <- @next_statuses}
                  type="submit"
                  name="status"
                  value={next}
                  class="btn btn-sm btn-soft"
                >
                  {humanize(next)}
                </button>
              </div>
            </.form>
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-5 space-y-3 shadow-sm">
            <h3 class="font-semibold">Subtasks</h3>

            <div :for={subtask <- @task.subtasks} class="flex items-center justify-between text-sm">
              <.link navigate={~p"/tasks/#{subtask}"} class="hover:underline">
                {subtask.title}
              </.link>
              <span class={["badge badge-sm badge-soft", status_badge_class(subtask.status)]}>
                {humanize(subtask.status)}
              </span>
            </div>

            <.form for={%{}} phx-submit="add_subtask" class="flex gap-2">
              <input
                type="text"
                name="title"
                placeholder="New subtask title"
                class="input input-bordered input-sm flex-1"
                required
              />
              <button type="submit" class="btn btn-sm">Add</button>
            </.form>
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-5 space-y-3 shadow-sm">
            <h3 class="font-semibold">Blocks &amp; interrupts</h3>
            <p :if={@task.task_events == []} class="text-sm opacity-60">None yet.</p>
            <div
              :for={event <- @task.task_events}
              class="text-sm border-l-2 pl-3 border-base-content/20"
            >
              <div class="font-medium">
                {humanize(event.kind)} · {format_datetime(event.started_at)}
                <span :if={event.ended_at}>→ {format_datetime(event.ended_at)}</span>
                <span :if={!event.ended_at} class="badge badge-xs badge-warning">open</span>
              </div>
              <div :if={event.blocking_task} class="opacity-80">
                Blocked by
                <.link
                  navigate={~p"/tasks/#{event.blocking_task}"}
                  class="hover:underline font-medium"
                >
                  {event.blocking_task.title}
                </.link>
              </div>
              <div :if={event.reason} class="opacity-80">{event.reason}</div>
              <div :if={event.resolution} class="opacity-60 italic">Resolved: {event.resolution}</div>
            </div>
          </section>
        </div>

        <div class="space-y-6">
          <section class="rounded-2xl border border-base-300 bg-base-100 p-5 space-y-2 shadow-sm">
            <h3 class="font-semibold">Details</h3>
            <.list>
              <:item title="Estimate">{@task.estimate_hours || "—"} h</:item>
              <:item title="Start date">{@task.start_date || "—"}</:item>
              <:item title="Due date">{@task.due_date || "—"}</:item>
              <:item title="Total tracked">{format_duration(@total_seconds)}</:item>
              <:item :if={@task.slack_permalink} title="Source">
                <a href={@task.slack_permalink} target="_blank" class="link">View in Slack</a>
              </:item>
            </.list>
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-5 space-y-2 shadow-sm">
            <h3 class="font-semibold">Time log</h3>
            <p :if={@task.time_entries == []} class="text-sm opacity-60">No time tracked yet.</p>
            <div :for={entry <- @task.time_entries} class="text-sm flex justify-between">
              <span>{format_datetime(entry.started_at)}</span>
              <span>
                <%= if entry.duration_seconds do %>
                  {format_duration(entry.duration_seconds)} ({entry.stop_reason})
                <% else %>
                  running…
                <% end %>
              </span>
            </div>
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-5 space-y-3 shadow-sm">
            <h3 class="font-semibold">Linear</h3>

            <.form
              :if={is_nil(@task.linear_identifier)}
              for={%{}}
              phx-submit="link_linear"
              class="flex gap-2"
            >
              <input
                type="text"
                name="identifier"
                placeholder="ENG-123 or a Linear issue URL"
                class="input input-bordered input-sm flex-1"
                required
              />
              <button type="submit" class="btn btn-sm">Link</button>
            </.form>

            <div :if={@task.linear_identifier} class="space-y-2 text-sm">
              <div class="flex items-center justify-between">
                <%= if @task.linear_url do %>
                  <a href={@task.linear_url} target="_blank" class="link font-medium">
                    {@task.linear_identifier}
                  </a>
                <% else %>
                  <span class="font-medium">{@task.linear_identifier}</span>
                <% end %>
                <span :if={@task.linear_state} class="badge badge-sm badge-soft">{@task.linear_state}</span>
              </div>

              <p :if={@task.linear_title} class="opacity-80">{@task.linear_title}</p>
              <p :if={@task.linear_assignee_name} class="opacity-60">
                Assignee: {@task.linear_assignee_name}
              </p>
              <p class="opacity-50 text-xs">
                <%= if @task.linear_synced_at do %>
                  Synced {format_datetime(@task.linear_synced_at)}
                <% else %>
                  Not synced yet
                <% end %>
              </p>

              <div class="flex gap-2">
                <button type="button" phx-click="refresh_linear" class="btn btn-xs btn-soft">
                  <.icon name="hero-arrow-path" class="size-3" /> Refresh
                </button>
                <button type="button" phx-click="unlink_linear" class="btn btn-xs btn-ghost">
                  Unlink
                </button>
              </div>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, 1_000)
    {:ok, load_task(socket, id)}
  end

  @impl true
  def handle_event("transition", params, socket) do
    task = socket.assigns.task
    status = String.to_existing_atom(params["status"])
    opts = transition_opts(params)

    case Tasks.change_status(task, status, opts) do
      {:ok, _task} ->
        {:noreply, load_task(socket, task.id)}

      {:error, :blocker_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Pick a blocking task or write a reason to block/interrupt a task"
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't change that task's status")}
    end
  end

  def handle_event("add_subtask", %{"title" => title}, socket) do
    case Tasks.add_subtask(socket.assigns.task, %{"title" => title}) do
      {:ok, _subtask} ->
        {:noreply, load_task(socket, socket.assigns.task.id)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't add that subtask")}
    end
  end

  def handle_event("archive", _params, socket) do
    {:ok, _task} = Tasks.archive_task(socket.assigns.task)

    {:noreply,
     socket
     |> put_flash(:info, "Task archived")
     |> push_navigate(to: ~p"/")}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _task} = Tasks.delete_task(socket.assigns.task)

    {:noreply,
     socket
     |> put_flash(:info, "Task deleted")
     |> push_navigate(to: ~p"/")}
  end

  def handle_event("link_linear", %{"identifier" => input}, socket) do
    case Linear.link_task(socket.assigns.task, input) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> load_task(socket.assigns.task.id)
         |> put_flash(:info, "Linked — click Refresh to pull its details")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("refresh_linear", _params, socket) do
    case Linear.refresh(socket.assigns.task) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> load_task(socket.assigns.task.id)
         |> put_flash(:info, "Refreshed from Linear")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("unlink_linear", _params, socket) do
    {:ok, _task} = Linear.unlink_task(socket.assigns.task)
    {:noreply, load_task(socket, socket.assigns.task.id)}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 1_000)
    task = socket.assigns.task

    if task.status == :in_progress do
      {:noreply, assign(socket, :elapsed, Tasks.total_active_seconds(task.id))}
    else
      {:noreply, socket}
    end
  end

  defp transition_opts(params) do
    []
    |> put_if_present(:reason, params["reason"])
    |> put_if_present(:blocking_task_id, params["blocking_task_id"])
    |> put_if_present(:resolution, params["resolution"])
  end

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, _key, ""), do: opts
  defp put_if_present(opts, key, value), do: [{key, value} | opts]

  defp load_task(socket, id) do
    task = Tasks.get_task_with_details!(id)
    next_statuses = StatusMachine.allowed_next(task.status)

    socket
    |> assign(:page_title, task.title)
    |> assign(:task, task)
    |> assign(:next_statuses, next_statuses)
    |> assign(:needs_blocker?, Enum.any?(next_statuses, &(&1 in [:blocked, :interrupted])))
    |> assign(:blocking_task_options, Tasks.list_blocking_task_options(task.id))
    |> assign(:total_seconds, Tasks.total_active_seconds(task.id))
    |> assign(:elapsed, Tasks.total_active_seconds(task.id))
  end

  @status_badge_class %{
    not_started: "badge-ghost",
    in_progress: "badge-info",
    paused: "badge-neutral",
    blocked: "badge-error",
    interrupted: "badge-warning",
    complete: "badge-success"
  }

  defp status_badge_class(status), do: Map.fetch!(@status_badge_class, status)

  defp humanize(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_datetime(nil), do: "—"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp format_duration(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    s = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> to_string()
  end
end
