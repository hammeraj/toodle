defmodule Toodle.Repo do
  use Ecto.Repo,
    otp_app: :toodle,
    adapter: Ecto.Adapters.SQLite3
end
