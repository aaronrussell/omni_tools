defmodule Omni.Tools.WebSearch.Provider do
  @moduledoc """
  Behaviour for web search providers.

  A provider implements a single callback — `c:search/2` — that
  executes a web search query and returns a list of results.

  ## Example

      defmodule MyApp.BraveProvider do
        @behaviour Omni.Tools.WebSearch.Provider

        @impl true
        def search(query, opts) do
          api_key = Keyword.fetch!(opts, :api_key)
          # ... HTTP request to Brave Search API ...
          {:ok, [%{url: "...", title: "...", snippet: "..."}]}
        end
      end

  ## Usage

  Pass your provider to `Omni.Tools.WebSearch.new/1`:

      Omni.Tools.WebSearch.new(
        provider: {MyApp.BraveProvider, api_key: "..."}
      )
  """

  @typedoc "A single search result."
  @type result :: %{url: String.t(), title: String.t(), snippet: String.t()}

  @doc """
  Executes a web search query.

  Receives the query string and a keyword list of options (provider
  config merged with runtime parameters like `:num_results` and
  `:recency`). Returns `{:ok, results}` on success or
  `{:error, reason}` on failure.
  """
  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, [result()]} | {:error, term()}

  @doc """
  Validates a provider spec as a `{module, opts}` tuple.

  Accepts a bare module (treated as `{module, []}`) or a
  `{module, opts}` tuple. Raises `ArgumentError` if the module
  cannot be loaded or does not export `search/2`.

      Provider.validate!({MyProvider, api_key: "..."})
      #=> {MyProvider, [api_key: "..."]}

      Provider.validate!(MyProvider)
      #=> {MyProvider, []}
  """
  @spec validate!(module() | {module(), keyword()}) :: {module(), keyword()}
  def validate!({mod, opts}) when is_atom(mod) and is_list(opts) do
    validate_module!(mod)
    {mod, opts}
  end

  def validate!(mod) when is_atom(mod) do
    validate_module!(mod)
    {mod, []}
  end

  def validate!(other) do
    raise ArgumentError,
          "expected a provider module or {module, opts} tuple, got: #{inspect(other)}"
  end

  defp validate_module!(mod) do
    case Code.ensure_loaded(mod) do
      {:module, ^mod} ->
        unless function_exported?(mod, :search, 2) do
          raise ArgumentError,
                "provider module #{inspect(mod)} must implement search/2"
        end

      {:error, reason} ->
        raise ArgumentError,
              "could not load provider module #{inspect(mod)}: #{reason}"
    end
  end
end
