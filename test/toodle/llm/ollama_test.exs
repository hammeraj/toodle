defmodule Toodle.Llm.OllamaTest do
  use ExUnit.Case, async: true

  alias Toodle.Llm.Ollama

  test "generate_json/2 decodes the model's JSON response" do
    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{"response" => Jason.encode!(%{"title" => "Fix the thing"})})
    end)

    assert {:ok, %{"title" => "Fix the thing"}} = Ollama.generate_json("clean this up")
  end

  test "generate_json/2 errors on a non-200 response" do
    Req.Test.stub(Ollama, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, "Ollama returned HTTP 500"} = Ollama.generate_json("clean this up")
  end

  test "generate_json/2 includes Ollama's own error detail on a non-200 JSON error body" do
    Req.Test.stub(Ollama, fn conn ->
      body = Jason.encode!(%{"error" => "model runner crashed: out of memory"})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(500, body)
    end)

    assert {:error, "Ollama returned HTTP 500: model runner crashed: out of memory"} =
             Ollama.generate_json("clean this up")
  end

  test "generate_json/2 errors when the response isn't valid JSON" do
    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{"response" => "not json"})
    end)

    assert {:error, %Jason.DecodeError{}} = Ollama.generate_json("clean this up")
  end

  test "ensure_model/1 posts to /api/pull and succeeds on 200" do
    Req.Test.stub(Ollama, fn conn ->
      assert conn.request_path == "/api/pull"
      Req.Test.json(conn, %{"status" => "success"})
    end)

    assert :ok = Ollama.ensure_model("qwen2.5:1.5b")
  end

  test "ensure_model/1 errors on a non-200 response" do
    Req.Test.stub(Ollama, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, "Ollama returned HTTP 500"} = Ollama.ensure_model("qwen2.5:1.5b")
  end

  test "model_present?/1 is true when the exact model name is in the local list" do
    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{"models" => [%{"name" => "qwen2.5:1.5b"}, %{"name" => "llama3.2:3b"}]})
    end)

    assert Ollama.model_present?("qwen2.5:1.5b")
    refute Ollama.model_present?("mistral:7b")
  end

  test "model_present?/1 matches an untagged model name against its :latest tag" do
    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{"models" => [%{"name" => "llama3.2:latest"}]})
    end)

    assert Ollama.model_present?("llama3.2")
  end

  test "model_present?/1 is false when Ollama is unreachable" do
    Req.Test.stub(Ollama, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    refute Ollama.model_present?("qwen2.5:1.5b")
  end
end
