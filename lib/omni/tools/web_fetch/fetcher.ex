defmodule Omni.Tools.WebFetch.Fetcher do
  @moduledoc false

  alias Omni.Tools.WebFetch.Strategy

  @doc """
  Fetches one or more URLs, returning extracted content as a string.

  For a single URL, returns the content directly. For multiple URLs,
  returns sections separated by URL headers and dividers.
  """
  @spec fetch([String.t()], [{module(), keyword()}], keyword()) :: String.t()
  def fetch([url], strategies, state) do
    case fetch_one(url, strategies, state) do
      {_url, {:ok, content}} -> content
      {url, {:error, exception}} -> raise "#{url}: #{Exception.message(exception)}"
    end
  end

  def fetch(urls, strategies, state) do
    results =
      urls
      |> Task.async_stream(
        &fetch_one(&1, strategies, state),
        max_concurrency: 3,
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)

    case Enum.find(results, &match?({_, {:error, _}}, &1)) do
      {url, {:error, exception}} ->
        raise "#{url}: #{Exception.message(exception)}"

      nil ->
        results |> Enum.map(fn {url, {:ok, content}} -> {url, content} end) |> assemble_batch()
    end
  end

  # ── Per-URL fetch ────────────────────────────────────────────────

  defp fetch_one(url, strategies, state) do
    uri = URI.parse(url)

    result =
      with :ok <- validate_scheme(uri),
           {mod, opts} <- find_strategy(strategies, uri) do
        case execute_request(uri, url, mod, opts, state) do
          {:ok, %Req.Response{} = response} ->
            {:ok, extract_content(response, mod, opts, state)}

          {:ok, message} when is_binary(message) ->
            {:ok, message}

          {:error, exception} ->
            {:error, exception}
        end
      else
        {:error, message} -> {:ok, message}
      end

    {url, result}
  end

  defp validate_scheme(%URI{scheme: scheme}) when scheme in ["http", "https"], do: :ok

  defp validate_scheme(%URI{scheme: nil} = uri) do
    {:error, "Invalid URL (missing scheme): #{URI.to_string(uri)}"}
  end

  defp validate_scheme(%URI{scheme: scheme} = uri) do
    {:error, "Unsupported scheme #{inspect(scheme)}: #{URI.to_string(uri)}"}
  end

  defp find_strategy(strategies, uri) do
    case Strategy.find(strategies, uri) do
      nil -> {:error, "No matching strategy for #{URI.to_string(uri)}"}
      match -> match
    end
  end

  defp execute_request(_uri, url, mod, opts, state) do
    req = build_req(url, mod, opts, state)

    case Req.request(req) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %{status: status}} ->
        {:ok, "HTTP #{status} — #{url}"}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp extract_content(response, mod, opts, state) do
    response = ensure_utf8_body(response)
    content = mod.extract(response, opts)
    max_output = Keyword.fetch!(state, :max_output)
    truncate(content, max_output)
  end

  # ── Request building ─────────────────────────────────────────────

  defp build_req(url, mod, opts, state) do
    base_req = Keyword.fetch!(state, :req)
    timeout = Keyword.fetch!(state, :timeout)

    req =
      Req.merge(base_req, url: url, receive_timeout: timeout, decode_body: false, retry: false)

    if function_exported?(mod, :request, 2) do
      mod.request(req, opts)
    else
      req
    end
  end

  # ── Batch assembly ───────────────────────────────────────────────

  defp assemble_batch(results) do
    results
    |> Enum.map(fn {url, content} -> "## #{url}\n\n#{content}" end)
    |> Enum.join("\n\n---\n\n")
  end

  # ── UTF-8 safety ─────────────────────────────────────────────────

  defp ensure_utf8_body(%{body: body} = response) when is_binary(body) do
    if String.valid?(body) do
      response
    else
      case :unicode.characters_to_binary(body, :utf8) do
        valid when is_binary(valid) -> %{response | body: valid}
        {:error, valid, _} -> %{response | body: IO.iodata_to_binary(valid)}
        {:incomplete, valid, _} -> %{response | body: IO.iodata_to_binary(valid)}
      end
    end
  end

  defp ensure_utf8_body(response), do: response

  # ── Truncation ───────────────────────────────────────────────────

  defp truncate(content, :infinity), do: content
  defp truncate(content, max) when byte_size(content) <= max, do: content

  defp truncate(content, max) do
    head = binary_part(content, 0, max)
    snapped = snap_to_last_newline(head)
    total = byte_size(content)

    "#{snapped}\n...(truncated, showing first #{format_bytes(byte_size(snapped))} of #{format_bytes(total)})"
  end

  defp snap_to_last_newline(binary) do
    size = byte_size(binary)

    case :binary.match(binary, "\n", [{:scope, {size, -size}}]) do
      {pos, 1} -> binary_part(binary, 0, pos)
      :nomatch -> binary
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
