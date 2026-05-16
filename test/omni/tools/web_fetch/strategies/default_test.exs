defmodule Omni.Tools.WebFetch.Strategies.DefaultTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebFetch.Strategies.Default

  defp response(body, content_type) do
    headers = if content_type, do: %{"content-type" => [content_type]}, else: %{}
    %Req.Response{status: 200, headers: headers, body: body}
  end

  describe "match?/2" do
    test "always returns true" do
      assert Default.match?(URI.parse("https://example.com"), [])
      assert Default.match?(URI.parse("ftp://anything"), [])
    end
  end

  describe "extract/2 — HTML" do
    test "converts HTML to markdown" do
      html = "<h1>Title</h1><p>Hello world</p>"
      result = Default.extract(response(html, "text/html"), [])
      assert result =~ "Title"
      assert result =~ "Hello world"
    end

    test "strips boilerplate tags" do
      html = """
      <html>
      <body>
        <nav><a href="/">Home</a></nav>
        <main><h1>Article</h1><p>Content here</p></main>
        <script>alert('xss')</script>
        <style>.foo { color: red; }</style>
      </body>
      </html>
      """

      result = Default.extract(response(html, "text/html"), [])
      assert result =~ "Article"
      assert result =~ "Content here"
      refute result =~ "alert"
      refute result =~ "color: red"
    end

    test "handles text/html with charset parameter" do
      html = "<p>Hello</p>"
      result = Default.extract(response(html, "text/html; charset=utf-8"), [])
      assert result =~ "Hello"
    end
  end

  describe "extract/2 — JSON" do
    test "pretty-prints JSON" do
      json = ~s({"name":"test","value":42})
      result = Default.extract(response(json, "application/json"), [])
      assert result =~ "\"name\": \"test\""
      assert result =~ "\"value\": 42"
    end

    test "handles JSON with charset parameter" do
      json = ~s({"ok":true})
      result = Default.extract(response(json, "application/json; charset=utf-8"), [])
      assert result =~ "\"ok\": true"
    end

    test "falls back to raw body on invalid JSON" do
      body = "not valid json"
      result = Default.extract(response(body, "application/json"), [])
      assert result == "not valid json"
    end

    test "handles vendor JSON types with +json suffix" do
      json = ~s({"data":"value"})
      result = Default.extract(response(json, "application/vnd.api+json"), [])
      assert result =~ "\"data\": \"value\""
    end
  end

  describe "extract/2 — text" do
    test "passes through plain text" do
      text = "Hello, plain text!"
      result = Default.extract(response(text, "text/plain"), [])
      assert result == "Hello, plain text!"
    end

    test "passes through CSV" do
      csv = "name,age\nAlice,30\nBob,25"
      result = Default.extract(response(csv, "text/csv"), [])
      assert result == csv
    end

    test "passes through XML" do
      xml = "<root><item>test</item></root>"
      result = Default.extract(response(xml, "text/xml"), [])
      assert result == xml
    end
  end

  describe "extract/2 — binary and edge cases" do
    test "returns metadata for binary content" do
      body = :crypto.strong_rand_bytes(1_024)
      result = Default.extract(response(body, "application/pdf"), [])
      assert result =~ "Binary content: application/pdf"
      assert result =~ "1.0KB"
    end

    test "returns metadata for image content" do
      body = String.duplicate("x", 5_000)
      result = Default.extract(response(body, "image/png"), [])
      assert result =~ "Binary content: image/png"
      assert result =~ "4.9KB"
    end

    test "defaults to binary metadata when content-type header is missing" do
      resp = %Req.Response{status: 200, headers: %{}, body: "some bytes"}
      result = Default.extract(resp, [])
      assert result =~ "Binary content: application/octet-stream"
    end

    test "returns marker for empty body" do
      result = Default.extract(response("", "text/html"), [])
      assert result == "(empty response)"
    end

    test "returns marker for nil body" do
      result = Default.extract(response(nil, "text/html"), [])
      assert result == "(empty response)"
    end
  end
end
