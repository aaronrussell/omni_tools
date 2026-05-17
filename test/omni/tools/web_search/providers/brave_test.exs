defmodule Omni.Tools.WebSearch.Providers.BraveTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebSearch.Providers.Brave

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

    @tag capture_log: true
    test "returns error tuple on network failure" do
      opts =
        stub_brave(:brave_network, fn conn ->
          Req.Test.transport_error(conn, :econnrefused)
        end)

      assert {:error, message} = Brave.search("test", opts)
      assert message =~ "connection refused"
    end
  end

  describe "config resolution" do
    test "resolves {:system, var} api_key from environment" do
      System.put_env("BRAVE_API_KEY", "env-key")
      on_exit(fn -> System.delete_env("BRAVE_API_KEY") end)

      Req.Test.stub(:brave_env, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-subscription-token") == ["env-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Brave.search("test", req: Req.new(plug: {Req.Test, :brave_env}))
    end

    test "resolves custom {:system, var} tuple" do
      System.put_env("MY_BRAVE_KEY", "custom-env-key")
      on_exit(fn -> System.delete_env("MY_BRAVE_KEY") end)

      Req.Test.stub(:brave_custom_env, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-subscription-token") == ["custom-env-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Brave.search("test",
        api_key: {:system, "MY_BRAVE_KEY"},
        req: Req.new(plug: {Req.Test, :brave_custom_env})
      )
    end

    test "raises when {:system, var} env var is not set" do
      existing = System.get_env("BRAVE_API_KEY")
      System.delete_env("BRAVE_API_KEY")
      on_exit(fn -> if existing, do: System.put_env("BRAVE_API_KEY", existing) end)

      assert_raise ArgumentError, ~r/environment variable BRAVE_API_KEY is not set/, fn ->
        Brave.search("test", [])
      end
    end

    test "resolves api_key from application config" do
      Application.put_env(:omni_tools, Brave, api_key: "app-config-key")
      on_exit(fn -> Application.delete_env(:omni_tools, Brave) end)

      Req.Test.stub(:brave_app_config, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-subscription-token") == ["app-config-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Brave.search("test", req: Req.new(plug: {Req.Test, :brave_app_config}))
    end

    test "explicit string key overrides app config" do
      Application.put_env(:omni_tools, Brave, api_key: "app-key")
      on_exit(fn -> Application.delete_env(:omni_tools, Brave) end)

      Req.Test.stub(:brave_override, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-subscription-token") == ["explicit-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Brave.search("test",
        api_key: "explicit-key",
        req: Req.new(plug: {Req.Test, :brave_override})
      )
    end

    test "app config only affects api_key, not other options" do
      Application.put_env(:omni_tools, Brave, api_key: "app-key", country: "GB")
      on_exit(fn -> Application.delete_env(:omni_tools, Brave) end)

      Req.Test.stub(:brave_app_key_only, fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert conn |> Plug.Conn.get_req_header("x-subscription-token") == ["app-key"]
        refute Map.has_key?(params, "country")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Brave.search("test", req: Req.new(plug: {Req.Test, :brave_app_key_only}))
    end
  end
end
