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

  test "generate_json/2 errors when the response isn't valid JSON" do
    Req.Test.stub(Ollama, fn conn ->
      Req.Test.json(conn, %{"response" => "not json"})
    end)

    assert {:error, %Jason.DecodeError{}} = Ollama.generate_json("clean this up")
  end
end
