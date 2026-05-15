defmodule Omni.Tools.Repl.SandboxTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.Repl.Sandbox

  describe "successful execution" do
    test "evaluates expression and returns raw result" do
      assert {:ok, %{output: "", result: 3}} = Sandbox.run("1 + 2")
    end

    test "captures IO output" do
      assert {:ok, %{output: "hello\n", result: :ok}} = Sandbox.run(~S|IO.puts("hello")|)
    end

    test "captures both IO output and return value" do
      code = ~S"""
      IO.puts("computing...")
      Enum.sum(1..10)
      """

      assert {:ok, %{output: "computing...\n", result: 55}} = Sandbox.run(code)
    end

    test "empty string evaluates to nil" do
      assert {:ok, %{output: "", result: nil}} = Sandbox.run("")
    end

    test "returns raw data structures" do
      assert {:ok, %{result: [1, 2, 3]}} = Sandbox.run("[1, 2, 3]")
      assert {:ok, %{result: %{a: 1}}} = Sandbox.run("%{a: 1}")
      assert {:ok, %{result: {:ok, "hello"}}} = Sandbox.run(~S|{:ok, "hello"}|)
    end

    test "captures IO from spawned processes" do
      code = ~S"""
      task = Task.async(fn -> IO.puts("from child") end)
      Task.await(task)
      """

      assert {:ok, %{output: "from child\n"}} = Sandbox.run(code)
    end

    test "can define and use modules" do
      code = """
      defmodule Greeter do
        def hello(name), do: "Hello, \#{name}!"
      end
      Greeter.hello("world")
      """

      assert {:ok, %{result: "Hello, world!"}} = Sandbox.run(code)
    end
  end

  describe "error handling" do
    test "runtime error returns exception triple" do
      assert {:error, {:error, :badarith, _stacktrace}, %{output: ""}} =
               Sandbox.run("1 / 0")
    end

    test "syntax error returns exception triple" do
      assert {:error, {kind, _reason, _stacktrace}, %{output: ""}} =
               Sandbox.run("if true do")

      assert kind in [:error, :throw]
    end

    test "captures output produced before an error" do
      code = ~S"""
      IO.puts("before")
      raise "boom"
      """

      assert {:error, {:error, %RuntimeError{message: "boom"}, _}, %{output: "before\n"}} =
               Sandbox.run(code)
    end

    test "catches throw" do
      assert {:error, {:throw, :foo, _stacktrace}, %{output: ""}} = Sandbox.run("throw(:foo)")
    end

    test "catches exit" do
      assert {:error, {:exit, :bar, _stacktrace}, %{output: ""}} = Sandbox.run("exit(:bar)")
    end

    test "handles peer crash gracefully" do
      assert {:error, :noconnection, %{output: ""}} = Sandbox.run("System.halt(1)")
    end
  end

  describe "timeout" do
    test "returns timeout error when execution exceeds limit" do
      assert {:error, :timeout, _} =
               Sandbox.run("Process.sleep(:infinity)", timeout: 500)
    end

    test "returns timeout error" do
      code = ~S"""
      IO.puts("before sleep")
      Process.sleep(:infinity)
      """

      assert {:error, :timeout, %{output: _}} = Sandbox.run(code, timeout: 500)
    end

    test "does not timeout for fast code" do
      assert {:ok, _} = Sandbox.run("1 + 1", timeout: 5_000)
    end
  end

  describe "output truncation" do
    test "truncates output exceeding max_output" do
      code = ~s|IO.write(String.duplicate("x", 10_000))|

      assert {:ok, %{output: output}} = Sandbox.run(code, max_output: 100)
      assert byte_size(output) < 200
      assert output =~ "truncated"
    end

    test "does not truncate when within limits" do
      assert {:ok, %{output: output}} = Sandbox.run(~s|IO.write("short")|, max_output: 50_000)
      refute output =~ "truncated"
    end
  end

  describe "setup option" do
    test "setup code is available to user code" do
      setup = """
      defmodule SetupHelper do
        def greet, do: "from setup"
      end
      """

      assert {:ok, %{result: "from setup"}} =
               Sandbox.run("SetupHelper.greet()", setup: setup)
    end

    test "setup IO output is not included in captured output" do
      setup = ~S|IO.puts("setup noise")|

      ExUnit.CaptureIO.capture_io(fn ->
        assert {:ok, %{output: output}} =
                 Sandbox.run(~S|IO.puts("user output")|, setup: setup)

        assert output == "user output\n"
        refute output =~ "setup noise"
      end)
    end
  end

  describe "AST setup" do
    test "AST setup defines modules available to user code" do
      setup =
        quote do
          defmodule(ASTHelper, do: def(greet, do: "from AST"))
        end

      assert {:ok, %{result: "from AST"}} =
               Sandbox.run("ASTHelper.greet()", setup: setup)
    end

    test "AST setup IO output is not captured" do
      setup =
        quote do
          IO.puts("ast noise")
        end

      ExUnit.CaptureIO.capture_io(fn ->
        assert {:ok, %{output: output}} =
                 Sandbox.run(~S|IO.puts("user output")|, setup: setup)

        assert output == "user output\n"
        refute output =~ "ast noise"
      end)
    end

    test "list of mixed setup items evaluated in order" do
      string_setup = "defmodule(SetupA, do: def(val, do: :a))"

      ast_setup =
        quote do
          defmodule(SetupB, do: def(val, do: :b))
        end

      assert {:ok, %{result: {:a, :b}}} =
               Sandbox.run("{SetupA.val(), SetupB.val()}", setup: [string_setup, ast_setup])
    end
  end

  describe "clean environment" do
    test "modules defined in one run are not available in the next" do
      code1 = """
      defmodule Ephemeral do
        def value, do: 42
      end
      Ephemeral.value()
      """

      assert {:ok, %{result: 42}} = Sandbox.run(code1)

      assert {:error, {:error, :undef, _}, _} = Sandbox.run("Ephemeral.value()")
    end
  end

  describe "Mix.install" do
    @tag timeout: 120_000
    test "can use Mix.install to add dependencies" do
      if Code.ensure_loaded?(Mix) do
        code = """
        Mix.install([{:jason, "~> 1.4"}])
        Jason.encode!(%{hello: "world"})
        """

        assert {:ok, %{result: result}} = Sandbox.run(code, timeout: 120_000)
        assert result =~ "hello"
      end
    end
  end
end
