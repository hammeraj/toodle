defmodule ToodleWeb.SettingsLive.InboxCleanupTest do
  use ToodleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Toodle.Llm.Ollama
  alias Toodle.Projects

  test "toggling inbox cleanup persists across a reload, and the model can be saved" do
    {:ok, view, html} = live(build_conn(), ~p"/settings")

    assert html =~ "Inbox Cleanup"
    assert has_element?(view, "span", "Disabled")

    html = render_click(view, "toggle_inbox_cleanup")
    assert html =~ "Enabled"

    {:ok, _reloaded_view, reloaded_html} = live(build_conn(), ~p"/settings")
    assert reloaded_html =~ "Enabled"

    html =
      render_submit(view, "save_inbox_cleanup_model", %{"model" => "  llama3.2:3b  "})

    assert html =~ "llama3.2:3b"

    html = render_click(view, "toggle_inbox_cleanup")
    assert html =~ "Disabled"
  end

  test "toggling guess project and guess due date/estimate persists across a reload" do
    {:ok, view, _html} = live(build_conn(), ~p"/settings")

    html = render_click(view, "toggle_inbox_cleanup_auto_project")
    assert html =~ "Guess project — Enabled"

    html = render_click(view, "toggle_inbox_cleanup_auto_metadata")
    assert html =~ "Guess due date &amp; estimate — Enabled"

    {:ok, _reloaded_view, reloaded_html} = live(build_conn(), ~p"/settings")
    assert reloaded_html =~ "Guess project — Enabled"
    assert reloaded_html =~ "Guess due date &amp; estimate — Enabled"
  end

  test "previewing a sample message shows what each enabled guess would produce" do
    {:ok, project} = Projects.create_project(%{name: "Infra"})

    {:ok, view, _html} = live(build_conn(), ~p"/settings")

    render_click(view, "toggle_inbox_cleanup")
    render_click(view, "toggle_inbox_cleanup_auto_project")
    render_click(view, "toggle_inbox_cleanup_auto_metadata")

    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{
        "response" =>
          Jason.encode!(%{
            "title" => "Fix staging deploy",
            "project" => project.name,
            "due_date" => "2026-09-04",
            "estimate_hours" => 2
          })
      })
    end)

    html =
      render_submit(view, "preview_inbox_cleanup", %{
        "text" => "hey can someone look at the staging deploy, by Friday, ~2h"
      })

    assert html =~ "Fix staging deploy"
    assert html =~ project.name
    assert html =~ "Sep 04, 2026"
    assert html =~ "2h"
  end

  test "previewing shows each guess as off when its toggle is disabled" do
    {:ok, view, _html} = live(build_conn(), ~p"/settings")

    html = render_submit(view, "preview_inbox_cleanup", %{"text" => "fix this by Friday"})

    assert html =~ "cleanup is off"
    assert html =~ "guessing is off"
  end

  test "previewing a blank message clears the result" do
    {:ok, view, _html} = live(build_conn(), ~p"/settings")

    render_click(view, "toggle_inbox_cleanup")

    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{"response" => Jason.encode!(%{"title" => "Some title"})})
    end)

    html = render_submit(view, "preview_inbox_cleanup", %{"text" => "something"})
    assert html =~ "Some title"

    html = render_submit(view, "preview_inbox_cleanup", %{"text" => "   "})
    refute html =~ "Some title"
  end

  test "no model readiness badge or download attempt when nothing is bundled" do
    {:ok, view, html} = live(build_conn(), ~p"/settings")

    refute html =~ "Model ready"
    refute html =~ "Model downloads on first use"

    # Toggling on shouldn't blow up trying to pull into a bundled server
    # that doesn't exist in this build.
    html = render_click(view, "toggle_inbox_cleanup")
    assert html =~ "Enabled"
    refute html =~ "Model ready"
    refute html =~ "Model downloads on first use"
  end
end
