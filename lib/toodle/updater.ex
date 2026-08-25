defmodule Toodle.Updater do
  @moduledoc """
  Checks CI's rolling "latest" GitHub release for a build newer than the
  one currently running, and can download + apply it in place over the
  installed app. See `Toodle.Updater.Client` for why "newer" means a
  different commit SHA rather than a version comparison, and
  `Toodle.Updater.Applier` for how the in-place replace actually works
  (and its Windows-verified/macOS-unverified status).
  """

  alias Toodle.Updater.{Applier, Client}

  @doc """
  This build's own commit SHA, embedded at release build time
  (see stamp_build_sha/1 in mix.exs). `nil` outside a packaged desktop
  release -- dev/test builds were never stamped, so there's nothing
  meaningful to compare.
  """
  def local_sha do
    case :code.priv_dir(:toodle) do
      {:error, :bad_name} ->
        nil

      priv_dir ->
        path = Path.join(priv_dir, "build_sha.txt")

        case File.read(path) do
          {:ok, sha} -> String.trim(sha)
          {:error, _} -> nil
        end
    end
  end

  @doc """
  Checks for an update.

    * `{:ok, :up_to_date}`
    * `{:ok, {:update_available, %{sha: sha, asset: asset}}}`
    * `{:error, reason}`
  """
  def check do
    case local_sha() do
      nil ->
        {:error, "This isn't a packaged build — no build identity to compare against"}

      local ->
        with {:ok, %{sha: remote_sha, assets: assets}} <- Client.latest_release() do
          if remote_sha == local do
            {:ok, :up_to_date}
          else
            case Client.asset_for_platform(assets) do
              nil -> {:error, "No installer for this platform in the latest release"}
              asset -> {:ok, {:update_available, %{sha: remote_sha, asset: asset}}}
            end
          end
        end
    end
  end

  @doc """
  Downloads `asset` (from a `{:update_available, ...}` result) and applies
  it. On success this app quits partway through to let the new version
  take over — callers shouldn't expect this function's caller process to
  still be running for long afterward.
  """
  def download_and_apply(asset) do
    with {:ok, path} <- Client.download(asset) do
      Applier.apply(path)
    end
  end
end
