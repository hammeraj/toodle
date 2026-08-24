defmodule Toodle.Settings.Setting do
  @moduledoc """
  Simple key/value app configuration (Linear API key, MCP enabled toggle, ...).

  Keyed by its string `key` rather than a binary_id — settings are
  singleton config, not syncable domain records, so a UUID surrogate key
  would add nothing.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime]

  schema "settings" do
    field :value, :string

    timestamps()
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
  end
end
