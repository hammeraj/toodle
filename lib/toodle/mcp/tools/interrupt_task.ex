defmodule Toodle.MCP.Tools.InterruptTask do
  @moduledoc """
  Mark a task interrupted and stop its timer. Requires at least one of
  blocking_task_id (the task causing the interrupt) or reason (free text).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Toodle.MCP.Tools.Support

  schema do
    field(:task_id, :string, required: true)
    field(:blocking_task_id, :string, description: "The id of the task causing the interrupt")
    field(:reason, :string, description: "Free-text note on what interrupted this task")
  end

  @impl true
  def execute(%{task_id: task_id} = params, frame) do
    opts =
      []
      |> maybe_put(:blocking_task_id, params[:blocking_task_id])
      |> maybe_put(:reason, params[:reason])

    reply(Support.transition(task_id, :interrupted, opts), frame)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp reply({:ok, summary}, frame),
    do: {:reply, Response.tool() |> Response.json(summary), frame}

  defp reply({:error, message}, frame),
    do: {:reply, Response.tool() |> Response.error(message), frame}
end
