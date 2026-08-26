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
end
