defmodule Omni.Tools.WebFetch do
  @moduledoc """
  An `Omni.Tool` for fetching and simplifying web content.

  Fetches one or more URLs, extracts content appropriate for LLM
  consumption (HTML to Markdown, pretty-printed JSON, plain text
  passthrough), and returns the results as a string.

      tool = Omni.Tools.WebFetch.new()
      tool = Omni.Tools.WebFetch.new(max_output: 30_000, timeout: 10_000)

  ## Strategies

  Content extraction is handled by pluggable strategies. Each strategy
  implements `Omni.Tools.WebFetch.Strategy` and declares which URLs it
  handles via `match?/2`. The first matching strategy wins.

  Three strategies ship built-in:

  - **GitHub** — matches `github.com` blob URLs, redirects to
    `raw.githubusercontent.com` for direct file content.
  - **Reddit** — matches `*.reddit.com`, fetches via Reddit's JSON API, formats
    posts and comments as readable Markdown.
  - **Default** — catch-all that handles HTML (→ Markdown), JSON
    (→ pretty-printed), plain text (→ passthrough), and binary (→ metadata).

  Custom strategies are prepended before the defaults:

      tool = Omni.Tools.WebFetch.new(strategies: [{MyApp.GitHubStrategy, token: "..."}])

  ## Custom Req

  Pass a pre-configured `Req.Request` struct to control the HTTP
  transport. This is useful for attaching middleware, setting
  authentication, or replacing the transport layer entirely.

      req = Req.new() |> MyApp.Auth.attach()
      tool = Omni.Tools.WebFetch.new(req: req)

  ## Options

  - `:req` — base `Req.Request` struct. Default: `Req.new()`.
  - `:strategies` — list of strategy modules or `{module, opts}` tuples.
    Default: `[]`.
  - `:max_output` — per-URL content truncation limit in bytes. Set to
    `:infinity` to disable truncation. Default: `100_000`.
  - `:max_urls` — maximum number of URLs per batch call. Default: `10`.
  - `:timeout` — HTTP receive timeout in milliseconds. Default: `15_000`.
  """

  use Omni.Tool, name: "web_fetch"

  alias Omni.Tools.WebFetch.{Fetcher, Strategy}
  alias Omni.Tools.WebFetch.Strategy.{Default, GitHub, Reddit}

  @defaults [
    strategies: [],
    max_output: 100_000,
    max_urls: 10,
    timeout: 15_000
  ]

  @impl Omni.Tool
  def init(opts) do
    opts =
      @defaults
      |> Keyword.merge(Application.get_env(:omni_tools, __MODULE__, []))
      |> Keyword.merge(opts || [])

    req = Keyword.get(opts, :req, Req.new())

    unless is_struct(req, Req.Request) do
      raise ArgumentError, ":req must be a %Req.Request{} struct, got: #{inspect(req)}"
    end

    strategies =
      opts
      |> Keyword.fetch!(:strategies)
      |> Strategy.resolve()
      |> Kernel.++([{GitHub, []}, {Reddit, []}, {Default, []}])

    [
      req: req,
      strategies: strategies,
      max_output: Keyword.fetch!(opts, :max_output),
      max_urls: Keyword.fetch!(opts, :max_urls),
      timeout: Keyword.fetch!(opts, :timeout)
    ]
  end

  @impl Omni.Tool
  def schema(_state) do
    import Omni.Schema

    object(
      %{
        url: string(description: "URL to fetch"),
        urls: array(string(), description: "Multiple URLs to fetch concurrently")
      },
      required: []
    )
  end

  @impl Omni.Tool
  def description(state) do
    max_urls = Keyword.fetch!(state, :max_urls)
    max_output = Keyword.fetch!(state, :max_output)

    truncation_line =
      case max_output do
        :infinity -> nil
        bytes -> "- Content is truncated to ~#{div(bytes, 1_000)}KB per URL"
      end

    output_lines =
      [
        "- HTML pages are converted to Markdown with boilerplate removed",
        "- JSON responses are pretty-printed",
        truncation_line,
        "- Batch results are separated with URL headers"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    """
    Fetch content from web URLs.

    ## Capabilities
    - Fetches web pages and converts HTML to clean Markdown
    - Fetches JSON APIs and returns pretty-printed JSON
    - Handles plain text, with metadata for binary formats (PDF, images, etc.)
    - Supports single URL or batch fetch (up to #{max_urls} URLs)

    ## Parameters
    - `url` — single URL to fetch (string)
    - `urls` — array of URLs to fetch concurrently (max #{max_urls})
    - Provide exactly one of `url` or `urls`

    ## Output
    #{output_lines}

    ## Limitations
    - Binary formats (PDF, DOCX, images) return metadata only, not extracted text
    - Some sites may block automated requests\
    """
  end

  @impl Omni.Tool
  def call(input, state) do
    urls = resolve_urls(input, state)
    Fetcher.fetch(urls, Keyword.fetch!(state, :strategies), state)
  end

  # ── URL resolution ───────────────────────────────────────────────

  defp resolve_urls(input, state) do
    urls =
      case input do
        %{url: url, urls: urls}
        when is_binary(url) and url != "" and is_list(urls) and urls != [] ->
          Enum.uniq([url | urls])

        %{urls: urls} when is_list(urls) and urls != [] ->
          urls

        %{url: url} when is_binary(url) and url != "" ->
          [url]

        _ ->
          raise "provide either `url` (string) or `urls` (array of strings)"
      end

    max = Keyword.fetch!(state, :max_urls)

    if length(urls) > max do
      raise "too many URLs: #{length(urls)} (max #{max})"
    end

    urls
  end
end
