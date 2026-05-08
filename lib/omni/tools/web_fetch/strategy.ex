defmodule Omni.Tools.WebFetch.Strategy do
  @moduledoc """
  Behaviour for URL-specific content extraction strategies.

  A strategy controls how a URL is fetched and how the response is
  converted to text for LLM consumption. Strategies are matched against
  URLs in order — the first strategy whose `c:match?/2` returns `true`
  handles the request.

  ## Callbacks

    * `c:match?/2` (required) — returns `true` if this strategy handles
      the given URI.
    * `c:request/2` (optional) — modifies the `Req.Request` before
      execution (URL rewriting, custom headers, etc.).
    * `c:extract/2` (required) — converts the `Req.Response` into a
      content string.

  ## Example

      defmodule MyApp.WikiStrategy do
        @behaviour Omni.Tools.WebFetch.Strategy

        @impl true
        def match?(uri, _opts), do: uri.host == "en.wikipedia.org"

        @impl true
        def request(req, _opts) do
          # Use the mobile API for cleaner content
          Req.merge(req, headers: [{"accept", "text/html"}])
        end

        @impl true
        def extract(response, _opts) do
          Html2Markdown.convert(response.body)
        end
      end

  ## Usage

  Pass strategies to `Omni.Tools.WebFetch.new/1`:

      Omni.Tools.WebFetch.new(
        strategies: [
          {MyApp.WikiStrategy, []},
          MyApp.AnotherStrategy
        ]
      )
  """

  @doc "Returns `true` if this strategy handles the given URI."
  @callback match?(URI.t(), opts :: keyword()) :: boolean()

  @doc "Modifies the `Req.Request` before execution."
  @callback request(Req.Request.t(), opts :: keyword()) :: Req.Request.t()

  @doc "Extracts content from the response as a string."
  @callback extract(Req.Response.t(), opts :: keyword()) :: String.t()

  @optional_callbacks [request: 2]

  @doc """
  Normalizes a list of strategy specs into `{module, opts}` tuples.

  Accepts bare modules or `{module, opts}` tuples. Validates that each
  module implements the required callbacks. Raises `ArgumentError` on
  invalid input.

      Strategy.resolve([MyStrategy, {OtherStrategy, key: "val"}])
      #=> [{MyStrategy, []}, {OtherStrategy, [key: "val"]}]
  """
  @spec resolve([module() | {module(), keyword()}]) :: [{module(), keyword()}]
  def resolve(strategies) do
    Enum.map(strategies, fn
      {mod, opts} when is_atom(mod) and is_list(opts) ->
        validate_module!(mod)
        {mod, opts}

      mod when is_atom(mod) ->
        validate_module!(mod)
        {mod, []}

      other ->
        raise ArgumentError,
              "expected a strategy module or {module, opts} tuple, got: #{inspect(other)}"
    end)
  end

  @doc """
  Finds the first strategy matching the given URI.

  Returns `{module, opts}` for the first strategy whose `match?/2`
  returns `true`, or `nil` if none match.
  """
  @spec find([{module(), keyword()}], URI.t()) :: {module(), keyword()} | nil
  def find(strategies, uri) do
    Enum.find(strategies, fn {mod, opts} -> mod.match?(uri, opts) end)
  end

  defp validate_module!(mod) do
    case Code.ensure_loaded(mod) do
      {:module, ^mod} ->
        unless function_exported?(mod, :match?, 2) and function_exported?(mod, :extract, 2) do
          raise ArgumentError,
                "strategy module #{inspect(mod)} must implement match?/2 and extract/2"
        end

      {:error, reason} ->
        raise ArgumentError,
              "could not load strategy module #{inspect(mod)}: #{reason}"
    end
  end
end
