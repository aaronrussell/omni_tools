defmodule Omni.Tools.WebFetch.Strategies.Default do
  @moduledoc false

  @behaviour Omni.Tools.WebFetch.Strategy

  @impl true
  def match?(_uri, _opts), do: true

  @impl true
  def extract(%{body: body}, _opts) when body in [nil, ""] do
    "(empty response)"
  end

  def extract(response, _opts) do
    content_type = parse_content_type(response)

    cond do
      content_type == "text/html" ->
        Html2Markdown.convert(response.body)

      json_type?(content_type) ->
        pretty_json(response.body)

      String.starts_with?(content_type, "text/") ->
        response.body

      true ->
        "Binary content: #{content_type}, #{format_bytes(byte_size(response.body))}"
    end
  end

  defp json_type?("application/json"), do: true
  defp json_type?(type), do: String.ends_with?(type, "+json")

  defp pretty_json(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> body
    end
  end

  defp parse_content_type(response) do
    case Req.Response.get_header(response, "content-type") do
      [value | _] ->
        value
        |> String.split(";", parts: 2)
        |> hd()
        |> String.trim()
        |> String.downcase()

      [] ->
        "application/octet-stream"
    end
  end

  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes}B"

  defp format_bytes(bytes) when bytes < 1_048_576 do
    kb = Float.round(bytes / 1_024, 1)
    "#{kb}KB"
  end

  defp format_bytes(bytes) do
    mb = Float.round(bytes / 1_048_576, 1)
    "#{mb}MB"
  end
end
