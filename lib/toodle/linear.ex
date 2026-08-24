defmodule Toodle.Linear do
  @moduledoc """
  Lightweight, read-only Linear integration: link a task to an issue by
  identifier, then pull its title/state/assignee on demand. No OAuth, no
  webhooks, no write-back to Linear.
  """

  alias Toodle.{Repo, Settings}
  alias Toodle.Linear.Client
  alias Toodle.Tasks.Task

  @settings_key "linear_api_key"

  def api_key, do: Settings.get(@settings_key)

  def api_key_configured? do
    case api_key() do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  def put_api_key(key) when is_binary(key), do: Settings.put(@settings_key, String.trim(key))

  @doc "Pulls a Linear issue identifier (e.g. \"ENG-123\") out of a pasted URL or raw identifier."
  def parse_identifier(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      match = Regex.run(~r{linear\.app/[^/]+/issue/([A-Za-z]+-\d+)}i, input) -> Enum.at(match, 1)
      Regex.match?(~r{^[A-Za-z]+-\d+$}, input) -> String.upcase(input)
      true -> nil
    end
  end

  @doc "Links a task to a Linear issue (identifier only — call `refresh/1` to fetch its details)."
  def link_task(%Task{} = task, raw_input) do
    case parse_identifier(raw_input) do
      nil ->
        {:error, "Couldn't find a Linear issue identifier (like ENG-123) in that"}

      identifier ->
        task
        |> Task.linear_link_changeset(%{linear_identifier: identifier})
        |> Repo.update()
    end
  end

  def unlink_task(%Task{} = task) do
    task
    |> Task.linear_unlink_changeset()
    |> Repo.update()
  end

  @doc "Fetches the latest title/state/assignee from Linear for a task's linked issue."
  def refresh(%Task{linear_identifier: nil}), do: {:error, "This task isn't linked to a Linear issue"}

  def refresh(%Task{} = task) do
    with {:key, key} when is_binary(key) and key != "" <- {:key, api_key()},
         {:ok, issue} <- Client.fetch_issue(task.linear_identifier, key) do
      task
      |> Task.linear_sync_changeset(%{
        linear_issue_id: issue.id,
        linear_identifier: issue.identifier,
        linear_url: issue.url,
        linear_title: issue.title,
        linear_state: issue.state,
        linear_assignee_name: issue.assignee,
        linear_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()
    else
      {:key, _} -> {:error, "Set a Linear API key in Settings first"}
      {:error, reason} -> {:error, reason}
    end
  end
end
