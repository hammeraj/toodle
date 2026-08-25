defmodule Toodle.MCP.Tools.Support do
  @moduledoc """
  Shared formatting/transition helpers for MCP tool modules — keeps every
  tool a thin adapter over `Toodle.Tasks`/`Toodle.Projects`/`Toodle.Sprints`
  instead of duplicating logic per tool.
  """

  alias Toodle.Tasks

  def task_summary(task) do
    %{
      id: task.id,
      title: task.title,
      status: task.status,
      project_id: task.project_id,
      parent_task_id: task.parent_task_id,
      estimate_hours: task.estimate_hours,
      due_date: task.due_date && Date.to_iso8601(task.due_date)
    }
  end

  def task_detail(task) do
    task
    |> task_summary()
    |> Map.merge(%{
      description: task.description,
      start_date: task.start_date && Date.to_iso8601(task.start_date),
      completed_at: task.completed_at && DateTime.to_iso8601(task.completed_at),
      archived_at: task.archived_at && DateTime.to_iso8601(task.archived_at),
      total_active_seconds: Tasks.total_active_seconds(task.id),
      subtasks: Enum.map(task.subtasks, &task_summary/1),
      open_event: open_event(task.task_events)
    })
  end

  def linear_summary(task) do
    %{
      id: task.id,
      linear_identifier: task.linear_identifier,
      linear_url: task.linear_url,
      linear_title: task.linear_title,
      linear_state: task.linear_state,
      linear_assignee_name: task.linear_assignee_name,
      linear_synced_at: task.linear_synced_at && DateTime.to_iso8601(task.linear_synced_at)
    }
  end

  defp open_event(events) do
    case Enum.find(events, &is_nil(&1.ended_at)) do
      nil ->
        nil

      event ->
        %{
          kind: event.kind,
          reason: event.reason,
          blocking_task_id: event.blocking_task_id,
          started_at: DateTime.to_iso8601(event.started_at)
        }
    end
  end

  @doc "Runs a `Tasks.change_status/3` transition and formats the result for a tool reply."
  def transition(task_id, status, opts \\ []) do
    task = Tasks.get_task!(task_id)

    case Tasks.change_status(task, status, opts) do
      {:ok, updated} ->
        {:ok, task_summary(updated)}

      {:error, :invalid_transition} ->
        {:error, "Can't move a #{task.status} task to #{status}"}

      {:error, :blocker_required} ->
        {:error, "Provide a blocking_task_id or a reason to block/interrupt a task"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset_errors(changeset)}

      {:error, other} ->
        {:error, inspect(other)}
    end
  rescue
    Ecto.NoResultsError -> {:error, "No task with that id"}
  end

  def changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
