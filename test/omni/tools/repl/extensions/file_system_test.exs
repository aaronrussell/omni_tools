defmodule Omni.Tools.Repl.Extensions.FileSystemTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.FileSystem.FS
  alias Omni.Tools.Repl
  alias Omni.Tools.Repl.Extensions.FileSystem, as: FSExtension

  @moduletag :tmp_dir

  defp fs(ctx, opts \\ []) do
    FS.new(Keyword.merge([base_dir: ctx.tmp_dir], opts))
  end

  defp repl(ctx, fs_opts \\ []) do
    Repl.new(extensions: [{FSExtension, fs: fs(ctx, fs_opts)}])
  end

  defp run(tool, code) do
    tool.handler.(%{title: "test", code: code})
  end

  describe "code/1" do
    test "raises when :fs option is missing" do
      assert_raise KeyError, ~r/:fs/, fn ->
        FSExtension.code([])
      end
    end
  end

  describe "description/1" do
    test "read-write includes all five functions", ctx do
      desc = FSExtension.description(fs: fs(ctx))
      assert desc =~ "Files.read"
      assert desc =~ "Files.write"
      assert desc =~ "Files.patch"
      assert desc =~ "Files.list"
      assert desc =~ "Files.delete"
    end

    test "read-only includes only read and list", ctx do
      desc = FSExtension.description(fs: fs(ctx, read_only: true))
      assert desc =~ "Files.read"
      assert desc =~ "Files.list"
      refute desc =~ "Files.write"
      refute desc =~ "Files.patch"
      refute desc =~ "Files.delete"
    end

    test "flat mode excludes subdirectory paths", ctx do
      nested = FSExtension.description(fs: fs(ctx))
      flat = FSExtension.description(fs: fs(ctx, nested: false))
      refute nested == flat
    end
  end

  describe "sandbox integration" do
    test "write and read round-trip", ctx do
      t = repl(ctx)
      result = run(t, ~S|Files.write("hello.txt", "world"); Files.read("hello.txt")|)
      assert result =~ "world"
    end

    test "write returns an Entry", ctx do
      t = repl(ctx)
      result = run(t, ~S|Files.write("test.txt", "abc")|)
      assert result =~ "test.txt"
      assert result =~ "Entry"
    end

    test "list returns entries after write", ctx do
      File.write!(Path.join(ctx.tmp_dir, "existing.txt"), "content")
      t = repl(ctx)
      result = run(t, ~S|Files.list()|)
      assert result =~ "existing.txt"
    end

    test "list returns empty list when no files", ctx do
      t = repl(ctx)
      result = run(t, ~S|Files.list()|)
      assert result =~ "[]"
    end

    test "patch modifies file content", ctx do
      File.write!(Path.join(ctx.tmp_dir, "greet.txt"), "hello world")
      t = repl(ctx)
      result = run(t, ~S|Files.patch("greet.txt", "hello", "goodbye"); Files.read("greet.txt")|)
      assert result =~ "goodbye world"
    end

    test "delete removes a file", ctx do
      path = Path.join(ctx.tmp_dir, "doomed.txt")
      File.write!(path, "bye")
      t = repl(ctx)
      result = run(t, ~S|Files.delete("doomed.txt")|)
      assert result =~ ":ok"
      refute File.exists?(path)
    end

    test "nested paths", ctx do
      t = repl(ctx)
      result = run(t, ~S|Files.write("sub/deep.txt", "nested"); Files.read("sub/deep.txt")|)
      assert result =~ "nested"
    end

    test "read-only raises on write", ctx do
      t = repl(ctx, read_only: true)

      assert_raise RuntimeError, ~r/read-only/, fn ->
        run(t, ~S|Files.write("nope.txt", "data")|)
      end
    end

    test "read-only allows read", ctx do
      File.write!(Path.join(ctx.tmp_dir, "readable.txt"), "allowed")
      t = repl(ctx, read_only: true)
      result = run(t, ~S|Files.read("readable.txt")|)
      assert result =~ "allowed"
    end

    test "read missing file raises", ctx do
      t = repl(ctx)

      assert_raise RuntimeError, ~r/not found/, fn ->
        run(t, ~S|Files.read("nope.txt")|)
      end
    end

    test "patch no match raises", ctx do
      File.write!(Path.join(ctx.tmp_dir, "stable.txt"), "unchanged")
      t = repl(ctx)

      assert_raise RuntimeError, ~r/not found/, fn ->
        run(t, ~S|Files.patch("stable.txt", "missing", "replacement")|)
      end
    end
  end
end
