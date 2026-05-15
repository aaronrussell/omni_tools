defmodule Omni.Tools.WebSearchTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebSearch
  alias Omni.Tools.WebSearch.TestProvider

  defp tool(opts \\ []) do
    opts = Keyword.put_new(opts, :provider, {TestProvider, []})
    WebSearch.new(opts)
  end

  describe "new/1" do
    test "returns a tool with the web_search name" do
      assert %Omni.Tool{name: "web_search"} = tool()
    end

    test "raises without :provider" do
      assert_raise ArgumentError, ~r/:provider is required/, fn ->
        WebSearch.new([])
      end
    end

    test "raises with invalid provider module" do
      assert_raise ArgumentError, ~r/could not load provider module/, fn ->
        WebSearch.new(provider: {NoSuchModule, []})
      end
    end

    test "accepts provider from app config" do
      Application.put_env(:omni_tools, WebSearch, provider: {TestProvider, []})

      on_exit(fn ->
        Application.delete_env(:omni_tools, WebSearch)
      end)

      assert %Omni.Tool{name: "web_search"} = WebSearch.new([])
    end

    test "explicit opts override app config" do
      Application.put_env(:omni_tools, WebSearch, num_results: 3)

      on_exit(fn ->
        Application.delete_env(:omni_tools, WebSearch)
      end)

      t = tool(num_results: 7)
      result = t.handler.(%{query: "test"})
      refute result =~ "3."
    end
  end

  describe "schema" do
    test "includes query as required" do
      t = tool()
      assert t.input_schema.required == [:query]
      assert Map.has_key?(t.input_schema.properties, :query)
    end

    test "includes num_results and recency as optional" do
      t = tool()
      assert Map.has_key?(t.input_schema.properties, :num_results)
      assert Map.has_key?(t.input_schema.properties, :recency)
    end
  end

  describe "call — successful results" do
    test "formats results as numbered text" do
      t = tool()
      result = t.handler.(%{query: "elixir genserver"})

      assert result =~ "1. First Result"
      assert result =~ "   https://example.com/1"
      assert result =~ "   The first snippet"
      assert result =~ "2. Second Result"
      assert result =~ "   https://example.com/2"
      assert result =~ "   The second snippet"
    end

    test "returns no results message for empty results" do
      t = tool(provider: {TestProvider, respond_with: :empty})
      result = t.handler.(%{query: "nothing here"})

      assert result == "No results found."
    end
  end

  describe "call — error handling" do
    test "raises on provider error" do
      t = tool(provider: {TestProvider, respond_with: {:error, "rate limited"}})

      assert_raise RuntimeError, ~r/search failed: rate limited/, fn ->
        t.handler.(%{query: "test"})
      end
    end

    test "raises when query is missing" do
      t = tool()

      assert_raise RuntimeError, ~r/query is required/, fn ->
        t.handler.(%{})
      end
    end

    test "raises when query is empty" do
      t = tool()

      assert_raise RuntimeError, ~r/query is required/, fn ->
        t.handler.(%{query: ""})
      end
    end
  end

  describe "call — options passing" do
    test "passes num_results to provider" do
      defmodule AssertNumResults do
        @behaviour Omni.Tools.WebSearch.Provider

        @impl true
        def search(_query, opts) do
          send(self(), {:search_opts, opts})
          {:ok, [%{url: "https://example.com", title: "Test", snippet: "Snippet"}]}
        end
      end

      t = WebSearch.new(provider: {AssertNumResults, []})
      t.handler.(%{query: "test", num_results: 10})

      assert_received {:search_opts, opts}
      assert Keyword.fetch!(opts, :num_results) == 10
    end

    test "uses default num_results when not in input" do
      defmodule AssertDefaultNumResults do
        @behaviour Omni.Tools.WebSearch.Provider

        @impl true
        def search(_query, opts) do
          send(self(), {:search_opts, opts})
          {:ok, [%{url: "https://example.com", title: "Test", snippet: "Snippet"}]}
        end
      end

      t = WebSearch.new(provider: {AssertDefaultNumResults, []}, num_results: 3)
      t.handler.(%{query: "test"})

      assert_received {:search_opts, opts}
      assert Keyword.fetch!(opts, :num_results) == 3
    end

    test "passes recency to provider as atom" do
      defmodule AssertRecency do
        @behaviour Omni.Tools.WebSearch.Provider

        @impl true
        def search(_query, opts) do
          send(self(), {:search_opts, opts})
          {:ok, [%{url: "https://example.com", title: "Test", snippet: "Snippet"}]}
        end
      end

      t = WebSearch.new(provider: {AssertRecency, []})
      t.handler.(%{query: "test", recency: "week"})

      assert_received {:search_opts, opts}
      assert Keyword.fetch!(opts, :recency) == :week
    end

    test "omits recency when not provided" do
      defmodule AssertNoRecency do
        @behaviour Omni.Tools.WebSearch.Provider

        @impl true
        def search(_query, opts) do
          send(self(), {:search_opts, opts})
          {:ok, [%{url: "https://example.com", title: "Test", snippet: "Snippet"}]}
        end
      end

      t = WebSearch.new(provider: {AssertNoRecency, []})
      t.handler.(%{query: "test"})

      assert_received {:search_opts, opts}
      refute Keyword.has_key?(opts, :recency)
    end
  end
end
