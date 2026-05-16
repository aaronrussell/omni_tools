defmodule Omni.Tools.WebSearch.Providers.Tavily do
  @moduledoc """
  Tavily Search provider for `Omni.Tools.WebSearch`.

  Uses the [Tavily Search API](https://tavily.com).

      # Uses TAVILY_API_KEY env var by default
      Omni.Tools.WebSearch.new(provider: Omni.Tools.WebSearch.Providers.Tavily)

      # Explicit API key
      Omni.Tools.WebSearch.new(
        provider: {Omni.Tools.WebSearch.Providers.Tavily, api_key: "..."}
      )

      # Custom env var
      Omni.Tools.WebSearch.new(
        provider: {Omni.Tools.WebSearch.Providers.Tavily, api_key: {:system, "MY_TAVILY_KEY"}}
      )

  ## API key resolution

  The `:api_key` option accepts a string or a `{:system, env_var}` tuple.
  The default is `{:system, "TAVILY_API_KEY"}`. Resolution order:

  1. Explicit `:api_key` in provider opts
  2. Application config: `config :omni_tools, Provider.Tavily, api_key: "..."`
  3. Module default: `{:system, "TAVILY_API_KEY"}`

  ## Options

  - `:api_key` — Tavily API key. A string or `{:system, env_var}` tuple.
    Default: `{:system, "TAVILY_API_KEY"}`.
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

  @defaults [api_key: {:system, "TAVILY_API_KEY"}]

  @impl true
  def search(query, opts) do
    opts = resolve_opts(opts)
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

  defp resolve_opts(opts) do
    @defaults
    |> Keyword.merge(Application.get_env(:omni_tools, __MODULE__, []))
    |> Keyword.merge(opts)
    |> resolve_api_key()
  end

  defp resolve_api_key(opts) do
    case Keyword.fetch!(opts, :api_key) do
      key when is_binary(key) ->
        opts

      {:system, env_var} ->
        case System.get_env(env_var) do
          nil -> raise ArgumentError, "environment variable #{env_var} is not set"
          key -> Keyword.put(opts, :api_key, key)
        end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
