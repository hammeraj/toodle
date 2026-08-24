defmodule Toodle.Slack.Poller do
  @moduledoc """
  Polls Slack for mentions on an interval, when configured. Always runs as
  part of the GUI app's supervision tree (see `Toodle.Application`) and
  checks `Toodle.Slack.configured?/0` on each tick, rather than being
  conditionally started — settings can change at runtime via the UI.
  """

  use GenServer
  require Logger

  @interval :timer.seconds(60)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule_tick(1_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    if Toodle.Slack.configured?() do
      case Toodle.Slack.poll() do
        {:ok, result} -> Logger.debug("Slack poll: #{inspect(result)}")
        {:error, reason} -> Logger.warning("Slack poll failed: #{inspect(reason)}")
      end
    end

    schedule_tick(@interval)
    {:noreply, state}
  end

  defp schedule_tick(delay), do: Process.send_after(self(), :tick, delay)
end
