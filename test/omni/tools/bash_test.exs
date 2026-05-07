defmodule Omni.Tools.BashTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.Bash

  @moduletag :tmp_dir

  defp tool(ctx, opts \\ []) do
    Bash.new(Keyword.merge([dir: ctx.tmp_dir], opts))
  end

  describe "new/1" do
    test "returns a tool with the bash name", ctx do
      assert %Omni.Tool{name: "bash"} = tool(ctx)
    end

    test "accepts timeout and max_output options", ctx do
      assert %Omni.Tool{} = tool(ctx, timeout: 60_000, max_output: 10_000)
    end

    test "accepts env option", ctx do
      assert %Omni.Tool{} = tool(ctx, env: [{"FOO", "bar"}])
    end

    test "accepts command_prefix option", ctx do
      assert %Omni.Tool{} = tool(ctx, command_prefix: "source .env")
    end

    test "raises on missing :dir" do
      assert_raise ArgumentError, ~r/missing required :dir/, fn ->
        Bash.new([])
      end
    end

    test "raises on non-existent :dir" do
      assert_raise ArgumentError, ~r/does not exist/, fn ->
        Bash.new(dir: "/nonexistent_path_xyz")
      end
    end

    test "raises on invalid :env entry", ctx do
      assert_raise ArgumentError, ~r/invalid :env entry/, fn ->
        tool(ctx, env: [{"FOO", 123}])
      end
    end
  end

  describe "schema" do
    test "has title and command properties", ctx do
      t = tool(ctx)
      assert get_in(t.input_schema, [:properties, :title])
      assert get_in(t.input_schema, [:properties, :command])
    end

    test "both fields are required", ctx do
      t = tool(ctx)
      assert Enum.sort(t.input_schema[:required]) == [:command, :title]
    end
  end

  describe "description" do
    test "includes shell and working directory", ctx do
      t = tool(ctx)
      assert t.description =~ ctx.tmp_dir
      {shell_exe, _} = Omni.Tools.Bash.Runner.resolve_shell([])
      assert t.description =~ Path.basename(shell_exe)
    end

    test "does not leak command prefix or env var names", ctx do
      t = tool(ctx, command_prefix: "source .env", env: [{"API_KEY", "secret"}])
      refute t.description =~ "source .env"
      refute t.description =~ "API_KEY"
    end
  end

  describe "call" do
    test "successful command returns output", ctx do
      t = tool(ctx)
      assert t.handler.(%{title: "test", command: "echo hello"}) =~ "hello"
    end

    test "returns '(no output)' for silent commands", ctx do
      t = tool(ctx)
      assert "(no output)" = t.handler.(%{title: "test", command: "true"})
    end

    test "raises on non-zero exit code", ctx do
      t = tool(ctx)

      assert_raise RuntimeError, ~r/exited with status 1/, fn ->
        t.handler.(%{title: "test", command: "exit 1"})
      end
    end

    test "includes output in error for non-zero exit", ctx do
      t = tool(ctx)

      assert_raise RuntimeError, ~r/something went wrong/, fn ->
        t.handler.(%{title: "test", command: "echo 'something went wrong'; exit 1"})
      end
    end

    test "raises on timeout with partial output", ctx do
      t = tool(ctx, timeout: 500)

      error =
        assert_raise RuntimeError, ~r/timed out/, fn ->
          t.handler.(%{title: "test", command: "echo before; sleep 60"})
        end

      assert error.message =~ "before"
    end

    test "env vars are available to commands", ctx do
      t = tool(ctx, env: [{"MY_VAR", "hello"}])
      assert t.handler.(%{title: "test", command: "echo $MY_VAR"}) =~ "hello"
    end

    test "command prefix is prepended", ctx do
      t = tool(ctx, command_prefix: "export PREFIX_VAR=yes")
      assert t.handler.(%{title: "test", command: "echo $PREFIX_VAR"}) =~ "yes"
    end
  end
end
