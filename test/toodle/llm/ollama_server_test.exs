defmodule Toodle.Llm.OllamaServerTest do
  use ExUnit.Case, async: true

  alias Toodle.Llm.OllamaServer

  test "bundled?/0 is false when this build ships no priv/ollama/bin/ollama" do
    refute OllamaServer.bundled?()
  end

  test "init/1 returns :ignore (so the supervisor just skips it) when nothing is bundled" do
    assert :ignore = OllamaServer.init([])
  end
end
