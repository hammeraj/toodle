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
        Jason.decode(response)

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:error, "Ollama response missing \"response\" field: #{inspect(body)}"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Ollama returned HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp request do
    [base_url: host(), receive_timeout: 8_000]
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
end
