defmodule ToodleWeb.TaskLive.Board do
  use ToodleWeb, :live_view

  alias Toodle.{Projects, Tasks}
  alias Toodle.Tasks.StatusMachine

  @per_page 15

  # Display-only ordering so active work surfaces first without literal
  # kanban swimlanes — not persisted, just how the flat list is sorted.
  @status_rank %{
    in_progress: 0,
    blocked: 1,
    interrupted: 1,
    paused: 1,
    not_started: 2,
    complete: 3
  }

  @status_badge_class %{
    not_started: "badge-ghost",
    in_progress: "badge-info",
    paused: "badge-neutral",
    blocked: "badge-error",
    interrupted: "badge-warning",
    complete: "badge-success"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:board}>
      <.header>
        Board
        <:actions>
          <div class="flex flex-wrap items-center gap-2">
            <.button variant="primary" navigate={~p"/tasks/new"}>
              <.icon name="hero-plus" /> New Task
            </.button>
            <label class="label cursor-pointer gap-2">
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                checked={@show_archived}
                phx-click="toggle_archived"
              />
              <span class="label-text">Show archived</span>
            </label>
          </div>
        </:actions>
      </.header>

      <div
        :if={@total_count == 0}
        class="rounded-2xl border border-dashed border-base-300 py-16 text-center"
      >
        <.icon name="hero-view-columns" class="size-10 mx-auto opacity-30 mb-3" />
        <p class="text-base-content/60">No tasks yet — create one to get started.</p>
      </div>

      <div :if={@total_count > 0} class="rounded-2xl border border-base-300 shadow-sm overflow-x-auto">
        <table class="table table-sm table-zebra">
          <thead>
            <tr>
              <th>Title</th>
              <th>
                <.form for={%{}} phx-change="filter_project" class="inline-block">
                  <select name="project_id" class="select select-ghost select-xs font-semibold">
                    <option value="" selected={@project_id == nil}>Project</option>
                    <option
                      :for={project <- @projects}
                      value={project.id}
                      selected={@project_id == project.id}
                    >
                      {project.name}
                    </option>
                  </select>
                </.form>
              </th>
              <th class="whitespace-nowrap">
                <button
                  type="button"
                  phx-click="sort_by"
                  phx-value-sort_by="status"
                  class="inline-flex items-center gap-0.5"
                >
                  Status <span :if={@sort_by == :status} class="opacity-70">⌄</span>
                </button>
              </th>
              <th class="whitespace-nowrap">
                <button
                  type="button"
                  phx-click="sort_by"
                  phx-value-sort_by="due_date"
                  class="inline-flex items-center gap-0.5"
                >
                  Due <span :if={@sort_by == :due_date} class="opacity-70">⌄</span>
                </button>
              </th>
              <th class="whitespace-nowrap">Est.</th>
              <th class="whitespace-nowrap">Elapsed</th>
              <th><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={task <- @tasks} id={"task-#{task.id}"}>
              <td>
                <.link navigate={~p"/tasks/#{task}"} class="hover:underline font-medium">
                  {task.title}
                </.link>
                <span :if={task.archived_at} class="badge badge-xs ml-1">archived</span>
              </td>
              <td>
                <span class="inline-flex items-center gap-1.5 text-base-content/70 whitespace-nowrap">
                  <span
                    class="inline-block size-2 rounded-full shrink-0"
                    style={"background-color: #{task.project.color || "var(--color-base-300)"}"}
                  />
                  {task.project.name}
                </span>
              </td>
              <td class="whitespace-nowrap">
                <span class={[
                  "badge badge-sm badge-soft",
                  Map.fetch!(@status_badge_class, task.status)
                ]}>
                  {humanize_status(task.status)}
                </span>
              </td>
              <td class="whitespace-nowrap text-sm">{format_date(task.due_date)}</td>
              <td class="whitespace-nowrap text-sm">{format_estimate(task.estimate_hours)}</td>
              <td class="whitespace-nowrap">
                <span :if={task.status == :in_progress} class="font-mono text-xs">
                  {format_duration(@elapsed[task.id] || 0)}
                </span>
              </td>
              <td>
                <div class="flex flex-wrap gap-1 justify-end">
                  <button
                    :for={next <- quick_transitions(task.status)}
                    class="btn btn-xs btn-ghost"
                    phx-click="change_status"
                    phx-value-id={task.id}
                    phx-value-status={next}
                  >
                    → {humanize_status(next)}
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>

        <div
          :if={@total_pages > 1}
          class="flex items-center justify-between px-4 py-3 border-t border-base-300 text-sm"
        >
          <span class="text-base-content/60">
            Page {@page} of {@total_pages} ({@total_count} tasks)
          </span>
          <div class="join">
            <button
              class="join-item btn btn-xs"
              disabled={@page <= 1}
              phx-click="paginate"
              phx-value-page={@page - 1}
            >
              «
            </button>
            <button
              class="join-item btn btn-xs"
              disabled={@page >= @total_pages}
              phx-click="paginate"
              phx-value-page={@page + 1}
            >
              »
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :tick, 1_000)
      Tasks.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Board")
     |> assign(:project_id, nil)
     |> assign(:show_archived, false)
     |> assign(:sort_by, :status)
     |> assign(:page, 1)
     |> assign(:projects, Projects.list_projects())
     |> assign(:status_badge_class, @status_badge_class)
     |> load_tasks(reset_page?: false)}
  end

  @impl true
  def handle_event("filter_project", %{"project_id" => ""}, socket) do
    {:noreply, socket |> assign(:project_id, nil) |> load_tasks(reset_page?: true)}
  end

  def handle_event("filter_project", %{"project_id" => project_id}, socket) do
    {:noreply, socket |> assign(:project_id, project_id) |> load_tasks(reset_page?: true)}
  end

  def handle_event("toggle_archived", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_archived, !socket.assigns.show_archived)
     |> load_tasks(reset_page?: true)}
  end

  def handle_event("sort_by", %{"sort_by" => sort_by}, socket) do
    {:noreply,
     socket |> assign(:sort_by, String.to_existing_atom(sort_by)) |> load_tasks(reset_page?: true)}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    {:noreply, socket |> assign(:page, String.to_integer(page)) |> load_tasks(reset_page?: false)}
  end

  def handle_event("change_status", %{"id" => id, "status" => status}, socket) do
    task = Tasks.get_task!(id)

    case Tasks.change_status(task, String.to_existing_atom(status)) do
      {:ok, _task} ->
        {:noreply, load_tasks(socket, reset_page?: false)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't change that task's status")}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 1_000)
    {:noreply, assign(socket, :elapsed, elapsed_map(socket.assigns.tasks))}
  end

  def handle_info(:tasks_changed, socket) do
    {:noreply, load_tasks(socket, reset_page?: false)}
  end

  defp load_tasks(socket, reset_page?: reset_page?) do
    opts = if socket.assigns.project_id, do: [project_id: socket.assigns.project_id], else: []
    opts = opts ++ [top_level_only: true, include_archived: socket.assigns.show_archived]

    all_tasks =
      Tasks.list_tasks(opts)
      |> Toodle.Repo.preload(:project)
      |> sort_tasks(socket.assigns.sort_by)

    total_count = length(all_tasks)
    total_pages = max(div(total_count + @per_page - 1, @per_page), 1)
    page = if reset_page?, do: 1, else: min(socket.assigns.page, total_pages)
    tasks = Enum.slice(all_tasks, (page - 1) * @per_page, @per_page)

    socket
    |> assign(:page, page)
    |> assign(:total_pages, total_pages)
    |> assign(:total_count, total_count)
    |> assign(:tasks, tasks)
    |> assign(:elapsed, elapsed_map(tasks))
  end

  defp sort_tasks(tasks, :due_date), do: Enum.sort_by(tasks, &due_date_sort_key/1)

  defp sort_tasks(tasks, :status) do
    Enum.sort_by(tasks, &{Map.fetch!(@status_rank, &1.status), &1.position, &1.inserted_at})
  end

  # Chronological, not Elixir's default struct term order (which would sort
  # %Date{} by field name, i.e. day before year) — tasks without a due date
  # sort last rather than first.
  defp due_date_sort_key(%{due_date: nil}), do: {1, {9999, 12, 31}}
  defp due_date_sort_key(%{due_date: due_date}), do: {0, Date.to_erl(due_date)}

  defp elapsed_map(tasks) do
    tasks
    |> Enum.filter(&(&1.status == :in_progress))
    |> Map.new(&{&1.id, Tasks.total_active_seconds(&1.id)})
  end

  defp quick_transitions(status) do
    status
    |> StatusMachine.allowed_next()
    |> Kernel.--([:blocked, :interrupted])
  end

  defp humanize_status(status), do: status |> to_string() |> String.replace("_", " ")

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d")

  defp format_estimate(nil), do: "—"

  defp format_estimate(hours) when hours == trunc(hours),
    do: "#{trunc(hours)}h"

  defp format_estimate(hours), do: "#{hours}h"

  defp format_duration(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    s = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> to_string()
  end
end
