defmodule Toodle.Schema do
  @moduledoc """
  Base module for Toodle's Ecto schemas.

  Uses binary IDs (UUIDs) instead of autoincrement integers everywhere so
  records have globally-unique identity from the start — this keeps the
  door open for multi-instance sync later without a primary-key migration.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]

      import Ecto.Changeset
    end
  end
end
