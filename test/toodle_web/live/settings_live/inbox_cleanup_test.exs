defmodule ToodleWeb.SettingsLive.InboxCleanupTest do
  use ToodleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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
end
