defmodule Omni.Tools.Repl.Sandbox do
  @moduledoc """
  Executes Elixir code in an isolated peer node.

  Each invocation starts a fresh Erlang peer node, evaluates the code, captures
  IO output and the raw return value, then stops the peer. Clean slate per
  execution — no state carries over between calls.

  The host's code paths are injected into the peer, so all compiled modules
  (including application dependencies) are available. In dev, `Mix.install/1` can
  add additional dependencies since each peer is a fresh VM.

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
      {:error, :timeout, %{output: "partial..."}}
      {:error, {:error, %ArithmeticError{}, stacktrace}, %{output: ""}}

  On success, `result` is the raw return value of the last expression (not
  inspected). On error, the second element is either `:timeout`, `:noconnection`,
  or a `{kind, reason, stacktrace}` triple from the caught exception.
  """

  @default_timeout 60_000
  @default_max_output 50_000

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
    timeout = config(opts, :timeout, @default_timeout)
    max_output = config(opts, :max_output, @default_max_output)
    setup = Keyword.get(opts, :setup)

    ensure_distributed!()
    {peer_pid, peer_node} = start_peer()
    init_peer(peer_node)

    # StringIO lives on the host so it's always accessible — on timeout we can
    # read partial output without an extra erpc call to the (possibly stuck) peer.
    {:ok, io_pid} = StringIO.open("")

    try do
      result = :erpc.call(peer_node, build_eval_fn(code, setup, io_pid), timeout)
      truncate_result(result, max_output)
    catch
      :error, {:erpc, :timeout} ->
        {_, output} = StringIO.contents(io_pid)
        {:error, :timeout, %{output: maybe_truncate(output, max_output)}}

      :error, {:erpc, :noconnection} ->
        {_, output} = StringIO.contents(io_pid)
        {:error, :noconnection, %{output: maybe_truncate(output, max_output)}}
    after
      StringIO.close(io_pid)
      safely_stop_peer(peer_pid)
    end
  end

  @doc """
  Enables distributed mode on the host VM if not already active.

  Peer nodes require the host to be distributed (`Node.alive?()`). When the
  VM was started without `--sname` / `--name`, this function starts EPMD and
  enables distribution with a unique short name.

  Called automatically by `run/2` on each invocation (idempotent). You may
  also call it explicitly at application boot to avoid flipping the VM into
  distributed mode during a request — that flip can invalidate any PID-based
  state (encoded tokens, cached process references, etc.) that was created
  before distribution was enabled.

      # In your Application.start/2:
      Omni.Tools.Repl.Sandbox.ensure_distributed!()
  """
  @spec ensure_distributed!() :: :ok
  def ensure_distributed! do
    unless Node.alive?() do
      ensure_epmd!()
      name = :"omni_repl_#{System.unique_integer([:positive])}"

      case Node.start(name, name_domain: :shortnames) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    :ok
  end

  defp build_eval_fn(code, setup, io_pid) do
    fn ->
      eval_setup(setup)

      Process.group_leader(self(), io_pid)

      try do
        {result, _bindings} = Code.eval_string(code)
        {_, output} = StringIO.contents(io_pid)
        {:ok, %{output: output, result: result}}
      catch
        kind, reason ->
          {_, output} = StringIO.contents(io_pid)
          {:error, {kind, reason, __STACKTRACE__}, %{output: output}}
      end
    end
  end

  defp eval_setup(nil), do: :ok
  defp eval_setup(code) when is_binary(code), do: Code.eval_string(code)
  defp eval_setup(items) when is_list(items), do: Enum.each(items, &eval_setup/1)
  defp eval_setup(ast), do: Code.eval_quoted(ast)

  defp init_peer(peer_node) do
    :erpc.call(peer_node, :code, :add_pathsa, [:code.get_path()])
    :erpc.call(peer_node, :application, :ensure_all_started, [:elixir])
    :erpc.call(peer_node, :logger, :set_primary_config, [:level, :warning])
  end

  defp ensure_epmd! do
    case :erl_epmd.names() do
      {:ok, _} -> :ok
      {:error, _} -> :os.cmd(~c"epmd -daemon")
    end
  end

  defp start_peer do
    id = System.unique_integer([:positive])

    opts =
      if :net_kernel.longnames() do
        %{name: ~c"omni_repl_#{id}", host: ~c"127.0.0.1", longnames: true}
      else
        %{name: :"omni_repl_#{id}"}
      end

    {:ok, pid, node} = :peer.start(opts)
    {pid, node}
  end

  defp safely_stop_peer(pid) do
    :peer.stop(pid)
  catch
    :exit, _ -> :ok
  end

  defp config(opts, key, default) do
    Keyword.get_lazy(opts, key, fn ->
      Application.get_env(:omni_tools, Omni.Tools.Repl, [])
      |> Keyword.get(key, default)
    end)
  end

  defp truncate_result({:ok, %{output: output, result: result}}, max) do
    {:ok, %{output: maybe_truncate(output, max), result: result}}
  end

  defp truncate_result({:error, reason, %{output: output}}, max) do
    {:error, reason, %{output: maybe_truncate(output, max)}}
  end

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
