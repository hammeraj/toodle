defmodule Toodle.Tasks.StatusMachine do
  @moduledoc """
  Pure rules for task status transitions. No side effects, no DB access —
  `Toodle.Tasks.change_status/3` is the only place transitions actually happen.
  """

  @type status :: :not_started | :in_progress | :paused | :blocked | :interrupted | :complete

  @transitions %{
    not_started: [:in_progress],
    in_progress: [:paused, :blocked, :interrupted, :complete, :not_started],
    paused: [:in_progress, :complete],
    blocked: [:in_progress, :complete],
    interrupted: [:in_progress, :complete],
    complete: [:in_progress]
  }

  @doc "Whether moving from `from` to `to` is a legal transition."
  @spec transition?(status, status) :: boolean
  def transition?(from, to), do: to in Map.fetch!(@transitions, from)

  @doc "Statuses reachable from the given status."
  @spec allowed_next(status) :: [status]
  def allowed_next(from), do: Map.fetch!(@transitions, from)

  @doc """
  Which side effects a `from -> to` transition triggers.

  Returns a list containing any of:
    * `:start_timer`       — open a new time entry
    * `:stop_timer`        — close the open time entry
    * `:open_task_event`   — open a new block/interrupt event (requires a reason)
    * `:close_task_event`  — close the open block/interrupt event
  """
  @spec side_effects(status, status) :: [atom]
  def side_effects(from, to) do
    []
    |> maybe_stop_timer(from, to)
    |> maybe_start_timer(from, to)
    |> maybe_open_task_event(from, to)
    |> maybe_close_task_event(from, to)
  end

  defp maybe_stop_timer(effects, :in_progress, to) when to != :in_progress,
    do: [:stop_timer | effects]

  defp maybe_stop_timer(effects, _from, _to), do: effects

  defp maybe_start_timer(effects, from, :in_progress) when from != :in_progress,
    do: [:start_timer | effects]

  defp maybe_start_timer(effects, _from, _to), do: effects

  defp maybe_open_task_event(effects, _from, to) when to in [:blocked, :interrupted],
    do: [:open_task_event | effects]

  defp maybe_open_task_event(effects, _from, _to), do: effects

  defp maybe_close_task_event(effects, from, _to) when from in [:blocked, :interrupted],
    do: [:close_task_event | effects]

  defp maybe_close_task_event(effects, _from, _to), do: effects
end
