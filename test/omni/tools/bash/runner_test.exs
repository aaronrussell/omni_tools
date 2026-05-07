defmodule Omni.Tools.Bash.RunnerTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.Bash.Runner

  @moduletag :tmp_dir

  @shell Runner.resolve_shell([])

  defp run(command, ctx, opts \\ []) do
    Runner.run(command, @shell, Keyword.merge([dir: ctx.tmp_dir], opts))
  end

  describe "successful execution" do
    test "runs a simple command and returns output", ctx do
      assert {:ok, %{output: "hello\n", exit_code: 0}} = run("echo hello", ctx)
    end

    test "returns empty output for silent commands", ctx do
      assert {:ok, %{output: "", exit_code: 0}} = run("true", ctx)
    end

    test "merges stdout and stderr", ctx do
      assert {:ok, %{output: output, exit_code: 0}} =
               run("echo out; echo err >&2", ctx)

      assert output =~ "out"
      assert output =~ "err"
    end

    test "respects working directory", ctx do
      File.write!(Path.join(ctx.tmp_dir, "marker.txt"), "found it")

      assert {:ok, %{output: "found it", exit_code: 0}} =
               run("cat marker.txt", ctx)
    end

    test "applies environment variables", ctx do
      assert {:ok, %{output: "hello\n", exit_code: 0}} =
               run("echo $MY_VAR", ctx, env: [{"MY_VAR", "hello"}])
    end

    test "applies command prefix", ctx do
      assert {:ok, %{output: "bar\n", exit_code: 0}} =
               run("echo $FOO", ctx, command_prefix: "export FOO=bar")
    end
  end

  describe "error handling" do
    test "returns nonzero exit code as error", ctx do
      assert {:error, :nonzero, %{output: _, exit_code: 1}} = run("exit 1", ctx)
    end

    test "preserves output with nonzero exit code", ctx do
      assert {:error, :nonzero, %{output: output, exit_code: 42}} =
               run("echo fail; exit 42", ctx)

      assert output =~ "fail"
    end

    test "handles command not found", ctx do
      assert {:error, :nonzero, %{output: output, exit_code: _code}} =
               run("nonexistent_command_xyz_12345", ctx)

      assert output =~ "not found"
    end
  end

  describe "timeout" do
    test "returns timeout error for long-running commands", ctx do
      assert {:error, :timeout, %{output: _}} = run("sleep 60", ctx, timeout: 500)
    end

    test "captures partial output on timeout", ctx do
      assert {:error, :timeout, %{output: output}} =
               run("echo before_timeout; sleep 60", ctx, timeout: 500)

      assert output =~ "before_timeout"
    end

    test "does not timeout for fast commands", ctx do
      assert {:ok, %{output: "fast\n", exit_code: 0}} =
               run("echo fast", ctx, timeout: 5_000)
    end
  end

  describe "output truncation" do
    test "truncates large output (tail-biased)", ctx do
      assert {:ok, %{output: output, exit_code: 0}} =
               run("seq 1 10000", ctx, max_output: 200)

      assert output =~ "truncated"
      assert output =~ "10000"
      refute output =~ "\n1\n"
    end

    test "does not truncate when within limits", ctx do
      assert {:ok, %{output: output, exit_code: 0}} =
               run("echo short", ctx, max_output: 50_000)

      refute output =~ "truncated"
    end

    test "snaps to line boundary", ctx do
      assert {:ok, %{output: output, exit_code: 0}} =
               run("seq 1 10000", ctx, max_output: 200)

      lines =
        output
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "..."))

      Enum.each(lines, fn line ->
        assert String.match?(line, ~r/^\d+$/)
      end)
    end
  end

  describe "resolve_shell/1" do
    test "returns bash or sh by default" do
      {exe, ["-c"]} = Runner.resolve_shell([])
      assert exe in ["/bin/bash", "/bin/sh"]
    end

    test "accepts explicit shell option" do
      assert {"/bin/sh", ["-c"]} = Runner.resolve_shell(shell: {"/bin/sh", ["-c"]})
    end

    test "raises on invalid shell option" do
      assert_raise ArgumentError, ~r/invalid :shell option/, fn ->
        Runner.resolve_shell(shell: "not a tuple")
      end
    end
  end
end
