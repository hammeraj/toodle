defmodule Toodle.Inbox.CleanupTest do
  use Toodle.DataCase, async: false

  alias Toodle.Inbox.Cleanup
  alias Toodle.Llm.Ollama

  test "clean_title/2 returns the fallback when disabled" do
    refute Cleanup.enabled?()

    assert Cleanup.clean_title("hey can someone look at the deploy", "fallback title") ==
             "fallback title"
  end

  test "clean_title/2 returns the model's title when enabled" do
    Cleanup.put_enabled(true)

    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{
        "response" => Jason.encode!(%{"title" => "Investigate deploy failure"})
      })
    end)

    assert Cleanup.clean_title("hey can someone look at the deploy", "fallback title") ==
             "Investigate deploy failure"
  end

  test "clean_title/2 falls back when Ollama is unreachable" do
    Cleanup.put_enabled(true)

    Req.Test.stub(Ollama, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert Cleanup.clean_title("hey can someone look at the deploy", "fallback title") ==
             "fallback title"
  end

  test "clean_title/2 falls back when the model returns a blank title" do
    Cleanup.put_enabled(true)

    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{"response" => Jason.encode!(%{"title" => "   "})})
    end)

    assert Cleanup.clean_title("hey can someone look at the deploy", "fallback title") ==
             "fallback title"
  end

  test "model/0 defaults to the Ollama client's default model" do
    assert Cleanup.model() == Ollama.default_model()
  end

  test "put_model/1 trims and persists a custom model, blank resets to default" do
    Cleanup.put_model("  llama3.2:3b  ")
    assert Cleanup.model() == "llama3.2:3b"

    Cleanup.put_model("")
    assert Cleanup.model() == Ollama.default_model()
  end

  test "suggest_project/2 returns nil when disabled" do
    refute Cleanup.auto_project_enabled?()

    assert Cleanup.suggest_project("fix the staging deploy", ["Infra", "Marketing"]) == nil
  end

  test "suggest_project/2 returns nil without calling Ollama when there are no candidate projects" do
    Cleanup.put_auto_project_enabled(true)
    Req.Test.stub(Ollama, fn _conn -> raise "should not be called" end)

    assert Cleanup.suggest_project("fix the staging deploy", []) == nil
  end

  test "suggest_project/2 returns the model's pick when it's one of the candidates" do
    Cleanup.put_auto_project_enabled(true)

    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{"response" => Jason.encode!(%{"project" => "Infra"})})
    end)

    assert Cleanup.suggest_project("fix the staging deploy", ["Infra", "Marketing"]) == "Infra"
  end

  test "suggest_project/2 discards a hallucinated project name not in the candidate list" do
    Cleanup.put_auto_project_enabled(true)

    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{"response" => Jason.encode!(%{"project" => "Not A Real Project"})})
    end)

    assert Cleanup.suggest_project("fix the staging deploy", ["Infra", "Marketing"]) == nil
  end

  test "suggest_project/2 returns nil when Ollama is unreachable" do
    Cleanup.put_auto_project_enabled(true)
    Req.Test.stub(Ollama, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert Cleanup.suggest_project("fix the staging deploy", ["Infra"]) == nil
  end

  test "suggest_metadata/2 returns nil fields when disabled" do
    refute Cleanup.auto_metadata_enabled?()

    assert Cleanup.suggest_metadata("fix this by Friday, ~2h") ==
             %{due_date: nil, estimate_hours: nil}
  end

  test "suggest_metadata/2 resolves a due date and estimate relative to today" do
    Cleanup.put_auto_metadata_enabled(true)

    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{
        "response" => Jason.encode!(%{"due_date" => "2026-09-04", "estimate_hours" => 2})
      })
    end)

    assert Cleanup.suggest_metadata("fix this by Friday, ~2h", ~D[2026-09-01]) ==
             %{due_date: ~D[2026-09-04], estimate_hours: 2.0}
  end

  test "suggest_metadata/2 leaves fields nil when nothing was mentioned" do
    Cleanup.put_auto_metadata_enabled(true)

    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{
        "response" => Jason.encode!(%{"due_date" => nil, "estimate_hours" => nil})
      })
    end)

    assert Cleanup.suggest_metadata("just a general note") ==
             %{due_date: nil, estimate_hours: nil}
  end

  test "suggest_metadata/2 discards a malformed date and a non-positive estimate" do
    Cleanup.put_auto_metadata_enabled(true)

    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{
        "response" => Jason.encode!(%{"due_date" => "not a date", "estimate_hours" => -1})
      })
    end)

    assert Cleanup.suggest_metadata("garbage response") == %{due_date: nil, estimate_hours: nil}
  end

  test "suggest_metadata/2 returns nil fields when Ollama is unreachable" do
    Cleanup.put_auto_metadata_enabled(true)
    Req.Test.stub(Ollama, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert Cleanup.suggest_metadata("fix this by Friday") == %{due_date: nil, estimate_hours: nil}
  end
end
