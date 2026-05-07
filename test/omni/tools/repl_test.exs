defmodule Omni.Tools.Repl.TestExtension do
  @behaviour Omni.Tools.Repl.Extension

  @impl true
  def code(opts) do
    greeting = Keyword.get(opts, :greeting, "hello")

    quote do
      defmodule(TestExt, do: def(greet, do: unquote(greeting)))
    end
  end

  @impl true
  def description(_opts), do: "## TestExt\n- `TestExt.greet/0` — returns a greeting"
end

defmodule Omni.Tools.ReplTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.Repl
  alias Omni.Tools.Repl.Extension

  defp tool(opts \\ []) do
    Repl.new(opts)
  end

  describe "new/1" do
    test "returns a tool with the repl name" do
      assert %Omni.Tool{name: "repl"} = tool()
    end

    test "accepts timeout and max_output options" do
      t = tool(timeout: 30_000, max_output: 10_000)
      assert %Omni.Tool{} = t
    end

    test "accepts module-based extensions as {mod, opts} tuples" do
      t = tool(extensions: [{Omni.Tools.Repl.TestExtension, greeting: "hi"}])
      assert %Omni.Tool{} = t
    end

    test "accepts bare module extensions" do
      t = tool(extensions: [Omni.Tools.Repl.TestExtension])
      assert %Omni.Tool{} = t
    end

    test "accepts inline %Extension{} structs" do
      ext = Extension.new(description: "some info")
      t = tool(extensions: [ext])
      assert %Omni.Tool{} = t
    end

    test "accepts mixed extension forms" do
      t =
        tool(
          extensions: [
            {Omni.Tools.Repl.TestExtension, []},
            Extension.new(description: "extra info")
          ]
        )

      assert %Omni.Tool{} = t
    end

    test "raises on invalid extension form" do
      assert_raise ArgumentError, ~r/expected an %Extension{}/, fn ->
        tool(extensions: ["not valid"])
      end
    end
  end

  describe "schema" do
    test "has title and code properties" do
      t = tool()
      assert get_in(t.input_schema, [:properties, :title])
      assert get_in(t.input_schema, [:properties, :code])
    end

    test "both fields are required" do
      t = tool()
      assert Enum.sort(t.input_schema[:required]) == [:code, :title]
    end
  end

  describe "description" do
    test "includes key sections" do
      t = tool()
      assert t.description =~ "When to Use"
      assert t.description =~ "Environment"
      assert t.description =~ "Output"
    end

    test "includes extension descriptions" do
      t = tool(extensions: [{Omni.Tools.Repl.TestExtension, []}])
      assert t.description =~ "TestExt"
      assert t.description =~ "greet"
    end

    test "omits nil and empty descriptions from extensions" do
      ext_nil = Extension.new(code: "nil")
      ext_empty = Extension.new(code: "nil", description: "")
      ext_present = Extension.new(description: "Visible description")

      t = tool(extensions: [ext_nil, ext_empty, ext_present])
      assert t.description =~ "Visible description"
    end
  end

  describe "call" do
    test "successful code execution" do
      t = tool()
      assert "=> 3" = t.handler.(%{title: "test", code: "1 + 2"})
    end

    test "captures IO output" do
      t = tool()
      result = t.handler.(%{title: "test", code: ~S|IO.puts("hello")|})
      assert result =~ "hello"
      assert result =~ "=> :ok"
    end

    test "raises on error" do
      t = tool()

      assert_raise RuntimeError, fn ->
        t.handler.(%{title: "test", code: "1 / 0"})
      end
    end

    test "raises on timeout" do
      t = tool(timeout: 500)

      assert_raise RuntimeError, ~r/timed out/, fn ->
        t.handler.(%{title: "test", code: "Process.sleep(:infinity)"})
      end
    end

    test "extensions inject code into sandbox" do
      t = tool(extensions: [{Omni.Tools.Repl.TestExtension, greeting: "hi there"}])
      assert "=> \"hi there\"" = t.handler.(%{title: "test", code: "TestExt.greet()"})
    end
  end
end
