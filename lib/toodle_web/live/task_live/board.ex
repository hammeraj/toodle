defmodule ToodleWeb.TaskLive.Board do
  use ToodleWeb, :live_view

  alias Toodle.{Projects, Tasks}
  alias Toodle.Tasks.StatusMachine

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
        <:subtitle>
          Blocking or interrupting a task needs a cause — do that from the task's detail page.
        </:subtitle>
        <:actions>
          <div class="flex flex-wrap items-center gap-2">
            <.button variant="primary" navigate={~p"/tasks/new"}>
              <.icon name="hero-plus" /> New Task
            </.button>
            <.form for={%{}} phx-change="filter_project">
              <select name="project_id" class="select select-bordered">
                <option value="" selected={@project_id == nil}>All projects</option>
                <option
                  :for={project <- @projects}
                  value={project.id}
                  selected={@project_id == project.id}
                >
                  {project.name}
                </option>
              </select>
            </.form>
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
        :if={@tasks == []}
        class="rounded-2xl border border-dashed border-base-300 py-16 text-center"
      >
        <.icon name="hero-view-columns" class="size-10 mx-auto opacity-30 mb-3" />
        <p class="text-base-content/60">No tasks yet — create one to get started.</p>
      </div>

      <div :if={@tasks != []} class="rounded-2xl border border-base-300 shadow-sm overflow-x-auto">
        <.table id="tasks" rows={@tasks}>
          <:col :let={task} label="Title">
            <.link navigate={~p"/tasks/#{task}"} class="hover:underline font-medium">
              {task.title}
            </.link>
            <span :if={task.archived_at} class="badge badge-xs ml-1">archived</span>
          </:col>
          <:col :let={task} label="Project">
            <span class="inline-flex items-center gap-1.5 text-base-content/70">
              <span
                class="inline-block size-2 rounded-full"
                style={"background-color: #{task.project.color || "var(--color-base-300)"}"}
              />
              {task.project.name}
            </span>
          </:col>
          <:col :let={task} label="Status">
            <span class={["badge badge-soft", Map.fetch!(@status_badge_class, task.status)]}>
              {humanize_status(task.status)}
            </span>
          </:col>
          <:col :let={task} label="Elapsed">
            <span :if={task.status == :in_progress} class="font-mono text-xs">
              {format_duration(@elapsed[task.id] || 0)}
            </span>
          </:col>
          <:action :let={task}>
            <button
              :for={next <- quick_transitions(task.status)}
              class="btn btn-xs btn-ghost"
              phx-click="change_status"
              phx-value-id={task.id}
              phx-value-status={next}
            >
              → {humanize_status(next)}
            </button>
          </:action>
        </.table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, 1_000)

    {:ok,
     socket
     |> assign(:page_title, "Board")
     |> assign(:project_id, nil)
     |> assign(:show_archived, false)
     |> assign(:projects, Projects.list_projects())
     |> assign(:status_badge_class, @status_badge_class)
     |> load_tasks()}
  end

  @impl true
  def handle_event("filter_project", %{"project_id" => ""}, socket) do
    {:noreply, socket |> assign(:project_id, nil) |> load_tasks()}
  end

  def handle_event("filter_project", %{"project_id" => project_id}, socket) do
    {:noreply, socket |> assign(:project_id, project_id) |> load_tasks()}
  end

  def handle_event("toggle_archived", _params, socket) do
    {:noreply, socket |> assign(:show_archived, !socket.assigns.show_archived) |> load_tasks()}
  end

  def handle_event("change_status", %{"id" => id, "status" => status}, socket) do
    task = Tasks.get_task!(id)

    case Tasks.change_status(task, String.to_existing_atom(status)) do
      {:ok, _task} ->
        {:noreply, load_tasks(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't change that task's status")}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 1_000)
    {:noreply, assign(socket, :elapsed, elapsed_map(socket.assigns.tasks))}
  end

  defp load_tasks(socket) do
    opts = if socket.assigns.project_id, do: [project_id: socket.assigns.project_id], else: []
    opts = opts ++ [top_level_only: true, include_archived: socket.assigns.show_archived]

    tasks =
      Tasks.list_tasks(opts)
      |> Toodle.Repo.preload(:project)
      |> Enum.sort_by(&{Map.fetch!(@status_rank, &1.status), &1.position, &1.inserted_at})

    socket
    |> assign(:tasks, tasks)
    |> assign(:elapsed, elapsed_map(tasks))
  end

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

  defp format_duration(seconds) do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    s = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> to_string()
  end
end
