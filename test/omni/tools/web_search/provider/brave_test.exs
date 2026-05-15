defmodule Omni.Tools.WebSearch.Provider.BraveTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebSearch.Provider.Brave

  @fixtures_dir Path.expand("../../../../support/fixtures", __DIR__)

  defp stub_brave(name, fun) do
    Req.Test.stub(name, fun)
    [api_key: "test-key", req: Req.new(plug: {Req.Test, name})]
  end

  defp stub_fixture(name, fixture, status \\ 200) do
    body = File.read!(Path.join(@fixtures_dir, fixture))

    stub_brave(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  defp ok_body(results \\ []) do
    Jason.encode!(%{"web" => %{"results" => results}})
  end

  describe "request building" do
    test "sends api key in x-subscription-token header" do
      opts =
        stub_brave(:brave_auth, fn conn ->
          assert Plug.Conn.get_req_header(conn, "x-subscription-token") == ["test-key"]

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Brave.search("test", opts)
    end

    test "sends query as q param" do
      opts =
        stub_brave(:brave_query, fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["q"] == "elixir genserver"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Brave.search("elixir genserver", opts)
    end

    test "maps num_results to count param" do
      opts =
        stub_brave(:brave_count, fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["count"] == "3"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Brave.search("test", Keyword.put(opts, :num_results, 3))
    end

    test "maps recency to freshness param" do
      for {recency, expected} <- [day: "pd", week: "pw", month: "pm", year: "py"] do
        stub_name = :"brave_freshness_#{recency}"

        opts =
          stub_brave(stub_name, fn conn ->
            params = Plug.Conn.fetch_query_params(conn).query_params
            assert params["freshness"] == expected

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, ok_body())
          end)

        Brave.search("test", Keyword.put(opts, :recency, recency))
      end
    end

    test "omits freshness when recency is nil" do
      opts =
        stub_brave(:brave_no_freshness, fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          refute Map.has_key?(params, "freshness")

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Brave.search("test", opts)
    end

    test "passes extra options through as query params" do
      opts =
        stub_brave(:brave_passthrough, fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["country"] == "GB"
          assert params["safesearch"] == "strict"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      opts = opts ++ [country: "GB", safesearch: "strict"]
      Brave.search("test", opts)
    end
  end

  describe "response parsing" do
    test "extracts results from real API response" do
      opts = stub_fixture(:brave_fixture, "brave.query.json")
      assert {:ok, results} = Brave.search("Elixir GenServer timeout handling", opts)

      assert length(results) == 5

      first = hd(results)
      assert first.url == "https://hexdocs.pm/elixir/GenServer.html"
      assert first.title == "GenServer behaviour (Elixir v1.19.5)"
      assert is_binary(first.snippet)
      assert first.snippet != ""
    end

    test "maps url, title, and description for each result" do
      opts = stub_fixture(:brave_fixture_fields, "brave.query.json")
      {:ok, results} = Brave.search("test", opts)

      for result <- results do
        assert Map.has_key?(result, :url)
        assert Map.has_key?(result, :title)
        assert Map.has_key?(result, :snippet)
        assert is_binary(result.url)
        assert is_binary(result.title)
        assert is_binary(result.snippet)
      end
    end
  end

  describe "error handling" do
    test "extracts detail from real API auth error" do
      opts = stub_fixture(:brave_auth_error, "brave.autherror.json", 422)
      assert {:error, message} = Brave.search("test", opts)
      assert message =~ "422"
      assert message =~ "The provided subscription token is invalid."
    end

    test "returns error tuple on non-200 status" do
      opts =
        stub_brave(:brave_error, fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, Jason.encode!(%{"message" => "Unauthorized"}))
        end)

      assert {:error, "Brave API 401: Unauthorized"} = Brave.search("test", opts)
    end

    test "returns error tuple on network failure" do
      opts =
        stub_brave(:brave_network, fn conn ->
          Req.Test.transport_error(conn, :econnrefused)
        end)

      assert {:error, message} = Brave.search("test", opts)
      assert message =~ "connection refused"
    end
  end
end
