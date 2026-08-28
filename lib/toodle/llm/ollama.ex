defmodule Toodle.Llm.Ollama do
  @moduledoc """
  Minimal client for a local Ollama server (https://ollama.com) — runs a
  small open-source model entirely on-device, no cloud API, no account.
  Ollama itself is optional infrastructure the user installs separately;
  every caller must tolerate `{:error, _}` (server not running, model not
  pulled, timeout, ...) rather than treat it as guaranteed available.
  """

  @default_host "http://localhost:11434"
  @default_model "qwen2.5:1.5b"

  require Logger

  alias Toodle.Llm.OllamaServer

  def default_model, do: @default_model

  @doc """
  The Ollama server to talk to: an explicit config override, then the
  bundled server this build ships (see `OllamaServer`), then the standard
  port a user's own separately-installed Ollama would be listening on.
  """
  def host do
    config()[:host] || (OllamaServer.bundled?() && OllamaServer.host()) || @default_host
  end

  @doc """
  Asks `model` to respond to `prompt` with a JSON object, and decodes it.
  Returns `{:ok, decoded_map}` or `{:error, reason}`.
  """
  def generate_json(prompt, model \\ @default_model) do
    request()
    |> Req.post(
      url: "/api/generate",
      json: %{model: model, prompt: prompt, stream: false, format: "json"}
    )
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"response" => response}}}
      when is_binary(response) ->
        case Jason.decode(response) do
          {:ok, decoded} ->
            {:ok, decoded}

          {:error, reason} ->
            log_error("returned non-JSON response: #{inspect(response)}")
            {:error, reason}
        end

      {:ok, %Req.Response{status: 200, body: body}} ->
        log_error("response missing \"response\" field: #{inspect(body)}")
        {:error, "Ollama response missing \"response\" field: #{inspect(body)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        message = http_error_message(status, body)
        log_error(message)
        {:error, message}

      {:error, exception} ->
        log_error(Exception.message(exception))
        {:error, Exception.message(exception)}
    end
  end

  @doc """
  Pulls `model` into whichever server `host/0` resolves to, if it isn't
  already there — a fast no-op when it is, since Ollama checks its own
  content-addressed blob store before transferring anything, and that's
  exactly how a real model version bump gets picked up without a full
  redownload.

  Meant for the bundled runtime specifically (see `OllamaServer` for why
  it owns its models directory) — callers should check
  `OllamaServer.bundled?/0` first, same as `Toodle.Inbox.Cleanup`'s
  Settings-driven callers do, rather than reaching into a user's own
  separately-installed Ollama uninvited.

  Downloading a model for real can take a while, so callers that don't
  want to block should wrap this in a `Task`.
  """
  def ensure_model(model \\ @default_model) do
    request(receive_timeout: :infinity)
    |> Req.post(url: "/api/pull", json: %{model: model, stream: false})
    |> case do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        message = http_error_message(status, body)
        log_error("pull of #{model} #{message}")
        {:error, message}

      {:error, exception} ->
        log_error("pull of #{model} failed: #{Exception.message(exception)}")
        {:error, Exception.message(exception)}
    end
  end

  @doc "Whether `model` is already pulled locally, for whichever server `host/0` resolves to."
  def model_present?(model) do
    case list_models() do
      {:ok, names} -> Enum.any?(names, &matches_model?(&1, model))
      {:error, _reason} -> false
    end
  end

  defp list_models do
    request()
    |> Req.get(url: "/api/tags")
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"models" => models}}} when is_list(models) ->
        {:ok, Enum.map(models, & &1["name"])}

      {:ok, %Req.Response{status: 200, body: body}} ->
        log_error("response missing \"models\" field: #{inspect(body)}")
        {:error, "Ollama response missing \"models\" field: #{inspect(body)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        message = http_error_message(status, body)
        log_error(message)
        {:error, message}

      {:error, exception} ->
        log_error(Exception.message(exception))
        {:error, Exception.message(exception)}
    end
  end

  # A pulled model's tag defaults to ":latest" when the caller's model name
  # didn't specify one, same as `ollama pull` itself.
  defp matches_model?(name, model) do
    name == model or (not String.contains?(model, ":") and name == "#{model}:latest")
  end

  # retry: false -- a local single-user Ollama is either up or it isn't;
  # Req's default retry-with-backoff on a GET (like list_models/0's) turns
  # one unreachable-server call into several seconds of retries instead of
  # the instant fallback every caller here is written to expect.
  defp request(opts \\ []) do
    [base_url: host(), receive_timeout: 8_000, retry: false]
    |> Keyword.merge(opts)
    |> Req.new()
    |> maybe_plug()
  end

  defp maybe_plug(req) do
    case config()[:plug] do
      nil -> req
      plug -> Req.merge(req, plug: plug)
    end
  end

  defp config, do: Application.get_env(:toodle, __MODULE__, [])

  # Ollama's non-200 responses are almost always {"error": "<what actually
  # went wrong>"} -- a crashed model runner, an out-of-memory kill, a bad
  # request -- which is the one piece of information that actually explains
  # a failure. A bare status code alone ("HTTP 500") tells a caller nothing
  # they can act on.
  defp http_error_message(status, %{"error" => error}) when is_binary(error),
    do: "Ollama returned HTTP #{status}: #{error}"

  defp http_error_message(status, _body), do: "Ollama returned HTTP #{status}"

  # Every caller here treats an Ollama failure as best-effort (fall back and
  # move on), so without this the only trace of a broken local model setup
  # would be silence -- a title that just never changes, with no way to tell
  # why.
  defp log_error(message), do: Logger.warning("Ollama: #{message}")
end
