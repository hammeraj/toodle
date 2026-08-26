defmodule Toodle.Inbox.Cleanup do
  @moduledoc """
  Best-effort task title cleanup for inbox items, using a small local LLM
  through `Toodle.Llm.Ollama`. Off by default — the user has to opt in from
  Settings, since it depends on Ollama being installed and running locally
  with a model pulled. Whenever it's disabled, unreachable, or returns
  something we can't parse, callers just keep the fallback title they
  already had; this is strictly best-effort polish, never a hard
  dependency for turning a message into a task.
  """

  alias Toodle.Settings
  alias Toodle.Llm.Ollama

  @enabled_key "inbox_cleanup_enabled"
  @model_key "inbox_cleanup_model"

  def enabled?, do: Settings.get(@enabled_key) == "true"

  def put_enabled(enabled?) when is_boolean(enabled?),
    do: Settings.put(@enabled_key, to_string(enabled?))

  def model, do: Settings.get(@model_key, Ollama.default_model())

  def put_model(model) when is_binary(model) do
    model = String.trim(model)
    Settings.put(@model_key, if(model == "", do: Ollama.default_model(), else: model))
  end

  @doc """
  Returns a cleaned-up task title for `raw_text`, or `fallback` if cleanup
  is disabled or anything about the LLM call goes wrong.
  """
  def clean_title(raw_text, fallback) do
    if enabled?() do
      raw_text |> prompt() |> Ollama.generate_json(model()) |> title_or_fallback(fallback)
    else
      fallback
    end
  end

  defp title_or_fallback({:ok, %{"title" => title}}, fallback) when is_binary(title) do
    case String.trim(title) do
      "" -> fallback
      title -> title
    end
  end

  defp title_or_fallback(_result, fallback), do: fallback

  defp prompt(raw_text) do
    """
    You clean up raw Slack messages into short, clear task titles for a to-do list app.

    Rewrite the message below as a single concise task title: under 80 characters, no \
    surrounding quotes, no trailing punctuation. Keep it specific to the concrete thing \
    that needs doing — don't generalize it away.

    Respond with only a JSON object of the form {"title": "..."} and nothing else.

    Message:
    #{raw_text}
    """
  end
end
