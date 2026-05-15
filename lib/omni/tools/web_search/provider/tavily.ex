defmodule Omni.Tools.WebSearch.Provider.Tavily do
  @moduledoc """
  Tavily Search provider for `Omni.Tools.WebSearch`.

  Uses the [Tavily Search API](https://tavily.com).

      Omni.Tools.WebSearch.new(
        provider: {Omni.Tools.WebSearch.Provider.Tavily, api_key: "..."}
      )

  ## Options

  - `:api_key` — (required) Tavily API key.
  - `:req` — optional `Req.Request` struct for transport customisation.

  Any additional options are passed through in the JSON request body
  (e.g. `topic: "news"`, `search_depth: "advanced"`,
  `include_domains: ["example.com"]`). See the Tavily API docs for
  available parameters.
  """

  @behaviour Omni.Tools.WebSearch.Provider

  @base_url "https://api.tavily.com/search"

  @recency_map %{
    day: "day",
    week: "week",
    month: "month",
    year: "year"
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
      |> Map.put(:query, query)
      |> Map.put(:max_results, num_results)
      |> maybe_put(:time_range, Map.get(@recency_map, recency))

    req =
      Req.merge(req,
        url: @base_url,
        headers: [{"authorization", "Bearer #{api_key}"}],
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

  defp extract_results(%{"results" => results}) do
    Enum.map(results, fn result ->
      %{
        url: result["url"],
        title: result["title"],
        snippet: result["content"] || ""
      }
    end)
  end

  defp extract_results(_body), do: []

  defp error_message(status, %{"detail" => %{"error" => error}}),
    do: "Tavily API #{status}: #{error}"

  defp error_message(status, %{"detail" => detail}) when is_binary(detail),
    do: "Tavily API #{status}: #{detail}"

  defp error_message(status, %{"message" => message}),
    do: "Tavily API #{status}: #{message}"

  defp error_message(status, body) when is_binary(body),
    do: "Tavily API #{status}: #{body}"

  defp error_message(status, _body), do: "Tavily API #{status}"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
