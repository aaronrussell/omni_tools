defmodule Omni.Tools.Repl.Sandbox do
  @moduledoc """
  Executes Elixir code in an isolated peer node.

  Each invocation starts a fresh Erlang peer node, evaluates the code, captures
  IO output and the raw return value, then stops the peer. Clean slate per
  execution — no state carries over between calls.

  The host's code paths are injected into the peer, so all compiled modules
  (including application dependencies) are available. In dev, `Mix.install/1` can
  add additional dependencies since each peer is a fresh VM.

  Communication with the peer uses the `:peer` module's stdio control channel,
  so no Erlang distribution (EPMD) is required.

  The sandbox executes arbitrary code with full system access. It is best-effort
  isolation, not a security boundary. For trusted use cases only: agent-driven
  experimentation, scratchpad computation — not adversarial input.

  ## Options

    * `:timeout` - execution timeout in milliseconds (default: `60_000`)
    * `:max_output` - truncation limit in bytes (default: `50_000`)
    * `:setup` - code evaluated in the peer before the user's code.
      Setup runs before IO capture begins, so its output is not included.
      Accepts a string, quoted AST, or a list of either.

  ## Return values

      {:ok, %{output: "hello\\n", result: :ok}}
      {:error, :timeout, %{output: ""}}
      {:error, {:error, %ArithmeticError{}, stacktrace}, %{output: ""}}

  On success, `result` is the raw return value of the last expression (not
  inspected). On error, the second element is either `:timeout`, `:noconnection`,
  or a `{kind, reason, stacktrace}` triple from the caught exception.
  """

  @default_timeout 60_000
  @default_max_output 50_000

  @typedoc "Result of a sandbox evaluation — success, timeout/disconnect, or exception."
  @type result ::
          {:ok, %{output: String.t(), result: term()}}
          | {:error, :timeout | :noconnection, %{output: String.t()}}
          | {:error, {atom(), term(), Exception.stacktrace()}, %{output: String.t()}}

  @doc """
  Evaluates `code` in a fresh peer node and returns the captured output
  and raw return value.
  """
  @spec run(String.t(), keyword()) :: result()
  def run(code, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_output = Keyword.get(opts, :max_output, @default_max_output)
    setup = Keyword.get(opts, :setup)

    peer_pid = start_peer()
    init_peer(peer_pid)

    try do
      result = :peer.call(peer_pid, __MODULE__, :eval_peer, [code, setup], timeout)
      truncate_result(result, max_output)
    catch
      :exit, {:timeout, _} ->
        {:error, :timeout, %{output: ""}}

      :exit, _ ->
        {:error, :noconnection, %{output: ""}}
    after
      safely_stop_peer(peer_pid)
    end
  end

  @doc false
  def eval_peer(code, setup) do
    eval_setup(setup)

    {:ok, io} = StringIO.open("")
    Process.group_leader(self(), io)

    try do
      {result, _bindings} = Code.eval_string(code)
      {_, output} = StringIO.contents(io)
      {:ok, %{output: output, result: result}}
    catch
      kind, reason ->
        {_, output} = StringIO.contents(io)
        {:error, {kind, reason, __STACKTRACE__}, %{output: output}}
    after
      StringIO.close(io)
    end
  end

  defp eval_setup(nil), do: :ok
  defp eval_setup(code) when is_binary(code), do: Code.eval_string(code)
  defp eval_setup(items) when is_list(items), do: Enum.each(items, &eval_setup/1)
  defp eval_setup(ast), do: Code.eval_quoted(ast)

  defp init_peer(peer_pid) do
    :peer.call(peer_pid, :code, :add_pathsa, [:code.get_path()])
    :peer.call(peer_pid, :application, :ensure_all_started, [:elixir])
    :peer.call(peer_pid, :logger, :set_primary_config, [:level, :warning])
  end

  defp start_peer do
    {:ok, pid, _node} = :peer.start(%{connection: :standard_io})
    pid
  end

  defp safely_stop_peer(pid) do
    Process.exit(pid, :kill)
  end

  defp truncate_result({:ok, %{output: output, result: result}}, max) do
    {:ok, %{output: maybe_truncate(output, max), result: result}}
  end

  defp truncate_result({:error, reason, %{output: output}}, max) do
    {:error, reason, %{output: maybe_truncate(output, max)}}
  end

  defp maybe_truncate(string, :infinity), do: string
  defp maybe_truncate(string, max) when byte_size(string) <= max, do: string

  defp maybe_truncate(string, max) do
    truncated = binary_part(string, 0, max)
    total = byte_size(string)
    truncated <> "\n...(truncated, showing first #{format_bytes(max)} of #{format_bytes(total)})"
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
