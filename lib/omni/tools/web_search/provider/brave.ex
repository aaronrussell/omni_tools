defmodule Omni.Tools.WebSearch.Provider.Brave do
  @moduledoc """
  Brave Search provider for `Omni.Tools.WebSearch`.

  Uses the [Brave Web Search API](https://api.search.brave.com).

      # Uses BRAVE_API_KEY env var by default
      Omni.Tools.WebSearch.new(provider: Omni.Tools.WebSearch.Provider.Brave)

      # Explicit API key
      Omni.Tools.WebSearch.new(
        provider: {Omni.Tools.WebSearch.Provider.Brave, api_key: "..."}
      )

      # Custom env var
      Omni.Tools.WebSearch.new(
        provider: {Omni.Tools.WebSearch.Provider.Brave, api_key: {:system, "MY_BRAVE_KEY"}}
      )

  ## API key resolution

  The `:api_key` option accepts a string or a `{:system, env_var}` tuple.
  The default is `{:system, "BRAVE_API_KEY"}`. Resolution order:

  1. Explicit `:api_key` in provider opts
  2. Application config: `config :omni_tools, Provider.Brave, api_key: "..."`
  3. Module default: `{:system, "BRAVE_API_KEY"}`

  ## Options

  - `:api_key` — Brave Search API subscription token. A string or
    `{:system, env_var}` tuple. Default: `{:system, "BRAVE_API_KEY"}`.
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

  @defaults [api_key: {:system, "BRAVE_API_KEY"}]

  @impl true
  def search(query, opts) do
    opts = resolve_opts(opts)
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

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
