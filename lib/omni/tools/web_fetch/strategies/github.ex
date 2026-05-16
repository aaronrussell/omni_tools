defmodule Omni.Tools.WebFetch.Strategies.GitHub do
  @moduledoc false

  @behaviour Omni.Tools.WebFetch.Strategy

  @impl true
  def match?(uri, _opts) do
    uri.host == "github.com" and blob_path?(uri.path)
  end

  @impl true
  def request(req, _opts) do
    uri = req.url
    raw_url = to_raw_url(uri)
    Req.merge(req, url: raw_url)
  end

  @impl true
  def extract(response, _opts) do
    if response.body in [nil, ""] do
      "(empty response)"
    else
      response.body
    end
  end

  defp blob_path?(nil), do: false

  defp blob_path?(path) do
    case String.split(path, "/", trim: true) do
      [_owner, _repo, "blob" | _rest] -> true
      _ -> false
    end
  end

  defp to_raw_url(uri) do
    [owner, repo, "blob" | ref_and_path] = String.split(uri.path, "/", trim: true)
    raw_path = "/" <> Enum.join([owner, repo | ref_and_path], "/")

    URI.to_string(%URI{
      scheme: "https",
      host: "raw.githubusercontent.com",
      path: raw_path
    })
  end
end
