defmodule Omni.Tools.WebFetchTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebFetch

  defp tool(opts \\ []) do
    stub_name = Keyword.get(opts, :stub, :web_fetch_default)
    opts = Keyword.put_new(opts, :req, Req.new(plug: {Req.Test, stub_name}))
    WebFetch.new(opts)
  end

  describe "new/1" do
    test "returns a tool with the web_fetch name" do
      assert %Omni.Tool{name: "web_fetch"} = tool()
    end

    test "accepts all configuration options" do
      t =
        tool(
          max_output: 10_000,
          max_urls: 3,
          timeout: 5_000
        )

      assert %Omni.Tool{} = t
    end

    test "raises on invalid :req option" do
      assert_raise ArgumentError, ~r/:req must be a %Req.Request{}/, fn ->
        WebFetch.new(req: "not a struct")
      end
    end

    test "raises on invalid strategy" do
      assert_raise ArgumentError, ~r/expected a strategy module/, fn ->
        WebFetch.new(strategies: ["not a module"])
      end
    end

    test "raises when strategy module does not implement callbacks" do
      assert_raise ArgumentError, ~r/must implement match\?\/2 and extract\/2/, fn ->
        WebFetch.new(strategies: [String])
      end
    end
  end

  describe "schema" do
    test "has url and urls properties" do
      t = tool()
      schema = t.input_schema

      assert schema.properties.url.type == "string"
      assert schema.properties.urls.type == "array"
    end

    test "neither url nor urls is required" do
      t = tool()
      schema = t.input_schema
      assert schema.required == []
    end
  end

  describe "description" do
    test "includes max_urls limit" do
      t = tool(max_urls: 3)
      assert t.description =~ "3"
    end

    test "includes max_output as KB" do
      t = tool(max_output: 50_000)
      assert t.description =~ "50KB"
    end

    test "omits truncation line when max_output is :infinity" do
      t = tool(max_output: :infinity)
      refute t.description =~ "truncated"
    end
  end

  describe "call — single URL" do
    test "returns content for a single URL" do
      Req.Test.stub(:single_call, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "hello from web")
      end)

      t = tool(stub: :single_call)
      result = t.handler.(%{url: "https://example.com"})

      assert result == "hello from web"
    end
  end

  describe "call — batch URLs" do
    test "returns batch format for multiple URLs" do
      Req.Test.stub(:batch_call, fn conn ->
        body =
          case conn.request_path do
            "/a" -> "Content A"
            "/b" -> "Content B"
          end

        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, body)
      end)

      t = tool(stub: :batch_call)
      result = t.handler.(%{urls: ["https://example.com/a", "https://example.com/b"]})

      assert result =~ "## https://example.com/a"
      assert result =~ "Content A"
      assert result =~ "## https://example.com/b"
      assert result =~ "Content B"
    end
  end

  describe "call — validation" do
    test "raises when neither url nor urls provided" do
      t = tool()

      assert_raise RuntimeError, ~r/provide either/, fn ->
        t.handler.(%{})
      end
    end

    test "raises when too many URLs" do
      t = tool(max_urls: 2)

      assert_raise RuntimeError, ~r/too many URLs/, fn ->
        t.handler.(%{urls: ["https://a.com", "https://b.com", "https://c.com"]})
      end
    end
  end

  describe "app config fallback" do
    test "uses application config when option not provided" do
      Application.put_env(:omni_tools, Omni.Tools.WebFetch, max_output: 12_345)

      on_exit(fn ->
        Application.delete_env(:omni_tools, Omni.Tools.WebFetch)
      end)

      t = tool()
      assert t.description =~ "12KB"
    end

    test "explicit option overrides application config" do
      Application.put_env(:omni_tools, Omni.Tools.WebFetch, max_output: 12_345)

      on_exit(fn ->
        Application.delete_env(:omni_tools, Omni.Tools.WebFetch)
      end)

      t = tool(max_output: 99_000)
      assert t.description =~ "99KB"
    end
  end
end
