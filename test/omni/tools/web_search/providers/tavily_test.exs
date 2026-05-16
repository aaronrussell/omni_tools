defmodule Omni.Tools.WebSearch.Providers.TavilyTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebSearch.Providers.Tavily

  @fixtures_dir Path.expand("../../../../support/fixtures", __DIR__)

  defp stub_tavily(name, fun) do
    Req.Test.stub(name, fun)
    [api_key: "test-key", req: Req.new(plug: {Req.Test, name})]
  end

  defp stub_fixture(name, fixture, status \\ 200) do
    body = File.read!(Path.join(@fixtures_dir, fixture))

    stub_tavily(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  defp ok_body(results \\ []) do
    Jason.encode!(%{"results" => results})
  end

  defp read_json_body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    Jason.decode!(body)
  end

  describe "request building" do
    test "sends api key as bearer token" do
      opts =
        stub_tavily(:tavily_auth, fn conn ->
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Tavily.search("test", opts)
    end

    test "sends POST request with query in JSON body" do
      opts =
        stub_tavily(:tavily_query, fn conn ->
          assert conn.method == "POST"
          body = read_json_body(conn)
          assert body["query"] == "elixir genserver"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Tavily.search("elixir genserver", opts)
    end

    test "maps num_results to max_results in body" do
      opts =
        stub_tavily(:tavily_max, fn conn ->
          body = read_json_body(conn)
          assert body["max_results"] == 3

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Tavily.search("test", Keyword.put(opts, :num_results, 3))
    end

    test "maps recency to time_range in body" do
      for {recency, expected} <- [day: "day", week: "week", month: "month", year: "year"] do
        stub_name = :"tavily_time_#{recency}"

        opts =
          stub_tavily(stub_name, fn conn ->
            body = read_json_body(conn)
            assert body["time_range"] == expected

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, ok_body())
          end)

        Tavily.search("test", Keyword.put(opts, :recency, recency))
      end
    end

    test "omits time_range when recency is nil" do
      opts =
        stub_tavily(:tavily_no_time, fn conn ->
          body = read_json_body(conn)
          refute Map.has_key?(body, "time_range")

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Tavily.search("test", opts)
    end

    test "passes extra options through in JSON body" do
      opts =
        stub_tavily(:tavily_passthrough, fn conn ->
          body = read_json_body(conn)
          assert body["topic"] == "news"
          assert body["search_depth"] == "advanced"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      opts = opts ++ [topic: "news", search_depth: "advanced"]
      Tavily.search("test", opts)
    end
  end

  describe "response parsing" do
    test "extracts results from real API response" do
      opts = stub_fixture(:tavily_fixture, "tavily.query.json")
      assert {:ok, results} = Tavily.search("Elixir GenServer timeout handling", opts)

      assert length(results) == 5

      first = hd(results)

      assert first.url ==
               "https://dev.to/herminiotorres/managing-timeouts-in-genserver-in-elixir-how-to-control-waiting-time-in-critical-operations-25jc"

      assert first.title =~ "Managing Timeouts in GenServer"
      assert is_binary(first.snippet)
      assert first.snippet != ""
    end

    test "maps content to snippet for each result" do
      opts = stub_fixture(:tavily_fixture_fields, "tavily.query.json")
      {:ok, results} = Tavily.search("test", opts)

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
      opts = stub_fixture(:tavily_auth_error, "tavily.autherror.json", 401)
      assert {:error, message} = Tavily.search("test", opts)
      assert message =~ "401"
      assert message =~ "missing or invalid API key"
    end

    test "returns error tuple on non-200 status" do
      opts =
        stub_tavily(:tavily_error, fn conn ->
          body = Jason.encode!(%{"detail" => %{"error" => "Invalid API key"}})

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, body)
        end)

      assert {:error, "Tavily API 401: Invalid API key"} = Tavily.search("test", opts)
    end

    @tag capture_log: true
    test "returns error tuple on network failure" do
      opts =
        stub_tavily(:tavily_network, fn conn ->
          Req.Test.transport_error(conn, :econnrefused)
        end)

      assert {:error, message} = Tavily.search("test", opts)
      assert message =~ "connection refused"
    end
  end

  describe "config resolution" do
    test "resolves {:system, var} api_key from environment" do
      System.put_env("TAVILY_API_KEY", "env-key")
      on_exit(fn -> System.delete_env("TAVILY_API_KEY") end)

      Req.Test.stub(:tavily_env, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer env-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Tavily.search("test", req: Req.new(plug: {Req.Test, :tavily_env}))
    end

    test "raises when {:system, var} env var is not set" do
      existing = System.get_env("TAVILY_API_KEY")
      System.delete_env("TAVILY_API_KEY")
      on_exit(fn -> if existing, do: System.put_env("TAVILY_API_KEY", existing) end)

      assert_raise ArgumentError, ~r/environment variable TAVILY_API_KEY is not set/, fn ->
        Tavily.search("test", [])
      end
    end

    test "resolves api_key from application config" do
      Application.put_env(:omni_tools, Tavily, api_key: "app-config-key")
      on_exit(fn -> Application.delete_env(:omni_tools, Tavily) end)

      Req.Test.stub(:tavily_app_config, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer app-config-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Tavily.search("test", req: Req.new(plug: {Req.Test, :tavily_app_config}))
    end

    test "explicit string key overrides app config" do
      Application.put_env(:omni_tools, Tavily, api_key: "app-key")
      on_exit(fn -> Application.delete_env(:omni_tools, Tavily) end)

      Req.Test.stub(:tavily_override, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer explicit-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Tavily.search("test",
        api_key: "explicit-key",
        req: Req.new(plug: {Req.Test, :tavily_override})
      )
    end
  end
end
