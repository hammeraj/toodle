defmodule Toodle.Tasks do
  @moduledoc """
  The Tasks context — CRUD for tasks/subtasks, and the single choke point
  (`change_status/3`) through which every status transition, timer
  start/stop, and block/interrupt event flows.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Toodle.Repo
  alias Toodle.Tasks.{Task, TaskEvent, TimeEntry, StatusMachine}

  ## CRUD

  def list_tasks(opts \\ []) do
    Task
    |> filter(:project_id, opts)
    |> filter(:sprint_id, opts)
    |> filter(:status, opts)
    |> maybe_top_level_only(opts)
    |> maybe_exclude_archived(opts)
    |> order_by([t], asc: t.position, asc: t.inserted_at)
    |> Repo.all()
  end

  defp filter(query, field, opts) do
    case Keyword.get(opts, field) do
      nil -> query
      value -> where(query, [t], field(t, ^field) == ^value)
    end
  end

  defp maybe_top_level_only(query, opts) do
    if Keyword.get(opts, :top_level_only, true) do
      where(query, [t], is_nil(t.parent_task_id))
    else
      query
    end
  end

  defp maybe_exclude_archived(query, opts) do
    if Keyword.get(opts, :include_archived, false) do
      query
    else
      where(query, [t], is_nil(t.archived_at))
    end
  end

  @doc "Options for a 'blocked by' picker: {label, id} for every other non-archived task, project-prefixed."
  def list_blocking_task_options(exclude_task_id) do
    Task
    |> where([t], t.id != ^exclude_task_id and is_nil(t.archived_at))
    |> order_by([t], asc: t.title)
    |> preload(:project)
    |> Repo.all()
    |> Enum.map(&{"#{&1.project.name} / #{&1.title}", &1.id})
  end

  def get_task!(id), do: Repo.get!(Task, id)

  def get_task_with_details!(id) do
    Task
    |> Repo.get!(id)
    |> Repo.preload([
      :project,
      :sprint,
      subtasks: from(t in Task, order_by: [asc: t.position, asc: t.inserted_at]),
      task_events: {from(e in TaskEvent, order_by: [desc: e.started_at]), [:blocking_task]},
      time_entries: from(te in TimeEntry, order_by: [desc: te.started_at])
    ])
  end

  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(stringify_keys(attrs))
    |> validate_parent_not_nested()
    |> Repo.insert()
  end

  @doc "Creates a subtask under `parent`, inheriting its project (and sprint, unless overridden)."
  def add_subtask(%Task{} = parent, attrs \\ %{}) do
    attrs
    |> stringify_keys()
    |> Map.put("parent_task_id", parent.id)
    |> Map.put("project_id", parent.project_id)
    |> Map.put_new("sprint_id", parent.sprint_id)
    |> create_task()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(stringify_keys(attrs))
    |> validate_parent_not_nested()
    |> validate_no_grandchildren()
    |> Repo.update()
  end

  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  @doc "Archives a task, hiding it from the default task list. Only makes sense for completed tasks."
  def archive_task(%Task{} = task) do
    task
    |> Task.archive_changeset(%{archived_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  def unarchive_task(%Task{} = task) do
    task
    |> Task.archive_changeset(%{archived_at: nil})
    |> Repo.update()
  end

  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  defp validate_parent_not_nested(changeset) do
    case Ecto.Changeset.get_change(changeset, :parent_task_id) do
      nil ->
        changeset

      parent_id ->
        case Repo.get(Task, parent_id) do
          %Task{parent_task_id: nil} ->
            changeset

          %Task{} ->
            Ecto.Changeset.add_error(
              changeset,
              :parent_task_id,
              "can't nest a subtask under another subtask"
            )

          nil ->
            changeset
        end
    end
  end

  defp validate_no_grandchildren(changeset) do
    with id when not is_nil(id) <- changeset.data.id,
         parent_id when not is_nil(parent_id) <- Ecto.Changeset.get_change(changeset, :parent_task_id),
         true <- Repo.exists?(from t in Task, where: t.parent_task_id == ^id) do
      Ecto.Changeset.add_error(changeset, :parent_task_id, "already has subtasks of its own")
    else
      _ -> changeset
    end
  end

  ## Status transitions — the only path by which status, timers, and
  ## block/interrupt events change.

  @doc """
  Transitions `task` to `new_status`, applying whatever side effects that
  transition requires (starting/stopping the timer, opening/closing a
  block or interrupt event) in a single DB transaction.

  Options:
    * `:blocking_task_id` — the task causing the block/interrupt
    * `:reason` — free-text note; at least one of `:blocking_task_id`/`:reason`
      is required when transitioning into `:blocked` or `:interrupted`
    * `:resolution` — optional note recorded when leaving `:blocked`/`:interrupted`
  """
  def change_status(%Task{} = task, new_status, opts \\ []) when is_atom(new_status) do
    from_status = task.status

    cond do
      not StatusMachine.transition?(from_status, new_status) ->
        {:error, :invalid_transition}

      :open_task_event in StatusMachine.side_effects(from_status, new_status) and
        is_nil(Keyword.get(opts, :reason)) and is_nil(Keyword.get(opts, :blocking_task_id)) ->
        {:error, :blocker_required}

      true ->
        do_change_status(task, from_status, new_status, opts)
    end
  end

  defp do_change_status(task, from_status, new_status, opts) do
    effects = StatusMachine.side_effects(from_status, new_status)
    reason = Keyword.get(opts, :reason)
    blocking_task_id = Keyword.get(opts, :blocking_task_id)
    resolution = Keyword.get(opts, :resolution)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.update(:task, task_status_changeset(task, new_status, now))
    |> maybe_stop_timer(effects, task.id, new_status, now)
    |> maybe_start_timer(effects, task.id, now)
    |> maybe_open_task_event(effects, task.id, new_status, reason, blocking_task_id, now)
    |> maybe_close_task_event(effects, task.id, resolution, now)
    |> Repo.transaction()
    |> case do
      {:ok, %{task: task}} -> {:ok, task}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp task_status_changeset(task, new_status, now) do
    completed_at = if new_status == :complete, do: now, else: nil
    Task.status_changeset(task, %{status: new_status, completed_at: completed_at})
  end

  defp maybe_stop_timer(multi, effects, task_id, new_status, now) do
    if :stop_timer in effects do
      Multi.run(multi, :close_time_entry, fn repo, _changes ->
        close_open_time_entry(repo, task_id, now, stop_reason_for(new_status))
      end)
    else
      multi
    end
  end

  defp maybe_start_timer(multi, effects, task_id, now) do
    if :start_timer in effects do
      Multi.insert(
        multi,
        :time_entry,
        TimeEntry.open_changeset(%TimeEntry{}, %{task_id: task_id, started_at: now})
      )
    else
      multi
    end
  end

  defp maybe_open_task_event(multi, effects, task_id, new_status, reason, blocking_task_id, now) do
    if :open_task_event in effects do
      Multi.insert(
        multi,
        :task_event,
        TaskEvent.open_changeset(%TaskEvent{}, %{
          task_id: task_id,
          blocking_task_id: blocking_task_id,
          kind: new_status,
          reason: reason,
          started_at: now
        })
      )
    else
      multi
    end
  end

  defp maybe_close_task_event(multi, effects, task_id, resolution, now) do
    if :close_task_event in effects do
      Multi.run(multi, :close_task_event, fn repo, _changes ->
        close_open_task_event(repo, task_id, resolution, now)
      end)
    else
      multi
    end
  end

  defp close_open_time_entry(repo, task_id, now, stop_reason) do
    query = from(te in TimeEntry, where: te.task_id == ^task_id and is_nil(te.ended_at))

    case repo.one(query) do
      nil ->
        {:error, :no_open_time_entry}

      entry ->
        duration = DateTime.diff(now, entry.started_at, :second)

        entry
        |> TimeEntry.close_changeset(%{
          ended_at: now,
          stop_reason: stop_reason,
          duration_seconds: duration
        })
        |> repo.update()
    end
  end

  defp close_open_task_event(repo, task_id, resolution, now) do
    query = from(e in TaskEvent, where: e.task_id == ^task_id and is_nil(e.ended_at))

    case repo.one(query) do
      nil ->
        {:error, :no_open_task_event}

      event ->
        event
        |> TaskEvent.close_changeset(%{ended_at: now, resolution: resolution})
        |> repo.update()
    end
  end

  defp stop_reason_for(status) when status in [:blocked, :interrupted, :paused, :complete], do: status
  defp stop_reason_for(_status), do: :manual

  @doc """
  Total active (in-progress) seconds tracked for a task: closed time
  entries plus the live delta of a currently-open one, if any.
  """
  def total_active_seconds(task_id) do
    closed =
      Repo.aggregate(
        from(te in TimeEntry, where: te.task_id == ^task_id and not is_nil(te.duration_seconds)),
        :sum,
        :duration_seconds
      ) || 0

    open_seconds =
      case Repo.one(from(te in TimeEntry, where: te.task_id == ^task_id and is_nil(te.ended_at))) do
        nil -> 0
        entry -> DateTime.diff(DateTime.utc_now(), entry.started_at, :second)
      end

    closed + open_seconds
  end
end
