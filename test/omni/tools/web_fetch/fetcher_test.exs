defmodule Omni.Tools.WebFetch.TestStrategy do
  @behaviour Omni.Tools.WebFetch.Strategy

  @impl true
  def match?(uri, _opts), do: uri.host == "custom.test"

  @impl true
  def request(req, opts) do
    Req.merge(req, headers: [{"x-test", opts[:value] || "default"}])
  end

  @impl true
  def extract(_response, _opts), do: "custom strategy result"
end

defmodule Omni.Tools.WebFetch.FetcherTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebFetch.Fetcher
  alias Omni.Tools.WebFetch.Strategies.Default
  alias Omni.Tools.WebFetch.TestStrategy

  defp default_strategies, do: [{Default, []}]

  defp state(stub_name, opts \\ []) do
    [
      req: Req.new(plug: {Req.Test, stub_name}),
      strategies: Keyword.get(opts, :strategies, default_strategies()),
      max_output: Keyword.get(opts, :max_output, 50_000),
      max_urls: Keyword.get(opts, :max_urls, 5),
      timeout: Keyword.get(opts, :timeout, 15_000)
    ]
  end

  describe "fetch/3 — single URL" do
    test "fetches HTML and converts to markdown" do
      Req.Test.stub(:html_fetch, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<h1>Hello</h1><p>World</p>")
      end)

      result =
        Fetcher.fetch(["https://example.com/page"], default_strategies(), state(:html_fetch))

      assert result =~ "Hello"
      assert result =~ "World"
    end

    test "fetches JSON and pretty-prints" do
      Req.Test.stub(:json_fetch, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ~s({"key":"value"}))
      end)

      result =
        Fetcher.fetch(["https://example.com/api"], default_strategies(), state(:json_fetch))

      assert result =~ "\"key\": \"value\""
    end

    test "returns content string directly for single URL" do
      Req.Test.stub(:single, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "plain text")
      end)

      result = Fetcher.fetch(["https://example.com"], default_strategies(), state(:single))

      refute result =~ "## https://"
      assert result == "plain text"
    end
  end

  describe "fetch/3 — batch" do
    test "returns sections with URL headers and dividers" do
      Req.Test.stub(:batch, fn conn ->
        body =
          case conn.request_path do
            "/page1" -> "Content One"
            "/page2" -> "Content Two"
          end

        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, body)
      end)

      result =
        Fetcher.fetch(
          ["https://example.com/page1", "https://example.com/page2"],
          default_strategies(),
          state(:batch)
        )

      assert result =~ "## https://example.com/page1"
      assert result =~ "Content One"
      assert result =~ "---"
      assert result =~ "## https://example.com/page2"
      assert result =~ "Content Two"
    end
  end

  describe "fetch/3 — HTTP errors (inline)" do
    test "returns inline content for HTTP 404" do
      Req.Test.stub(:not_found, fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      result =
        Fetcher.fetch(["https://example.com/missing"], default_strategies(), state(:not_found))

      assert result =~ "HTTP 404"
    end

    test "returns inline content for HTTP 500" do
      Req.Test.stub(:server_error, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      result =
        Fetcher.fetch(["https://example.com/broken"], default_strategies(), state(:server_error))

      assert result =~ "HTTP 500"
    end

    test "isolates HTTP errors in batch" do
      Req.Test.stub(:mixed_batch, fn conn ->
        case conn.request_path do
          "/good" ->
            conn
            |> Plug.Conn.put_resp_content_type("text/plain")
            |> Plug.Conn.send_resp(200, "good content")

          "/bad" ->
            Plug.Conn.send_resp(conn, 500, "error")
        end
      end)

      result =
        Fetcher.fetch(
          ["https://example.com/good", "https://example.com/bad"],
          default_strategies(),
          state(:mixed_batch)
        )

      assert result =~ "good content"
      assert result =~ "HTTP 500"
    end

    test "returns inline content for invalid URL scheme" do
      result = Fetcher.fetch(["ftp://example.com/file"], default_strategies(), state(:unused))

      assert result =~ "Unsupported scheme"
    end

    test "returns inline content for URL missing scheme" do
      result = Fetcher.fetch(["example.com/page"], default_strategies(), state(:unused))

      assert result =~ "Invalid URL"
      assert result =~ "missing scheme"
    end
  end

  describe "fetch/3 — network errors (raise)" do
    test "raises on network error for single URL" do
      Req.Test.stub(:network_fail, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert_raise RuntimeError, ~r/connection refused/, fn ->
        Fetcher.fetch(
          ["https://example.com"],
          default_strategies(),
          state(:network_fail)
        )
      end
    end

    test "raises on network error in batch" do
      Req.Test.stub(:batch_network_fail, fn conn ->
        case conn.request_path do
          "/good" ->
            conn
            |> Plug.Conn.put_resp_content_type("text/plain")
            |> Plug.Conn.send_resp(200, "good content")

          "/fail" ->
            Req.Test.transport_error(conn, :timeout)
        end
      end)

      assert_raise RuntimeError, ~r/timeout/, fn ->
        Fetcher.fetch(
          ["https://example.com/good", "https://example.com/fail"],
          default_strategies(),
          state(:batch_network_fail)
        )
      end
    end
  end

  describe "fetch/3 — truncation" do
    test "truncates content exceeding max_output" do
      large_body = String.duplicate("Line of content\n", 5_000)

      Req.Test.stub(:large, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, large_body)
      end)

      result =
        Fetcher.fetch(
          ["https://example.com"],
          default_strategies(),
          state(:large, max_output: 1_000)
        )

      assert byte_size(result) < byte_size(large_body)
      assert result =~ "truncated"
      assert result =~ "showing first"
    end

    test "does not truncate content within max_output" do
      body = "Short content"

      Req.Test.stub(:short, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, body)
      end)

      result = Fetcher.fetch(["https://example.com"], default_strategies(), state(:short))

      assert result == "Short content"
      refute result =~ "truncated"
    end
  end

  describe "fetch/3 — custom strategies" do
    test "custom strategy takes precedence over default" do
      Req.Test.stub(:custom, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "raw response")
      end)

      strategies = [{TestStrategy, [value: "test-val"]}, {Default, []}]

      result =
        Fetcher.fetch(
          ["https://custom.test/page"],
          strategies,
          state(:custom, strategies: strategies)
        )

      assert result == "custom strategy result"
    end

    test "falls through to default when custom strategy does not match" do
      Req.Test.stub(:fallthrough, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "default content")
      end)

      strategies = [{TestStrategy, []}, {Default, []}]

      result =
        Fetcher.fetch(
          ["https://other.test/page"],
          strategies,
          state(:fallthrough, strategies: strategies)
        )

      assert result == "default content"
    end
  end
end
