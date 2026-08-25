defmodule Toodle.Updater.Client do
  @moduledoc """
  GitHub releases API client for `Toodle.Updater`. Reads the rolling
  "latest" release CI publishes (see .github/workflows/desktop-build.yml)
  and the commit SHA embedded in its body -- there's no version-numbered
  tag to compare against, since the tag is reused on every build.
  """

  @repo "hammeraj/toodle"
  @api_url "https://api.github.com/repos/#{@repo}/releases/tags/latest"
  @sha_regex ~r/Commit:\s*([0-9a-f]{7,40})/i

  @doc "Fetches the latest release's commit SHA and asset list."
  def latest_release do
    req = Req.new(receive_timeout: 10_000)

    case Req.get(req, url: @api_url, headers: [{"accept", "application/vnd.github+json"}]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case extract_sha(body["body"]) do
          {:ok, sha} -> {:ok, %{sha: sha, assets: body["assets"] || []}}
          :error -> {:error, "Release body doesn't contain a commit SHA"}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, "GitHub API returned HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp extract_sha(nil), do: :error

  defp extract_sha(body) do
    case Regex.run(@sha_regex, body) do
      [_, sha] -> {:ok, sha}
      _ -> :error
    end
  end

  @doc "Picks the release asset matching this platform's installer, or nil if none matches."
  def asset_for_platform(assets) do
    case platform_suffix() do
      nil -> nil
      suffix -> Enum.find(assets, &String.ends_with?(&1["name"], suffix))
    end
  end

  defp platform_suffix do
    case :os.type() do
      {:win32, _} -> ".exe"
      {:unix, :darwin} -> ".dmg"
      _ -> nil
    end
  end

  @doc "Downloads an asset to a temp file. Returns {:ok, path}."
  def download(asset) do
    path = Path.join(System.tmp_dir!(), asset["name"])
    req = Req.new(receive_timeout: 120_000)

    case Req.get(req, url: asset["browser_download_url"], into: File.stream!(path)) do
      {:ok, %Req.Response{status: 200}} -> {:ok, path}
      {:ok, %Req.Response{status: status}} -> {:error, "Download failed with HTTP #{status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end
end
