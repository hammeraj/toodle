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
  @auto_project_key "inbox_cleanup_auto_project"
  @auto_metadata_key "inbox_cleanup_auto_metadata"

  def enabled?, do: Settings.get(@enabled_key) == "true"

  def put_enabled(enabled?) when is_boolean(enabled?),
    do: Settings.put(@enabled_key, to_string(enabled?))

  def model, do: Settings.get(@model_key, Ollama.default_model())

  def put_model(model) when is_binary(model) do
    model = String.trim(model)
    Settings.put(@model_key, if(model == "", do: Ollama.default_model(), else: model))
  end

  @doc "Whether inbox items should get an automatic project guess."
  def auto_project_enabled?, do: Settings.get(@auto_project_key) == "true"

  def put_auto_project_enabled(enabled?) when is_boolean(enabled?),
    do: Settings.put(@auto_project_key, to_string(enabled?))

  @doc "Whether inbox items should get an automatic due date / estimate guess."
  def auto_metadata_enabled?, do: Settings.get(@auto_metadata_key) == "true"

  def put_auto_metadata_enabled(enabled?) when is_boolean(enabled?),
    do: Settings.put(@auto_metadata_key, to_string(enabled?))

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

  @doc """
  Suggests an existing project for `raw_text` out of `project_names`, or
  `nil` if disabled, nothing matched confidently, there are no candidate
  projects, or anything about the LLM call goes wrong. Most messages should
  come back `nil` — this only fires on an unambiguous match, so a caller can
  safely use it to route a task without a human double-checking first.
  """
  def suggest_project(_raw_text, []), do: nil

  def suggest_project(raw_text, project_names) when is_list(project_names) do
    if auto_project_enabled?() do
      raw_text
      |> project_prompt(project_names)
      |> Ollama.generate_json(model())
      |> project_name_or_nil(project_names)
    else
      nil
    end
  end

  defp project_name_or_nil({:ok, %{"project" => name}}, project_names) when is_binary(name) do
    if name in project_names, do: name
  end

  defp project_name_or_nil(_result, _project_names), do: nil

  defp project_prompt(raw_text, project_names) do
    """
    You file incoming messages into the right project for a to-do list app.

    Existing projects: #{Enum.join(project_names, ", ")}

    Decide which project (if any) the message below clearly belongs to. Only pick one \
    if it's obvious from the text — when in doubt, pick none.

    Respond with only a JSON object of the form {"project": "<exact project name from \
    the list above>"} or {"project": null}, and nothing else.

    Message:
    #{raw_text}
    """
  end

  @doc """
  Guesses a due date and/or hour estimate for `raw_text` from natural-
  language cues ("by Friday", "~2h", "quick fix"), resolved relative to
  `today`. Returns `%{due_date: Date.t() | nil, estimate_hours: float |
  nil}` — every field `nil` if disabled, nothing was mentioned, or the LLM
  call fails.
  """
  def suggest_metadata(raw_text, today \\ Date.utc_today()) do
    if auto_metadata_enabled?() do
      raw_text
      |> metadata_prompt(today)
      |> Ollama.generate_json(model())
      |> metadata_or_empty()
    else
      %{due_date: nil, estimate_hours: nil}
    end
  end

  defp metadata_prompt(raw_text, today) do
    """
    You pull a due date and a rough time estimate out of a message for a to-do list \
    app, when either is actually mentioned. Today's date is #{Date.to_iso8601(today)}.

    Resolve any relative date ("Friday", "tomorrow", "next week") to an absolute date. \
    Leave a field null if it isn't mentioned at all — don't guess.

    Respond with only a JSON object of the form {"due_date": "YYYY-MM-DD" or null, \
    "estimate_hours": <number> or null}, and nothing else.

    Message:
    #{raw_text}
    """
  end

  defp metadata_or_empty({:ok, %{"due_date" => due_date, "estimate_hours" => estimate}}) do
    %{due_date: parse_date(due_date), estimate_hours: parse_estimate(estimate)}
  end

  defp metadata_or_empty(_result), do: %{due_date: nil, estimate_hours: nil}

  defp parse_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_date), do: nil

  defp parse_estimate(estimate) when is_number(estimate) and estimate > 0, do: estimate / 1
  defp parse_estimate(_estimate), do: nil
end
