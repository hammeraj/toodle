defmodule Toodle.MCP.Tools.StartTask do
  @moduledoc """
  Move a task to in_progress and start its timer. Works whether the task is
  currently not_started, paused, blocked, interrupted, or complete (reopens it).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.MCP.Tools.Support

  schema do
    field(:task_id, :string, required: true)
  end

  @impl true
  def execute(%{task_id: task_id}, frame) do
    reply(Support.transition(task_id, :in_progress), frame)
  end

  defp reply({:ok, summary}, frame), do: {:reply, Response.tool() |> Response.json(summary), frame}
  defp reply({:error, message}, frame), do: {:reply, Response.tool() |> Response.error(message), frame}
end
