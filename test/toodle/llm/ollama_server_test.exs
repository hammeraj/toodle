defmodule Toodle.Llm.OllamaServerTest do
  use ExUnit.Case, async: true

  alias Toodle.{Paths, Llm.OllamaServer}

  test "bundled?/0 is false when this build ships no priv/ollama/bin/ollama" do
    refute OllamaServer.bundled?()
  end

  test "init/1 returns :ignore (so the supervisor just skips it) when nothing is bundled" do
    assert :ignore = OllamaServer.init([])
  end

  test "models_dir/0 lives outside the release bundle, under the persistent app-data dir" do
    assert OllamaServer.models_dir() == Path.join(Paths.data_dir(), "ollama/models")
    refute String.contains?(OllamaServer.models_dir(), Application.app_dir(:toodle, "priv"))
  end
end
