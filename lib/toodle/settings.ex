defmodule Toodle.Settings do
  @moduledoc "The Settings context — simple key/value app configuration."

  alias Toodle.Repo
  alias Toodle.Settings.Setting

  @doc "Gets a setting's value, or `default` if unset."
  def get(key, default \\ nil) when is_binary(key) do
    case Repo.get(Setting, key) do
      nil -> default
      %Setting{value: value} -> value
    end
  end

  @doc "Sets a setting's value, creating or updating it."
  def put(key, value) when is_binary(key) do
    %Setting{key: key}
    |> Setting.changeset(%{key: key, value: value})
    |> Repo.insert(
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )
  end
end
