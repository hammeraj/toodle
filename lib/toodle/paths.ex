defmodule Toodle.Paths do
  @moduledoc """
  Resolves where the packaged desktop app keeps its SQLite database, outside
  the release bundle so it survives upgrades: macOS Application Support,
  Windows AppData/Roaming, `~/.config` elsewhere.
  """

  @doc "Toodle's persistent app-data directory (created if missing)."
  def data_dir do
    dir =
      case :os.type() do
        {:unix, :darwin} -> Path.join([System.user_home!(), "Library", "Application Support", "Toodle"])
        {:win32, _} -> Path.join(windows_app_data(), "Toodle")
        _ -> Path.join([System.user_home!(), ".config", "toodle"])
      end

    File.mkdir_p!(dir)
    dir
  end

  def database_path, do: Path.join(data_dir(), "toodle.db")

  @doc """
  A `secret_key_base` persisted in the app-data dir, generated once on first
  run. No ops team hands this to a single-user local desktop app, so it's
  self-managed rather than required via env var.
  """
  def secret_key_base do
    path = Path.join(data_dir(), "secret_key_base")

    case File.read(path) do
      {:ok, key} ->
        key

      {:error, :enoent} ->
        key = :crypto.strong_rand_bytes(48) |> Base.encode64()
        File.write!(path, key)
        key
    end
  end

  defp windows_app_data do
    System.get_env("APPDATA") || Path.join(System.user_home!(), "AppData/Roaming")
  end
end
