defmodule Omni.Tools.FileSystemTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.FileSystem

  @moduletag :tmp_dir

  defp tool(ctx, opts \\ []) do
    FileSystem.new(Keyword.merge([base_dir: ctx.tmp_dir], opts))
  end

  describe "new/1" do
    test "returns an %Omni.Tool{} with the right name", ctx do
      tool = tool(ctx)
      assert %Omni.Tool{name: "file_system"} = tool
    end
  end

  describe "schema" do
    test "read-only schema only includes read and list", ctx do
      tool = tool(ctx, read_only: true)
      commands = get_in(tool.input_schema, [:properties, :command, :enum])
      assert commands == ["read", "list"]
    end

    test "full schema includes all commands", ctx do
      tool = tool(ctx)
      commands = get_in(tool.input_schema, [:properties, :command, :enum])
      assert commands == ["read", "list", "write", "patch", "delete"]
    end
  end

  describe "description" do
    test "mentions read-only when configured", ctx do
      tool = tool(ctx, read_only: true)
      assert tool.description =~ "Read-only"
    end

    test "mentions read-write when configured", ctx do
      tool = tool(ctx)
      assert tool.description =~ "Read-write"
    end

    test "mentions flat mode", ctx do
      tool = tool(ctx, nested: false)
      assert tool.description =~ "Flat mode"
    end

    test "mentions subdirectories when nested", ctx do
      tool = tool(ctx)
      assert tool.description =~ "Subdirectories are allowed"
    end

    test "includes base_dir path", ctx do
      tool = tool(ctx)
      assert tool.description =~ ctx.tmp_dir
    end
  end

  describe "call dispatch" do
    test "read returns file content", ctx do
      File.write!(Path.join(ctx.tmp_dir, "hello.txt"), "world")
      assert tool(ctx).handler.(%{command: "read", id: "hello.txt"}) == "world"
    end

    test "list returns formatted entries", ctx do
      File.write!(Path.join(ctx.tmp_dir, "a.json"), "{}")

      result = tool(ctx).handler.(%{command: "list"})
      assert result =~ "a.json"
      assert result =~ "application/json"
      assert result =~ "bytes"
    end

    test "list returns 'No files' when empty", ctx do
      assert tool(ctx).handler.(%{command: "list"}) == "No files"
    end

    test "write creates file and returns confirmation", ctx do
      result = tool(ctx).handler.(%{command: "write", id: "new.txt", content: "hello"})
      assert result =~ "Wrote new.txt"
      assert result =~ "bytes"
      assert File.read!(Path.join(ctx.tmp_dir, "new.txt")) == "hello"
    end

    test "patch replaces and returns confirmation", ctx do
      File.write!(Path.join(ctx.tmp_dir, "file.txt"), "hello world")

      result =
        tool(ctx).handler.(%{
          command: "patch",
          id: "file.txt",
          search: "hello",
          replace: "goodbye"
        })

      assert result =~ "Patched file.txt"
      assert File.read!(Path.join(ctx.tmp_dir, "file.txt")) == "goodbye world"
    end

    test "delete removes file and returns confirmation", ctx do
      File.write!(Path.join(ctx.tmp_dir, "temp.txt"), "bye")

      result = tool(ctx).handler.(%{command: "delete", id: "temp.txt"})
      assert result == "Deleted temp.txt"
      refute File.exists?(Path.join(ctx.tmp_dir, "temp.txt"))
    end

    test "read-only write raises", ctx do
      assert_raise RuntimeError, ~r/read-only/, fn ->
        tool(ctx, read_only: true).handler.(%{command: "write", id: "x.txt", content: "x"})
      end
    end

    test "missing required param raises", ctx do
      assert_raise RuntimeError, ~r/write requires :content/, fn ->
        tool(ctx).handler.(%{command: "write", id: "x.txt"})
      end
    end
  end
end
