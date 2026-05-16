defmodule Omni.Tools.WebSearch.Providers.SerperTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebSearch.Providers.Serper

  @fixtures_dir Path.expand("../../../../support/fixtures", __DIR__)

  defp stub_serper(name, fun) do
    Req.Test.stub(name, fun)
    [api_key: "test-key", req: Req.new(plug: {Req.Test, name})]
  end

  defp stub_fixture(name, fixture, status \\ 200) do
    body = File.read!(Path.join(@fixtures_dir, fixture))

    stub_serper(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  defp ok_body(results \\ []) do
    Jason.encode!(%{"organic" => results})
  end

  defp read_json_body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    Jason.decode!(body)
  end

  describe "request building" do
    test "sends api key in x-api-key header" do
      opts =
        stub_serper(:serper_auth, fn conn ->
          assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test-key"]

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Serper.search("test", opts)
    end

    test "sends POST request with query in JSON body" do
      opts =
        stub_serper(:serper_query, fn conn ->
          assert conn.method == "POST"
          body = read_json_body(conn)
          assert body["q"] == "elixir genserver"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Serper.search("elixir genserver", opts)
    end

    test "maps num_results to num in body" do
      opts =
        stub_serper(:serper_num, fn conn ->
          body = read_json_body(conn)
          assert body["num"] == 3

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Serper.search("test", Keyword.put(opts, :num_results, 3))
    end

    test "maps recency to tbs in body" do
      for {recency, expected} <- [day: "qdr:d", week: "qdr:w", month: "qdr:m", year: "qdr:y"] do
        stub_name = :"serper_tbs_#{recency}"

        opts =
          stub_serper(stub_name, fn conn ->
            body = read_json_body(conn)
            assert body["tbs"] == expected

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, ok_body())
          end)

        Serper.search("test", Keyword.put(opts, :recency, recency))
      end
    end

    test "omits tbs when recency is nil" do
      opts =
        stub_serper(:serper_no_tbs, fn conn ->
          body = read_json_body(conn)
          refute Map.has_key?(body, "tbs")

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      Serper.search("test", opts)
    end

    test "passes extra options through in JSON body" do
      opts =
        stub_serper(:serper_passthrough, fn conn ->
          body = read_json_body(conn)
          assert body["gl"] == "uk"
          assert body["hl"] == "en"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ok_body())
        end)

      opts = opts ++ [gl: "uk", hl: "en"]
      Serper.search("test", opts)
    end
  end

  describe "response parsing" do
    test "extracts results from real API response" do
      opts = stub_fixture(:serper_fixture, "serper.query.json")
      assert {:ok, results} = Serper.search("Elixir GenServer timeout handling", opts)

      assert length(results) == 5

      first = hd(results)
      assert first.url == "https://elixirforum.com/t/genserver-timeout-how-do-i-handle-this/57137"
      assert first.title =~ "GenServer timeout"
      assert is_binary(first.snippet)
      assert first.snippet != ""
    end

    test "maps link to url and snippet for each result" do
      opts = stub_fixture(:serper_fixture_fields, "serper.query.json")
      {:ok, results} = Serper.search("test", opts)

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
    test "extracts message from real API auth error" do
      opts = stub_fixture(:serper_auth_error, "serper.autherror.json", 403)
      assert {:error, message} = Serper.search("test", opts)
      assert message =~ "403"
      assert message =~ "Unauthorized"
    end

    test "returns error tuple on non-200 status" do
      opts =
        stub_serper(:serper_error, fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, Jason.encode!(%{"message" => "Invalid API key"}))
        end)

      assert {:error, "Serper API 401: Invalid API key"} = Serper.search("test", opts)
    end

    @tag capture_log: true
    test "returns error tuple on network failure" do
      opts =
        stub_serper(:serper_network, fn conn ->
          Req.Test.transport_error(conn, :econnrefused)
        end)

      assert {:error, message} = Serper.search("test", opts)
      assert message =~ "connection refused"
    end
  end

  describe "config resolution" do
    test "resolves {:system, var} api_key from environment" do
      System.put_env("SERPER_API_KEY", "env-key")
      on_exit(fn -> System.delete_env("SERPER_API_KEY") end)

      Req.Test.stub(:serper_env, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["env-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Serper.search("test", req: Req.new(plug: {Req.Test, :serper_env}))
    end

    test "raises when {:system, var} env var is not set" do
      existing = System.get_env("SERPER_API_KEY")
      System.delete_env("SERPER_API_KEY")
      on_exit(fn -> if existing, do: System.put_env("SERPER_API_KEY", existing) end)

      assert_raise ArgumentError, ~r/environment variable SERPER_API_KEY is not set/, fn ->
        Serper.search("test", [])
      end
    end

    test "resolves api_key from application config" do
      Application.put_env(:omni_tools, Serper, api_key: "app-config-key")
      on_exit(fn -> Application.delete_env(:omni_tools, Serper) end)

      Req.Test.stub(:serper_app_config, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["app-config-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Serper.search("test", req: Req.new(plug: {Req.Test, :serper_app_config}))
    end

    test "explicit string key overrides app config" do
      Application.put_env(:omni_tools, Serper, api_key: "app-key")
      on_exit(fn -> Application.delete_env(:omni_tools, Serper) end)

      Req.Test.stub(:serper_override, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["explicit-key"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ok_body())
      end)

      Serper.search("test",
        api_key: "explicit-key",
        req: Req.new(plug: {Req.Test, :serper_override})
      )
    end
  end
end
