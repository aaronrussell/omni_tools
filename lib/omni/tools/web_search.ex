defmodule Omni.Tools.WebSearch do
  @moduledoc """
  An `Omni.Tool` for searching the web via configurable providers.

  Executes a web search query and returns results formatted for LLM
  consumption. The search backend is pluggable — any module implementing
  `Omni.Tools.WebSearch.Provider` can be used.

      tool = Omni.Tools.WebSearch.new(
        provider: {MyApp.BraveProvider, api_key: "..."}
      )

  ## Providers

  A provider is a module implementing the `Omni.Tools.WebSearch.Provider`
  behaviour. It receives the query and options (including `:num_results`
  and `:recency` when supplied by the model) and returns structured
  results.

  See `Omni.Tools.WebSearch.Provider` for details on implementing your
  own provider.

  ## Options

  - `:provider` — (required) a provider module or `{module, opts}` tuple.
  - `:num_results` — default number of results to request. Default: `5`.
  """

  use Omni.Tool,
    name: "web_search",
    description: """
    Search the web for information. Returns a numbered list of results, \
    each with title, URL, and a short snippet.
    """

  alias Omni.Tools.WebSearch.Provider

  @defaults [
    num_results: 5
  ]

  @impl Omni.Tool
  def init(opts) do
    opts =
      @defaults
      |> Keyword.merge(Application.get_env(:omni_tools, __MODULE__, []))
      |> Keyword.merge(opts || [])

    provider =
      case Keyword.fetch(opts, :provider) do
        {:ok, provider} -> Provider.validate!(provider)
        :error -> raise ArgumentError, ":provider is required"
      end

    [
      provider: provider,
      num_results: Keyword.fetch!(opts, :num_results)
    ]
  end

  @impl Omni.Tool
  def schema() do
    import Omni.Schema

    object(
      %{
        query: string(description: "The search query"),
        num_results: integer(description: "Number of results to return", default: 5),
        recency:
          enum(["day", "week", "month", "year"],
            description: "Filter results by recency"
          )
      },
      required: [:query]
    )
  end

  @impl Omni.Tool
  def call(input, state) do
    query = fetch_query!(input)
    {mod, provider_opts} = Keyword.fetch!(state, :provider)

    search_opts =
      provider_opts
      |> Keyword.put(:num_results, input[:num_results] || Keyword.fetch!(state, :num_results))
      |> maybe_put(:recency, parse_recency(input[:recency]))

    case mod.search(query, search_opts) do
      {:ok, []} -> "No results found."
      {:ok, results} -> format_results(results)
      {:error, reason} -> raise "search failed: #{format_error(reason)}"
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp fetch_query!(%{query: query}) when is_binary(query) and query != "", do: query
  defp fetch_query!(_input), do: raise("query is required and must be a non-empty string")

  defp parse_recency("day"), do: :day
  defp parse_recency("week"), do: :week
  defp parse_recency("month"), do: :month
  defp parse_recency("year"), do: :year
  defp parse_recency(nil), do: nil
  defp parse_recency(_other), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp format_results(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {result, idx} ->
      "#{idx}. #{result.title}\n   #{result.url}\n   #{result.snippet}"
    end)
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error(%{message: message}), do: message
  defp format_error(reason), do: inspect(reason)
end
