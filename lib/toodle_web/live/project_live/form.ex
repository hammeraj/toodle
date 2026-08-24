defmodule ToodleWeb.ProjectLive.Form do
  use ToodleWeb, :live_view

  alias Toodle.Projects
  alias Toodle.Projects.Project

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:projects}>
      <.header>
        {@page_title}
      </.header>

      <.form
        for={@form}
        id="project-form"
        phx-change="validate"
        phx-submit="save"
        class="max-w-xl rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-1"
      >
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:description]} type="textarea" label="Description" />

        <div class="fieldset mb-2">
          <label for={@form[:color].id}>
            <span class="label mb-1">Color</span>
            <div class="flex items-center gap-3">
              <input
                type="color"
                name={@form[:color].name}
                id={@form[:color].id}
                value={@form[:color].value || "#f97316"}
                class="h-10 w-16 cursor-pointer rounded-lg border border-base-300 bg-transparent p-1"
              />
              <span class="font-mono text-sm text-base-content/70">
                {@form[:color].value || "#f97316"}
              </span>
            </div>
          </label>
        </div>

        <footer class="flex gap-2 pt-2">
          <.button phx-disable-with="Saving..." variant="primary">Save Project</.button>
          <.button navigate={~p"/projects"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    project = Projects.get_project!(id)

    socket
    |> assign(:page_title, "Edit Project")
    |> assign(:project, project)
    |> assign(:form, to_form(Projects.change_project(project)))
  end

  defp apply_action(socket, :new, _params) do
    project = %Project{}

    socket
    |> assign(:page_title, "New Project")
    |> assign(:project, project)
    |> assign(:form, to_form(Projects.change_project(project)))
  end

  @impl true
  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset = Projects.change_project(socket.assigns.project, project_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    save_project(socket, socket.assigns.live_action, project_params)
  end

  defp save_project(socket, :edit, project_params) do
    case Projects.update_project(socket.assigns.project, project_params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project updated successfully")
         |> push_navigate(to: ~p"/projects")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_project(socket, :new, project_params) do
    case Projects.create_project(project_params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created successfully")
         |> push_navigate(to: ~p"/projects")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
