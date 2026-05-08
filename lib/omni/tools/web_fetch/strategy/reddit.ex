defmodule Omni.Tools.WebFetch.Strategy.Reddit do
  @moduledoc false

  @behaviour Omni.Tools.WebFetch.Strategy

  @max_comments 20
  @max_depth 2
  @max_replies 5

  @impl true
  def match?(uri, _opts) do
    is_binary(uri.host) and
      (uri.host == "reddit.com" or String.ends_with?(uri.host, ".reddit.com"))
  end

  @impl true
  def request(req, _opts) do
    uri = req.url

    path =
      (uri.path || "/")
      |> String.trim_trailing("/")
      |> then(fn p -> if String.ends_with?(p, ".json"), do: p, else: p <> ".json" end)

    query =
      case uri.query do
        nil -> "raw_json=1"
        existing -> existing <> "&raw_json=1"
      end

    url = URI.to_string(%{uri | path: path, query: query})

    Req.merge(req, url: url, headers: [{"user-agent", "Omni.Tools.WebFetch/0.1"}])
  end

  @impl true
  def extract(%{body: body}, _opts) when body in [nil, ""] do
    "(empty response)"
  end

  def extract(response, _opts) do
    case Jason.decode(response.body) do
      {:ok, [post_listing, comments_listing]} ->
        format_post_page(post_listing, comments_listing)

      {:ok, %{"kind" => "Listing"} = listing} ->
        format_subreddit_listing(listing)

      {:ok, _other} ->
        pretty_json(response.body)

      {:error, _} ->
        response.body
    end
  end

  # ── Post page ────────────────────────────────────────────────────

  defp format_post_page(post_listing, comments_listing) do
    post = get_in(post_listing, ["data", "children", Access.at(0), "data"])
    comments = get_in(comments_listing, ["data", "children"]) || []

    post_section = format_post(post)

    comment_section =
      comments
      |> Enum.filter(&(&1["kind"] == "t1"))
      |> Enum.take(@max_comments)
      |> Enum.map(&format_comment(&1["data"], 0))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    case comment_section do
      "" -> post_section
      section -> post_section <> "\n\n---\n\n## Comments\n\n" <> section
    end
  end

  defp format_post(nil), do: "(post data unavailable)"

  defp format_post(data) do
    title = data["title"] || "(untitled)"
    author = data["author"] || "[deleted]"
    subreddit = data["subreddit"] || "?"
    score = data["score"] || 0

    selftext =
      case data["selftext"] do
        text when is_binary(text) and text != "" -> text
        _ -> nil
      end

    link =
      if not data["is_self"] and is_binary(data["url"]) do
        "Link: #{data["url"]}"
      end

    body =
      [selftext, link]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    header = "# #{title}\n\n**r/#{subreddit}** | #{score} points | u/#{author}"

    case body do
      "" -> header
      text -> header <> "\n\n" <> text
    end
  end

  # ── Comments ─────────────────────────────────────────────────────

  defp format_comment(nil, _depth), do: ""
  defp format_comment(_data, depth) when depth > @max_depth, do: ""

  defp format_comment(data, depth) do
    author = data["author"] || "[deleted]"
    body = data["body"] || ""

    if skip_comment?(author, body), do: "", else: do_format_comment(data, author, body, depth)
  end

  defp do_format_comment(data, author, body, depth) do
    score = data["score"] || 0
    prefix = String.duplicate("> ", depth)

    header = "#{prefix}**u/#{author}** (#{score} points)"

    body_lines =
      body
      |> String.split("\n")
      |> Enum.map_join("\n", &"#{prefix}#{&1}")

    result = header <> "\n" <> body_lines

    replies = format_replies(data["replies"], depth)

    case replies do
      "" -> result
      text -> result <> "\n\n" <> text
    end
  end

  defp format_replies(%{"data" => %{"children" => children}}, depth) when is_list(children) do
    children
    |> Enum.filter(&(&1["kind"] == "t1"))
    |> Enum.take(@max_replies)
    |> Enum.map(&format_comment(&1["data"], depth + 1))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp format_replies(_other, _depth), do: ""

  defp skip_comment?(author, body) do
    author == "[deleted]" and body in ["[removed]", "[deleted]", ""]
  end

  # ── Subreddit listing ───────────────────────────────────────────

  defp format_subreddit_listing(listing) do
    children = get_in(listing, ["data", "children"]) || []

    posts =
      children
      |> Enum.filter(&(&1["kind"] == "t3"))
      |> Enum.map(fn %{"data" => data} ->
        title = data["title"] || "(untitled)"
        score = data["score"] || 0
        permalink = data["permalink"] || ""
        "- **#{score}** [#{title}](https://reddit.com#{permalink})"
      end)

    subreddit =
      case get_in(children, [Access.at(0), "data", "subreddit"]) do
        nil -> "Reddit"
        sub -> "r/#{sub}"
      end

    ["# #{subreddit}" | posts]
    |> Enum.join("\n")
  end

  defp pretty_json(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> body
    end
  end
end
