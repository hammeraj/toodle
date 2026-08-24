defmodule ToodleWeb.ProjectLive.Index do
  use ToodleWeb, :live_view

  alias Toodle.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:projects}>
      <.header>
        Projects
        <:actions>
          <.button variant="primary" navigate={~p"/projects/new"}>
            <.icon name="hero-plus" /> New Project
          </.button>
        </:actions>
      </.header>

      <div :if={@projects == []} class="rounded-2xl border border-dashed border-base-300 py-16 text-center">
        <.icon name="hero-folder" class="size-10 mx-auto opacity-30 mb-3" />
        <p class="text-base-content/60">No projects yet — create one to get started.</p>
      </div>

      <div :if={@projects != []} class="rounded-2xl border border-base-300 shadow-sm overflow-x-auto">
        <.table id="projects" rows={@projects}>
          <:col :let={project} label="Name">
            <span class="inline-flex items-center gap-2 font-medium">
              <span
                class="inline-block size-3 rounded-full ring-1 ring-base-content/10"
                style={"background-color: #{project.color || "var(--color-base-300)"}"}
              />
              {project.name}
            </span>
          </:col>
          <:col :let={project} label="Description">
            <span class="text-base-content/70">{project.description}</span>
          </:col>
          <:action :let={project}>
            <.link navigate={~p"/projects/#{project}/edit"} class="btn btn-xs btn-ghost">
              Edit
            </.link>
          </:action>
          <:action :let={project}>
            <.link
              phx-click={JS.push("archive", value: %{id: project.id})}
              data-confirm="Archive this project?"
              class="btn btn-xs btn-ghost"
            >
              Archive
            </.link>
          </:action>
        </.table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:projects, Projects.list_projects())}
  end

  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    project = Projects.get_project!(id)
    {:ok, _project} = Projects.archive_project(project)

    {:noreply, assign(socket, :projects, Projects.list_projects())}
  end
end
