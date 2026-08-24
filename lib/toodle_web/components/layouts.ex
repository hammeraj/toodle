defmodule ToodleWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ToodleWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :active, :atom,
    default: nil,
    doc: "which sidebar nav item to highlight (:board or :projects)"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen bg-base-100">
      <aside class="hidden md:flex md:w-64 md:shrink-0 md:flex-col border-r border-base-300 bg-base-200/60 px-4 py-6">
        <a href="/" class="flex items-center gap-2.5 px-2 mb-10">
          <img src={~p"/images/logo.svg"} width="30" />
          <span class="text-xl font-bold tracking-tight">Toodle</span>
        </a>

        <nav class="flex-1 space-y-1">
          <.nav_link navigate="/" icon="hero-view-columns" active={@active == :board}>
            Board
          </.nav_link>
          <.nav_link navigate="/projects" icon="hero-folder" active={@active == :projects}>
            Projects
          </.nav_link>
          <.nav_link navigate="/settings" icon="hero-cog-6-tooth" active={@active == :settings}>
            Settings
          </.nav_link>
        </nav>

        <div class="pt-4 mt-4 border-t border-base-300 flex justify-center">
          <.theme_toggle />
        </div>
      </aside>

      <div class="flex-1 min-w-0 flex flex-col">
        <header class="flex md:hidden items-center justify-between px-4 py-3 border-b border-base-300 bg-base-200/60">
          <a href="/" class="flex items-center gap-2">
            <img src={~p"/images/logo.svg"} width="24" />
            <span class="font-bold">Toodle</span>
          </a>
          <div class="flex items-center gap-1">
            <a href="/" class="btn btn-ghost btn-sm">Board</a>
            <a href="/projects" class="btn btn-ghost btn-sm">Projects</a>
            <a href="/settings" class="btn btn-ghost btn-sm">Settings</a>
          </div>
        </header>

        <main class="flex-1 px-6 py-8 lg:px-12 lg:py-10">
          <div class="mx-auto max-w-6xl">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
        @active && "bg-primary/15 text-primary",
        !@active && "text-base-content/70 hover:bg-base-300/70 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="size-5" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
