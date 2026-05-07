defmodule Omni.Tools.Bash.Runner do
  @moduledoc """
  Executes shell commands via a Port and returns captured output.

  Each invocation spawns a new shell process, captures merged stdout/stderr,
  and returns the output alongside the exit code. No state carries over
  between calls.

      Runner.run("echo hello", {"/bin/bash", ["-c"]}, dir: "/tmp")
      #=> {:ok, %{output: "hello\\n", exit_code: 0}}

      Runner.run("exit 1", {"/bin/bash", ["-c"]}, dir: "/tmp")
      #=> {:error, :nonzero, %{output: "", exit_code: 1}}

  The runner executes arbitrary shell commands with full system access. It is
  not a security boundary — OS-level sandboxing (containers, restricted users)
  is the caller's responsibility.

  ## Options

    * `:dir` (required) — working directory for the command
    * `:env` — extra environment variables as `[{String.t(), String.t()}]`,
      merged additively with the inherited environment. Default `[]`
    * `:timeout` — execution timeout in milliseconds. Default `30_000`
    * `:max_output` — output truncation limit in bytes. Tail-biased, snapped
      to line boundaries. Default `50_000`
    * `:command_prefix` — string prepended to every command. Default `nil`

  ## Return values

      {:ok, %{output: "hello\\n", exit_code: 0}}
      {:error, :nonzero, %{output: "error msg\\n", exit_code: 1}}
      {:error, :timeout, %{output: "partial..."}}

  On success, `exit_code` is always `0`. On a non-zero exit, the output
  captured up to that point is included. On timeout, partial output
  collected before the deadline is returned.
  """

  @default_timeout 30_000
  @default_max_output 50_000

  @type result ::
          {:ok, %{output: String.t(), exit_code: 0}}
          | {:error, :nonzero, %{output: String.t(), exit_code: pos_integer()}}
          | {:error, :timeout, %{output: String.t()}}

  @doc """
  Executes `command` in the given `shell` and returns captured output.

  The `shell` argument is a `{executable, args}` tuple — the command string
  is appended to `args` when spawning the port.
  """
  @spec run(String.t(), {String.t(), [String.t()]}, keyword()) :: result()
  def run(command, {shell_exe, shell_args}, opts \\ []) do
    dir = Keyword.fetch!(opts, :dir)
    env = opts |> Keyword.get(:env, []) |> to_port_env()
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_output = Keyword.get(opts, :max_output, @default_max_output)
    prefix = Keyword.get(opts, :command_prefix)

    full_command = build_command(command, prefix)

    port =
      Port.open({:spawn_executable, shell_exe}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:args, shell_args ++ [full_command]},
        {:cd, dir},
        {:env, env}
      ])

    deadline = System.monotonic_time(:millisecond) + timeout

    case collect(port, deadline, []) do
      {:ok, output, exit_code} ->
        output = truncate_tail(output, max_output)

        if exit_code == 0 do
          {:ok, %{output: output, exit_code: 0}}
        else
          {:error, :nonzero, %{output: output, exit_code: exit_code}}
        end

      {:timeout, acc} ->
        close_port(port)
        remaining = drain_port(port, [])
        all = Enum.reverse(acc) ++ remaining
        output = IO.iodata_to_binary(all)
        output = truncate_tail(output, max_output)
        {:error, :timeout, %{output: output}}
    end
  end

  @doc """
  Resolves the shell to use for command execution.

  Checks in order: explicit `:shell` option, `/bin/bash`, `/bin/sh`.
  Returns a `{executable, args}` tuple suitable for `Port.open/2`.

  Raises `ArgumentError` if no usable shell is found or the option is invalid.

      Runner.resolve_shell([])
      #=> {"/bin/bash", ["-c"]}

      Runner.resolve_shell(shell: {"/bin/zsh", ["-c"]})
      #=> {"/bin/zsh", ["-c"]}
  """
  @spec resolve_shell(keyword()) :: {String.t(), [String.t()]}
  def resolve_shell(opts) do
    case Keyword.get(opts, :shell) do
      {exe, args} when is_binary(exe) and is_list(args) ->
        {exe, args}

      nil ->
        cond do
          File.exists?("/bin/bash") -> {"/bin/bash", ["-c"]}
          File.exists?("/bin/sh") -> {"/bin/sh", ["-c"]}
          true -> raise ArgumentError, "no shell found: /bin/bash and /bin/sh both missing"
        end

      other ->
        raise ArgumentError,
              "invalid :shell option: expected {executable, args} tuple, got: #{inspect(other)}"
    end
  end

  # ── Port communication ───────────────────────────────────────────

  defp collect(port, deadline, acc) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, chunk}} ->
        collect(port, deadline, [chunk | acc])

      {^port, {:exit_status, code}} ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, output, code}
    after
      remaining ->
        {:timeout, acc}
    end
  end

  defp drain_port(port, acc) do
    receive do
      {^port, {:data, chunk}} -> drain_port(port, [chunk | acc])
      {^port, {:exit_status, _}} -> acc |> Enum.reverse()
    after
      0 -> acc |> Enum.reverse()
    end
  end

  defp close_port(port) do
    Port.close(port)
  catch
    :error, :badarg -> :ok
  end

  # ── Command building ─────────────────────────────────────────────

  defp build_command(command, nil), do: command
  defp build_command(command, prefix), do: prefix <> "\n" <> command

  defp to_port_env(env) do
    Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
  end

  # ── Output truncation ───────────────────────────────────────────

  defp truncate_tail(output, max) when byte_size(output) <= max, do: output

  defp truncate_tail(output, max) do
    total = byte_size(output)
    skip = total - max
    tail = binary_part(output, skip, max)

    snapped =
      case :binary.match(tail, "\n") do
        {pos, 1} -> binary_part(tail, pos + 1, byte_size(tail) - pos - 1)
        :nomatch -> tail
      end

    "...(truncated, showing last #{format_bytes(byte_size(snapped))} of #{format_bytes(total)})\n#{snapped}"
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
