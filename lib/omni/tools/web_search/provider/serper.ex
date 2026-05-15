defmodule Omni.Tools.WebSearch.Provider.Serper do
  @moduledoc """
  Serper provider for `Omni.Tools.WebSearch`.

  Uses the [Serper Google Search API](https://serper.dev).

      Omni.Tools.WebSearch.new(
        provider: {Omni.Tools.WebSearch.Provider.Serper, api_key: "..."}
      )

  ## Options

  - `:api_key` — (required) Serper API key.
  - `:req` — optional `Req.Request` struct for transport customisation.

  Any additional options are passed through in the JSON request body
  (e.g. `gl: "uk"`, `hl: "en"`, `location: "London"`). See the Serper
  API docs for available parameters.
  """

  @behaviour Omni.Tools.WebSearch.Provider

  @base_url "https://google.serper.dev/search"

  @recency_map %{
    day: "qdr:d",
    week: "qdr:w",
    month: "qdr:m",
    year: "qdr:y"
  }

  @impl true
  def search(query, opts) do
    {api_key, opts} = Keyword.pop!(opts, :api_key)
    {req, opts} = Keyword.pop(opts, :req, Req.new())
    {num_results, opts} = Keyword.pop(opts, :num_results, 5)
    {recency, opts} = Keyword.pop(opts, :recency)

    body =
      opts
      |> Map.new()
      |> Map.put(:q, query)
      |> Map.put(:num, num_results)
      |> maybe_put(:tbs, Map.get(@recency_map, recency))

    req =
      Req.merge(req,
        url: @base_url,
        headers: [{"x-api-key", api_key}],
        json: body
      )

    case Req.post(req) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, extract_results(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, error_message(status, body)}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp extract_results(%{"organic" => results}) do
    Enum.map(results, fn result ->
      %{
        url: result["link"],
        title: result["title"],
        snippet: result["snippet"] || ""
      }
    end)
  end

  defp extract_results(_body), do: []

  defp error_message(status, %{"message" => message}), do: "Serper API #{status}: #{message}"
  defp error_message(status, body) when is_binary(body), do: "Serper API #{status}: #{body}"
  defp error_message(status, _body), do: "Serper API #{status}"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
