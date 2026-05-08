defmodule Omni.Tools.Bash do
  @moduledoc """
  An `Omni.Tool` for executing shell commands.

  Runs commands in a configured shell (bash by default, falling back to sh)
  with a working directory, optional environment variables, and timeout.

      tool = Omni.Tools.Bash.new(dir: "/path/to/workspace")
      tool = Omni.Tools.Bash.new(dir: "/app", timeout: 60_000, env: [{"NODE_ENV", "test"}])

  The tool delegates execution to `Omni.Tools.Bash.Runner`, which can also
  be used independently of the tool machinery.

  ## Options

  - `:dir` (required) — working directory. Must exist at init time.
  - `:env` — extra environment variables as `[{String.t(), String.t()}]`.
    Merged additively with the inherited environment. Default `[]`.
  - `:timeout` — execution timeout in milliseconds. Default `30_000`.
  - `:max_output` — output truncation limit in bytes. Tail-biased, snapped to
    line boundaries. Default `50_000`.
  - `:shell` — explicit shell as `{executable, args}` tuple.
    Default: auto-resolved (bash then sh fallback).
  - `:command_prefix` — string prepended to every command. Default `nil`.
  """

  use Omni.Tool, name: "bash"

  alias Omni.Tools.Bash.Runner

  @defaults [
    env: [],
    timeout: 30_000,
    max_output: 50_000,
    command_prefix: nil
  ]

  @impl Omni.Tool
  def init(opts) do
    opts =
      @defaults
      |> Keyword.merge(Application.get_env(:omni_tools, __MODULE__, []))
      |> Keyword.merge(opts || [])

    dir = Keyword.get(opts, :dir) || raise ArgumentError, "missing required :dir option"

    unless File.dir?(dir) do
      raise ArgumentError, ":dir does not exist or is not a directory: #{inspect(dir)}"
    end

    unless Path.type(dir) == :absolute do
      raise ArgumentError, ":dir must be an absolute path, got: #{inspect(dir)}"
    end

    [
      dir: Path.expand(dir),
      shell: Runner.resolve_shell(opts),
      env: validate_env!(Keyword.fetch!(opts, :env)),
      timeout: Keyword.fetch!(opts, :timeout),
      max_output: Keyword.fetch!(opts, :max_output),
      command_prefix: Keyword.fetch!(opts, :command_prefix)
    ]
  end

  @impl Omni.Tool
  def schema(_state) do
    import Omni.Schema

    object(
      %{
        title:
          string(
            description:
              "Brief title describing the command's purpose in active voice, e.g. 'List project files'"
          ),
        command: string(description: "Shell command to execute")
      },
      required: [:title, :command]
    )
  end

  @impl Omni.Tool
  def description(state) do
    {shell_exe, _args} = Keyword.fetch!(state, :shell)
    shell_name = Path.basename(shell_exe)
    dir = Keyword.fetch!(state, :dir)
    max_output = Keyword.fetch!(state, :max_output)

    """
    Execute shell commands in a #{shell_name} shell.

    ## Environment
    - Working directory: `#{dir}`
    - Shell: `#{shell_exe}`

    ## Output
    - stdout and stderr are merged into a single output stream
    - Output is truncated to the last #{max_output / 1024}KB
    """
  end

  @impl Omni.Tool
  def call(%{command: command}, state) do
    shell = Keyword.fetch!(state, :shell)

    runner_opts = Keyword.take(state, [:dir, :env, :timeout, :max_output, :command_prefix])

    case Runner.run(command, shell, runner_opts) do
      {:ok, %{output: ""}} ->
        "(no output)"

      {:ok, %{output: output}} ->
        output

      {:error, :nonzero, %{output: output, exit_code: code}} ->
        raise format_error(output, "Command exited with status #{code}")

      {:error, :timeout, %{output: output}} ->
        raise format_error(output, "Command timed out")
    end
  end

  defp format_error("", message), do: message
  defp format_error(output, message), do: "#{output}\n#{message}"

  defp validate_env!(env) do
    Enum.each(env, fn
      {k, v} when is_binary(k) and is_binary(v) ->
        :ok

      other ->
        raise ArgumentError,
              "invalid :env entry: expected {String.t(), String.t()}, got: #{inspect(other)}"
    end)

    env
  end
end
