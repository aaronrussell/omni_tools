defmodule Omni.Tools.WebFetch.Strategies.GitHubTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebFetch.Strategies.GitHub

  describe "match?/2" do
    test "matches github.com blob URLs" do
      assert GitHub.match?(URI.parse("https://github.com/user/repo/blob/main/lib/app.ex"), [])
    end

    test "matches blob URLs with nested paths" do
      uri = URI.parse("https://github.com/user/repo/blob/main/src/deep/nested/file.rs")
      assert GitHub.match?(uri, [])
    end

    test "matches blob URLs with branch refs" do
      assert GitHub.match?(URI.parse("https://github.com/user/repo/blob/v1.2.3/README.md"), [])
    end

    test "rejects non-blob github URLs" do
      refute GitHub.match?(URI.parse("https://github.com/user/repo"), [])
      refute GitHub.match?(URI.parse("https://github.com/user/repo/tree/main/lib"), [])
      refute GitHub.match?(URI.parse("https://github.com/user/repo/issues/42"), [])
      refute GitHub.match?(URI.parse("https://github.com/user/repo/pull/10"), [])
    end

    test "rejects non-github hosts" do
      refute GitHub.match?(URI.parse("https://gitlab.com/user/repo/blob/main/file.ex"), [])
      refute GitHub.match?(URI.parse("https://example.com/blob/main/file.ex"), [])
    end

    test "handles nil path" do
      refute GitHub.match?(%URI{host: "github.com", path: nil}, [])
    end
  end

  describe "request/2" do
    test "rewrites to raw.githubusercontent.com" do
      req = Req.new(url: "https://github.com/user/repo/blob/main/lib/app.ex")
      result = GitHub.request(req, [])
      url = result.url |> URI.to_string()

      assert url == "https://raw.githubusercontent.com/user/repo/main/lib/app.ex"
    end

    test "preserves nested paths" do
      req = Req.new(url: "https://github.com/org/project/blob/develop/src/a/b/c.py")
      result = GitHub.request(req, [])
      url = result.url |> URI.to_string()

      assert url == "https://raw.githubusercontent.com/org/project/develop/src/a/b/c.py"
    end

    test "handles tag refs" do
      req = Req.new(url: "https://github.com/user/repo/blob/v2.0.0/mix.exs")
      result = GitHub.request(req, [])
      url = result.url |> URI.to_string()

      assert url == "https://raw.githubusercontent.com/user/repo/v2.0.0/mix.exs"
    end

    test "handles commit SHA refs" do
      req = Req.new(url: "https://github.com/user/repo/blob/abc123def/file.txt")
      result = GitHub.request(req, [])
      url = result.url |> URI.to_string()

      assert url == "https://raw.githubusercontent.com/user/repo/abc123def/file.txt"
    end
  end

  describe "extract/2" do
    test "returns body directly" do
      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["text/plain"]},
        body: "defmodule App do\n  def hello, do: :world\nend\n"
      }

      result = GitHub.extract(response, [])
      assert result == "defmodule App do\n  def hello, do: :world\nend\n"
    end

    test "handles empty body" do
      response = %Req.Response{status: 200, headers: %{}, body: ""}
      assert GitHub.extract(response, []) == "(empty response)"
    end
  end
end
