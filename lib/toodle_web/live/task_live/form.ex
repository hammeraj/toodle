defmodule ToodleWeb.TaskLive.Form do
  use ToodleWeb, :live_view

  alias Toodle.{Projects, Tasks}
  alias Toodle.Tasks.Task

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:board}>
      <.header>{@page_title}</.header>

      <.form
        for={@form}
        id="task-form"
        phx-change="validate"
        phx-submit="save"
        class="max-w-xl rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-1"
      >
        <.input
          field={@form[:project_id]}
          type="select"
          label="Project"
          prompt="Choose a project"
          options={Enum.map(@projects, &{&1.name, &1.id})}
        />
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input field={@form[:estimate_hours]} type="number" step="0.25" label="Estimate (hours)" />
        <.input field={@form[:start_date]} type="date" label="Start date" />
        <.input field={@form[:due_date]} type="date" label="Due date" />
        <footer class="flex gap-2 pt-2">
          <.button phx-disable-with="Saving..." variant="primary">Save Task</.button>
          <.button navigate={~p"/"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:projects, Projects.list_projects())
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    task = Tasks.get_task!(id)

    socket
    |> assign(:page_title, "Edit Task")
    |> assign(:task, task)
    |> assign(:form, to_form(Tasks.change_task(task)))
  end

  defp apply_action(socket, :new, params) do
    task = %Task{project_id: params["project_id"]}

    socket
    |> assign(:page_title, "New Task")
    |> assign(:task, task)
    |> assign(:form, to_form(Tasks.change_task(task)))
  end

  @impl true
  def handle_event("validate", %{"task" => task_params}, socket) do
    changeset = Tasks.change_task(socket.assigns.task, task_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"task" => task_params}, socket) do
    save_task(socket, socket.assigns.live_action, task_params)
  end

  defp save_task(socket, :edit, task_params) do
    case Tasks.update_task(socket.assigns.task, task_params) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task updated successfully")
         |> push_navigate(to: ~p"/tasks/#{task}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_task(socket, :new, task_params) do
    case Tasks.create_task(task_params) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task created successfully")
         |> push_navigate(to: ~p"/tasks/#{task}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
