defmodule Toodle.MCP.Tools.CompleteTask do
  @moduledoc "Mark a task complete and stop its timer."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.MCP.Tools.Support

  schema do
    field(:task_id, :string, required: true)
  end

  @impl true
  def execute(%{task_id: task_id}, frame) do
    reply(Support.transition(task_id, :complete), frame)
  end

  defp reply({:ok, summary}, frame),
    do: {:reply, Response.tool() |> Response.json(summary), frame}

  defp reply({:error, message}, frame),
    do: {:reply, Response.tool() |> Response.error(message), frame}
end
