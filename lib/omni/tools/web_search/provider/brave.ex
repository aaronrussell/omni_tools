defmodule Omni.Tools.WebSearch.Provider.Brave do
  @moduledoc """
  Brave Search provider for `Omni.Tools.WebSearch`.

  Uses the [Brave Web Search API](https://api.search.brave.com).

      Omni.Tools.WebSearch.new(
        provider: {Omni.Tools.WebSearch.Provider.Brave, api_key: "..."}
      )

  ## Options

  - `:api_key` — (required) Brave Search API subscription token.
  - `:req` — optional `Req.Request` struct for transport customisation.

  Any additional options are passed through as query parameters to the
  Brave API (e.g. `country: "GB"`, `safesearch: "strict"`,
  `search_lang: "en"`). See the Brave API docs for available parameters.
  """

  @behaviour Omni.Tools.WebSearch.Provider

  @base_url "https://api.search.brave.com/res/v1/web/search"

  @recency_map %{
    day: "pd",
    week: "pw",
    month: "pm",
    year: "py"
  }

  @impl true
  def search(query, opts) do
    {api_key, opts} = Keyword.pop!(opts, :api_key)
    {req, opts} = Keyword.pop(opts, :req, Req.new())
    {num_results, opts} = Keyword.pop(opts, :num_results, 5)
    {recency, opts} = Keyword.pop(opts, :recency)

    params =
      opts
      |> Keyword.put(:q, query)
      |> Keyword.put(:count, num_results)
      |> maybe_put(:freshness, Map.get(@recency_map, recency))

    req =
      Req.merge(req,
        url: @base_url,
        headers: [{"x-subscription-token", api_key}, {"accept", "application/json"}],
        params: params
      )

    case Req.get(req) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, extract_results(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, error_message(status, body)}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp extract_results(%{"web" => %{"results" => results}}) do
    Enum.map(results, fn result ->
      %{
        url: result["url"],
        title: result["title"],
        snippet: result["description"] || ""
      }
    end)
  end

  defp extract_results(_body), do: []

  defp error_message(status, %{"error" => %{"detail" => detail}}),
    do: "Brave API #{status}: #{detail}"

  defp error_message(status, %{"message" => message}),
    do: "Brave API #{status}: #{message}"

  defp error_message(status, body) when is_binary(body),
    do: "Brave API #{status}: #{body}"

  defp error_message(status, _body), do: "Brave API #{status}"

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
