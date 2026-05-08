defmodule Omni.Tools.WebFetch.Strategy.RedditTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.WebFetch.Strategy.Reddit

  describe "match?/2" do
    test "matches www.reddit.com" do
      assert Reddit.match?(URI.parse("https://www.reddit.com/r/elixir"), [])
    end

    test "matches old.reddit.com" do
      assert Reddit.match?(URI.parse("https://old.reddit.com/r/elixir"), [])
    end

    test "matches new.reddit.com" do
      assert Reddit.match?(URI.parse("https://new.reddit.com/r/elixir"), [])
    end

    test "matches bare reddit.com" do
      assert Reddit.match?(URI.parse("https://reddit.com/r/elixir"), [])
    end

    test "rejects non-reddit hosts" do
      refute Reddit.match?(URI.parse("https://example.com"), [])
      refute Reddit.match?(URI.parse("https://notreallyreddit.com"), [])
    end

    test "handles nil host" do
      refute Reddit.match?(%URI{host: nil}, [])
    end
  end

  describe "request/2" do
    defp req_with_url(url) do
      Req.new(url: url)
    end

    test "appends .json to path" do
      req = Reddit.request(req_with_url("https://www.reddit.com/r/elixir"), [])
      assert URI.parse(req.url |> URI.to_string()).path == "/r/elixir.json"
    end

    test "strips trailing slash before appending .json" do
      req = Reddit.request(req_with_url("https://www.reddit.com/r/elixir/"), [])
      assert URI.parse(req.url |> URI.to_string()).path == "/r/elixir.json"
    end

    test "does not double-append .json" do
      req = Reddit.request(req_with_url("https://www.reddit.com/r/elixir.json"), [])
      url = req.url |> URI.to_string()
      refute url =~ ".json.json"
    end

    test "adds raw_json=1 query parameter" do
      req = Reddit.request(req_with_url("https://www.reddit.com/r/elixir"), [])
      url = req.url |> URI.to_string()
      assert url =~ "raw_json=1"
    end

    test "preserves existing query parameters" do
      req = Reddit.request(req_with_url("https://www.reddit.com/r/elixir?sort=new"), [])
      url = req.url |> URI.to_string()
      assert url =~ "sort=new"
      assert url =~ "raw_json=1"
    end

    test "sets user-agent header" do
      req = Reddit.request(req_with_url("https://www.reddit.com/r/elixir"), [])
      headers = Map.new(req.headers)
      assert Map.has_key?(headers, "user-agent")
    end
  end

  describe "extract/2 — post page" do
    test "formats a self-text post with comments" do
      json =
        post_page_json("Test Title", "elixir", "author1", 42, "Post body text", true, [
          comment("commenter1", "Great post!", 10, []),
          comment("commenter2", "Thanks!", 5, [])
        ])

      result = Reddit.extract(%Req.Response{status: 200, body: json}, [])

      assert result =~ "# Test Title"
      assert result =~ "r/elixir"
      assert result =~ "42 points"
      assert result =~ "u/author1"
      assert result =~ "Post body text"
      assert result =~ "Comments"
      assert result =~ "u/commenter1"
      assert result =~ "Great post!"
      assert result =~ "u/commenter2"
    end

    test "formats a link post" do
      json =
        post_page_json("Link Post", "elixir", "poster", 10, "", false, [],
          url: "https://example.com/article"
        )

      result = Reddit.extract(%Req.Response{status: 200, body: json}, [])

      assert result =~ "# Link Post"
      assert result =~ "Link: https://example.com/article"
    end

    test "formats nested replies with blockquote nesting" do
      json =
        post_page_json("Post", "test", "op", 1, "Body", true, [
          comment("user1", "Top comment", 5, [
            comment("user2", "Reply to top", 3, [])
          ])
        ])

      result = Reddit.extract(%Req.Response{status: 200, body: json}, [])

      assert result =~ "**u/user1**"
      assert result =~ "> **u/user2**"
      assert result =~ "> Reply to top"
    end

    test "skips deleted and removed comments" do
      json =
        post_page_json("Post", "test", "op", 1, "Body", true, [
          comment("[deleted]", "[removed]", 0, []),
          comment("[deleted]", "[deleted]", 0, []),
          comment("real_user", "Visible comment", 5, [])
        ])

      result = Reddit.extract(%Req.Response{status: 200, body: json}, [])

      assert result =~ "Visible comment"
      refute result =~ "[removed]"
    end

    test "handles post with no comments" do
      json = post_page_json("Solo Post", "test", "op", 1, "Just me", true, [])
      result = Reddit.extract(%Req.Response{status: 200, body: json}, [])

      assert result =~ "# Solo Post"
      assert result =~ "Just me"
      refute result =~ "Comments"
    end
  end

  describe "extract/2 — subreddit listing" do
    test "formats a subreddit listing as bullet list" do
      json =
        subreddit_listing_json("elixir", [
          {"First Post", 42, "/r/elixir/comments/abc/first_post"},
          {"Second Post", 15, "/r/elixir/comments/def/second_post"}
        ])

      result = Reddit.extract(%Req.Response{status: 200, body: json}, [])

      assert result =~ "# r/elixir"
      assert result =~ "**42** [First Post]"
      assert result =~ "**15** [Second Post]"
    end
  end

  describe "extract/2 — edge cases" do
    test "falls back to pretty JSON on unrecognized structure" do
      json = Jason.encode!(%{"unexpected" => "structure"})
      result = Reddit.extract(%Req.Response{status: 200, body: json}, [])
      assert result =~ "\"unexpected\": \"structure\""
    end

    test "returns raw body on invalid JSON" do
      result = Reddit.extract(%Req.Response{status: 200, body: "not json"}, [])
      assert result == "not json"
    end

    test "handles empty body" do
      result = Reddit.extract(%Req.Response{status: 200, body: ""}, [])
      assert result == "(empty response)"
    end
  end

  # ── Fixture-based tests ──────────────────────────────────────────

  describe "extract/2 — real fixtures" do
    defp fixture(name) do
      path = Path.join(["test", "support", "fixtures", name])
      json = File.read!(path)
      %Req.Response{status: 200, headers: %{}, body: json}
    end

    test "post with comments: includes title, body, and comments" do
      result = Reddit.extract(fixture("reddit.post-with-comments.json"), [])

      assert result =~ "# [KCD2] Zoologist here"
      assert result =~ "r/kingdomcome"
      assert result =~ "686 points"
      assert result =~ "u/JJC165463"
      assert result =~ "ambient chirping from birds"
      assert result =~ "## Comments"
      assert result =~ "u/poopdick4000"
      assert result =~ "moonwalking rabbits"
    end

    test "post without comments: includes title and body, no comments section" do
      result = Reddit.extract(fixture("reddit.post-no-comments.json"), [])

      assert result =~ "# Just finished [KCD1] and have few questions"
      assert result =~ "u/EstablishmentThis888"
      assert result =~ "defeated Istvan Toth"
      refute result =~ "## Comments"
    end

    test "post with image: includes title and body, and link" do
      result = Reddit.extract(fixture("reddit.post-image-with-text.json"), [])

      assert result =~ "# Lost my north trying to get medication"
      assert result =~ "TLDR: I have a private diagnosis"
      assert result =~ "Link: https://www.reddit.com/gallery/1t776zs"
    end

    test "link-only post: shows link URL and comments" do
      result = Reddit.extract(fixture("reddit.post-link-only.json"), [])

      assert result =~ "# Farage claims Reform"
      assert result =~ "Link: https://www.independent.co.uk"
      assert result =~ "## Comments"
    end

    test "image-only post: shows image URL" do
      result = Reddit.extract(fixture("reddit.post-image-only.json"), [])

      assert result =~ "# I’m kinda feeling a bit hungry"
      assert result =~ "Link: https://i.redd.it/mtlwdr629vzg1.jpeg"
    end

    test "media-only post: shows media URL" do
      result = Reddit.extract(fixture("reddit.post-media-only.json"), [])

      assert result =~ "# [OTHER] Kingdom Come Eau de Parfum"
      assert result =~ "Link: https://youtu.be/zjXnLpnksHI"
    end

    test "subreddit listing: formats as bullet list" do
      result = Reddit.extract(fixture("reddit.listing.json"), [])

      assert result =~ "# r/kingdomcome"
      assert result =~ "**323**"
      assert result =~ "[KCD1]"
    end
  end

  # ── JSON builders ────────────────────────────────────────────────

  defp post_page_json(title, subreddit, author, score, selftext, is_self, comments, opts \\ []) do
    post_data = %{
      "title" => title,
      "subreddit" => subreddit,
      "author" => author,
      "score" => score,
      "selftext" => selftext,
      "is_self" => is_self,
      "url" => Keyword.get(opts, :url, "https://reddit.com/r/#{subreddit}/comments/abc/slug")
    }

    post_listing = %{
      "kind" => "Listing",
      "data" => %{
        "children" => [%{"kind" => "t3", "data" => post_data}]
      }
    }

    comments_listing = %{
      "kind" => "Listing",
      "data" => %{
        "children" => comments
      }
    }

    Jason.encode!([post_listing, comments_listing])
  end

  defp comment(author, body, score, replies) do
    reply_listing =
      case replies do
        [] ->
          ""

        children ->
          %{
            "kind" => "Listing",
            "data" => %{"children" => children}
          }
      end

    %{
      "kind" => "t1",
      "data" => %{
        "author" => author,
        "body" => body,
        "score" => score,
        "depth" => 0,
        "replies" => reply_listing
      }
    }
  end

  defp subreddit_listing_json(subreddit, posts) do
    children =
      Enum.map(posts, fn {title, score, permalink} ->
        %{
          "kind" => "t3",
          "data" => %{
            "title" => title,
            "score" => score,
            "permalink" => permalink,
            "subreddit" => subreddit
          }
        }
      end)

    Jason.encode!(%{
      "kind" => "Listing",
      "data" => %{"children" => children}
    })
  end
end
