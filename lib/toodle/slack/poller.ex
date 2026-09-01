defmodule Toodle.Slack.Poller do
  @moduledoc """
  Polls Slack for mentions on an interval, when configured. Always runs as
  part of the GUI app's supervision tree (see `Toodle.Application`) and
  checks `Toodle.Slack.configured?/0` on each tick, rather than being
  conditionally started — settings can change at runtime via the UI. The
  interval itself is also read fresh from `Toodle.Slack.poll_interval_seconds/0`
  on every tick, so changing it in Settings takes effect on the next poll
  rather than needing a restart.
  """

  use GenServer
  require Logger

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
        {:ok, %{reaction_error: reason} = result} when not is_nil(reason) ->
          Logger.warning("Slack reaction poll failed: #{reason}")
          Logger.debug("Slack poll: #{inspect(result)}")

        {:ok, result} ->
          Logger.debug("Slack poll: #{inspect(result)}")

        {:error, reason} ->
          Logger.warning("Slack poll failed: #{inspect(reason)}")
      end
    end

    schedule_tick(:timer.seconds(Toodle.Slack.poll_interval_seconds()))
    {:noreply, state}
  end

  defp schedule_tick(delay), do: Process.send_after(self(), :tick, delay)
end
