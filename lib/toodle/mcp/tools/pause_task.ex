defmodule Toodle.MCP.Tools.PauseTask do
  @moduledoc "Pause an in_progress task, stopping its timer. No reason needed — use block_task/interrupt_task for that."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.MCP.Tools.Support

  schema do
    field(:task_id, :string, required: true)
  end

  @impl true
  def execute(%{task_id: task_id}, frame) do
    reply(Support.transition(task_id, :paused), frame)
  end

  defp reply({:ok, summary}, frame),
    do: {:reply, Response.tool() |> Response.json(summary), frame}

  defp reply({:error, message}, frame),
    do: {:reply, Response.tool() |> Response.error(message), frame}
end
