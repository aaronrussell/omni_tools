defmodule Omni.Tools.Repl do
  @moduledoc """
  An `Omni.Tool` for executing Elixir code in a sandboxed peer node.

  Each invocation runs in a fresh Erlang peer node with a clean slate.
  IO output is captured and returned alongside the expression result.

      tool = Omni.Tools.Repl.new()
      tool = Omni.Tools.Repl.new(timeout: 30_000, max_output: 10_000)

  ## Extensions

  Extensions inject code and/or documentation into the sandbox. Pass
  module-based extensions as `{module, opts}` tuples, or use inline
  extensions via `Omni.Tools.Repl.Extension.new/1`.

      alias Omni.Tools.Repl.Extension

      tool = Omni.Tools.Repl.new(
        extensions: [
          {MyApp.ReplExtension, api_key: "sk-..."},
          Extension.new(description: "Req and Jason are available.")
        ]
      )

  See `Omni.Tools.Repl.Extension` for the full extension API.

  ## Options

  - `:timeout` — execution timeout in milliseconds. Default `60_000`.
  - `:max_output` — output truncation limit in bytes. Default `50_000`.
  - `:extensions` — list of extensions (module tuples or `%Extension{}`).
  """

  use Omni.Tool, name: "repl"

  alias Omni.Tools.Repl.{Extension, Sandbox}

  @impl Omni.Tool
  def schema do
    import Omni.Schema

    object(
      %{
        title:
          string(
            description:
              "Brief title describing what the code achieves in active form, e.g. 'Calculating average score'"
          ),
        code: string(description: "Elixir code to evaluate")
      },
      required: [:title, :code]
    )
  end

  @impl Omni.Tool
  def init(opts) do
    opts = opts || []

    opts
    |> Keyword.take([:timeout, :max_output, :extensions])
    |> Keyword.update(:extensions, [], &resolve_extensions/1)
  end

  @impl Omni.Tool
  def description(opts) do
    """
    Execute Elixir code in a sandboxed peer node.

    ## When to Use
    - Calculations and data transformations
    - Testing code snippets and exploring APIs
    - Processing, analysing, or generating data
    - Verifying assumptions about Elixir behaviour

    ## Environment
    - Full Elixir/Erlang standard library
    - Each invocation is a fresh VM — no state persists between calls
    - The host application's compiled dependencies are available
    - Use `Mix.install/1` to add packages not already available (dev only)

    ## Output
    - IO output (IO.puts, IO.inspect, etc.) is captured and returned to you
    - The return value of the last expression is always shown
    - The user does not see raw output — summarise key findings in your response

    ## Example
        numbers = [10, 20, 15, 25]
        sum = Enum.sum(numbers)
        avg = sum / length(numbers)
        IO.puts("Sum: \#{sum}, Average: \#{avg}")

    ## Important Notes
    - Be intentional about return values — end with :ok if only IO output matters
    - For large data, use IO.inspect(data, limit: 20) rather than returning the full structure
    - Define modules freely — they exist only for the current invocation\
    #{extension_section(opts)}
    """
  end

  @impl Omni.Tool
  def call(%{code: code}, opts) do
    setup = build_setup(opts)

    sandbox_opts =
      opts
      |> Keyword.take([:timeout, :max_output])
      |> maybe_put_setup(setup)

    case Sandbox.run(code, sandbox_opts) do
      {:ok, %{output: output, result: result}} ->
        format_success(output, result)

      {:error, :timeout, %{output: output}} ->
        raise format_error(output, "Execution timed out")

      {:error, :noconnection, %{output: output}} ->
        raise format_error(output, "Sandbox node crashed")

      {:error, {kind, reason, stacktrace}, %{output: output}} ->
        raise format_error(output, Exception.format(kind, reason, stacktrace))
    end
  end

  # ── Setup ─────────────────────────────────────────────────────────

  defp build_setup(opts) do
    case opts |> Keyword.get(:extensions, []) |> Enum.map(& &1.code) |> Enum.reject(&is_nil/1) do
      [] -> nil
      codes -> codes
    end
  end

  defp maybe_put_setup(opts, nil), do: opts
  defp maybe_put_setup(opts, setup), do: Keyword.put(opts, :setup, setup)

  defp resolve_extensions(exts) do
    Enum.map(exts, fn
      %Extension{} = ext ->
        ext

      {mod, ext_opts} when is_atom(mod) ->
        %Extension{code: mod.code(ext_opts), description: mod.description(ext_opts)}

      mod when is_atom(mod) ->
        %Extension{code: mod.code([]), description: mod.description([])}

      other ->
        raise ArgumentError,
              "expected an %Extension{}, {module, opts} tuple, or module, got: #{inspect(other)}"
    end)
  end

  # ── Description helpers ───────────────────────────────────────────

  defp extension_section(opts) do
    case Keyword.get(opts, :extensions, []) do
      [] ->
        ""

      exts ->
        desc =
          exts
          |> Enum.map(& &1.description)
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")

        case desc do
          "" -> ""
          text -> "\n\n" <> text
        end
    end
  end

  # ── Formatting ────────────────────────────────────────────────────

  defp format_success(output, result) do
    inspected = inspect(result, pretty: true)

    case output do
      "" -> "=> #{inspected}"
      _ -> "#{output}\n=> #{inspected}"
    end
  end

  defp format_error("", message), do: message
  defp format_error(output, message), do: "#{output}\n#{message}"
end
