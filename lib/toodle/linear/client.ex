defmodule Toodle.Linear.Client do
  @moduledoc """
  Minimal read-only Linear GraphQL client — fetches a single issue's
  title/state/assignee by its identifier (e.g. "ENG-123") or internal UUID.
  No OAuth, no webhooks, no write-back — see `Toodle.Linear`.
  """

  @endpoint "https://api.linear.app/graphql"

  @query """
  query Issue($id: String!) {
    issue(id: $id) {
      id
      identifier
      title
      url
      state { name }
      assignee { name }
    }
  }
  """

  @doc """
  Fetches an issue by identifier or UUID, given a personal Linear API key.
  Returns `{:ok, %{id:, identifier:, title:, url:, state:, assignee:}}` or `{:error, reason}`.
  """
  def fetch_issue(identifier, api_key) when is_binary(identifier) and is_binary(api_key) do
    req = Req.new(receive_timeout: 10_000)

    case Req.post(req,
           url: @endpoint,
           json: %{query: @query, variables: %{id: identifier}},
           headers: [{"authorization", api_key}]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"issue" => nil}}}} ->
        {:error, "No Linear issue found with that identifier"}

      {:ok, %Req.Response{status: 200, body: %{"data" => %{"issue" => issue}}}} ->
        {:ok, normalize(issue)}

      {:ok, %Req.Response{status: 200, body: %{"errors" => errors}}} ->
        {:error, Enum.map_join(errors, "; ", & &1["message"])}

      {:ok, %Req.Response{status: 401}} ->
        {:error, "Linear rejected the API key"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Linear API returned HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp normalize(issue) do
    %{
      id: issue["id"],
      identifier: issue["identifier"],
      title: issue["title"],
      url: issue["url"],
      state: get_in(issue, ["state", "name"]),
      assignee: get_in(issue, ["assignee", "name"])
    }
  end
end
