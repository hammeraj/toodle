defmodule Toodle.MCP.Tools.ListTasks do
  @moduledoc """
  List top-level tasks, optionally filtered by project and/or status.
  Status must be one of: not_started, in_progress, paused, blocked, interrupted, complete.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.Tasks
  alias Toodle.Tasks.Task
  alias Toodle.MCP.Tools.Support

  schema do
    field(:project_id, :string)
    field(:status, :string)
    field(:include_subtasks, :boolean, default: false)
  end

  @impl true
  def execute(params, frame) do
    with {:ok, status} <- parse_status(params[:status]) do
      opts =
        []
        |> maybe_put(:project_id, params[:project_id])
        |> maybe_put(:status, status)
        |> maybe_put(:top_level_only, !params[:include_subtasks])

      tasks = Enum.map(Tasks.list_tasks(opts), &Support.task_summary/1)
      {:reply, Response.tool() |> Response.json(tasks), frame}
    else
      {:error, message} -> {:reply, Response.tool() |> Response.error(message), frame}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_status(nil), do: {:ok, nil}

  defp parse_status(status) do
    case Enum.find(Task.statuses(), &(Atom.to_string(&1) == status)) do
      nil -> {:error, "Unknown status #{inspect(status)} — must be one of #{inspect(Task.statuses())}"}
      atom -> {:ok, atom}
    end
  end
end
