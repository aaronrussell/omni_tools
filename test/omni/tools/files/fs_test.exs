defmodule Omni.Tools.Files.FSTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.Files.{Entry, FS}

  @moduletag :tmp_dir

  defp fs(ctx, opts \\ []) do
    FS.new(Keyword.merge([base_dir: ctx.tmp_dir], opts))
  end

  # -- FS.new/1 ---------------------------------------------------------------

  describe "new/1" do
    test "accepts valid opts", ctx do
      assert %FS{base_dir: _, read_only?: false, nested?: true} = fs(ctx)
    end

    test "accepts read_only and nested opts", ctx do
      result = fs(ctx, read_only: true, nested: false)
      assert result.read_only? == true
      assert result.nested? == false
    end

    test "raises on missing :base_dir" do
      assert_raise ArgumentError, ~r/missing required :base_dir/, fn ->
        FS.new([])
      end
    end

    test "raises on relative :base_dir" do
      assert_raise ArgumentError, ~r/must be an absolute path/, fn ->
        FS.new(base_dir: "relative/path")
      end
    end

    test "raises on non-existent :base_dir" do
      assert_raise ArgumentError, ~r/does not exist/, fn ->
        FS.new(base_dir: "/nonexistent/path/#{System.unique_integer()}")
      end
    end
  end

  # -- resolve/2 --------------------------------------------------------------

  describe "resolve/2" do
    test "accepts valid id in nested mode", ctx do
      assert {:ok, path} = FS.resolve(fs(ctx), "sub/file.txt")
      assert path == Path.join(ctx.tmp_dir, "sub/file.txt")
    end

    test "accepts valid id in flat mode", ctx do
      assert {:ok, path} = FS.resolve(fs(ctx, nested: false), "file.txt")
      assert path == Path.join(ctx.tmp_dir, "file.txt")
    end

    test "accepts dotfiles in both modes", ctx do
      assert {:ok, _} = FS.resolve(fs(ctx), ".hidden")
      assert {:ok, _} = FS.resolve(fs(ctx, nested: false), ".hidden")
    end

    test "accepts dot-directories in nested mode", ctx do
      assert {:ok, _} = FS.resolve(fs(ctx), ".config/settings.json")
    end

    test "rejects empty id", ctx do
      assert {:error, {:invalid_id, _}} = FS.resolve(fs(ctx), "")
    end

    test "rejects absolute id", ctx do
      assert {:error, {:invalid_id, _}} = FS.resolve(fs(ctx), "/etc/passwd")
    end

    test "rejects tilde-prefixed id", ctx do
      assert {:error, {:invalid_id, _}} = FS.resolve(fs(ctx), "~/secret")
    end

    test "rejects leading .. segment", ctx do
      assert {:error, {:invalid_id, _}} = FS.resolve(fs(ctx), "../escape.txt")
    end

    test "rejects middle .. segment", ctx do
      assert {:error, {:invalid_id, _}} = FS.resolve(fs(ctx), "sub/../escape.txt")
    end

    test "rejects trailing .. segment", ctx do
      assert {:error, {:invalid_id, _}} = FS.resolve(fs(ctx), "sub/..")
    end

    test "rejects null bytes", ctx do
      assert {:error, {:invalid_id, _}} = FS.resolve(fs(ctx), "file\0.txt")
    end

    test "rejects forward slash in flat mode", ctx do
      assert {:error, {:invalid_id, _}} = FS.resolve(fs(ctx, nested: false), "sub/file.txt")
    end

    test "rejects backslash in flat mode", ctx do
      assert {:error, {:invalid_id, _}} = FS.resolve(fs(ctx, nested: false), "sub\\file.txt")
    end
  end

  # -- read/2 -----------------------------------------------------------------

  describe "read/2" do
    test "happy path", ctx do
      File.write!(Path.join(ctx.tmp_dir, "hello.txt"), "world")
      assert {:ok, "world"} = FS.read(fs(ctx), "hello.txt")
    end

    test "reads nested file", ctx do
      dir = Path.join(ctx.tmp_dir, "sub")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "deep.txt"), "nested")

      assert {:ok, "nested"} = FS.read(fs(ctx), "sub/deep.txt")
    end

    test "missing file returns error", ctx do
      assert {:error, :not_found} = FS.read(fs(ctx), "nope.txt")
    end

    test "rejected id returns error", ctx do
      assert {:error, {:invalid_id, _}} = FS.read(fs(ctx), "../escape.txt")
    end
  end

  # -- write/3 ----------------------------------------------------------------

  describe "write/3" do
    test "happy path", ctx do
      assert {:ok, %Entry{id: "report.html"}} =
               FS.write(fs(ctx), "report.html", "<h1>Hi</h1>")

      assert File.read!(Path.join(ctx.tmp_dir, "report.html")) == "<h1>Hi</h1>"
    end

    test "overwrites existing file", ctx do
      FS.write(fs(ctx), "data.json", ~s({"v":1}))
      assert {:ok, %Entry{}} = FS.write(fs(ctx), "data.json", ~s({"v":2}))
      assert File.read!(Path.join(ctx.tmp_dir, "data.json")) == ~s({"v":2})
    end

    test "creates parent dirs in nested mode", ctx do
      assert {:ok, %Entry{id: "a/b/c.txt"}} = FS.write(fs(ctx), "a/b/c.txt", "deep")
      assert File.read!(Path.join(ctx.tmp_dir, "a/b/c.txt")) == "deep"
    end

    test "returns error on read-only", ctx do
      assert {:error, :read_only} = FS.write(fs(ctx, read_only: true), "file.txt", "x")
    end

    test "rejects bad ids", ctx do
      assert {:error, {:invalid_id, _}} = FS.write(fs(ctx), "", "x")
      assert {:error, {:invalid_id, _}} = FS.write(fs(ctx), "../escape.txt", "x")
    end
  end

  # -- patch/4 ----------------------------------------------------------------

  describe "patch/4" do
    test "unique match replaces and returns entry", ctx do
      File.write!(Path.join(ctx.tmp_dir, "page.html"), "<h1>Old</h1><p>body</p>")

      assert {:ok, %Entry{id: "page.html"}} =
               FS.patch(fs(ctx), "page.html", "Old", "New")

      assert File.read!(Path.join(ctx.tmp_dir, "page.html")) == "<h1>New</h1><p>body</p>"
    end

    test "zero matches returns error with search string", ctx do
      File.write!(Path.join(ctx.tmp_dir, "file.txt"), "hello world")

      assert {:error, {:patch_no_match, "missing"}} =
               FS.patch(fs(ctx), "file.txt", "missing", "replacement")
    end

    test "multiple matches returns error with count", ctx do
      File.write!(Path.join(ctx.tmp_dir, "file.txt"), "aaa")

      assert {:error, {:patch_multiple_matches, 3}} =
               FS.patch(fs(ctx), "file.txt", "a", "b")
    end

    test "missing file returns error", ctx do
      assert {:error, :not_found} = FS.patch(fs(ctx), "nope.txt", "a", "b")
    end

    test "returns error on read-only", ctx do
      File.write!(Path.join(ctx.tmp_dir, "file.txt"), "hello")

      assert {:error, :read_only} =
               FS.patch(fs(ctx, read_only: true), "file.txt", "hello", "bye")
    end
  end

  # -- list/1 -----------------------------------------------------------------

  describe "list/1" do
    test "empty dir returns empty list", ctx do
      assert {:ok, []} = FS.list(fs(ctx))
    end

    test "lists regular files sorted by id", ctx do
      File.write!(Path.join(ctx.tmp_dir, "b.json"), "{}")
      File.write!(Path.join(ctx.tmp_dir, "a.html"), "<h1>hi</h1>")

      assert {:ok, [%Entry{id: "a.html"}, %Entry{id: "b.json"}]} = FS.list(fs(ctx))
    end

    test "recursive in nested mode", ctx do
      sub = Path.join(ctx.tmp_dir, "sub/deep")
      File.mkdir_p!(sub)
      File.write!(Path.join(sub, "file.txt"), "nested")
      File.write!(Path.join(ctx.tmp_dir, "root.txt"), "top")

      assert {:ok, entries} = FS.list(fs(ctx))
      ids = Enum.map(entries, & &1.id)
      assert ids == ["root.txt", "sub/deep/file.txt"]
    end

    test "flat in flat mode (no recursion)", ctx do
      sub = Path.join(ctx.tmp_dir, "sub")
      File.mkdir_p!(sub)
      File.write!(Path.join(sub, "hidden.txt"), "nested")
      File.write!(Path.join(ctx.tmp_dir, "visible.txt"), "top")

      assert {:ok, [%Entry{id: "visible.txt"}]} = FS.list(fs(ctx, nested: false))
    end

    test "ignores directories themselves", ctx do
      File.mkdir_p!(Path.join(ctx.tmp_dir, "empty_dir"))
      File.write!(Path.join(ctx.tmp_dir, "file.txt"), "content")

      assert {:ok, [%Entry{id: "file.txt"}]} = FS.list(fs(ctx))
    end

    test "includes dotfiles", ctx do
      File.write!(Path.join(ctx.tmp_dir, ".hidden"), "secret")
      File.write!(Path.join(ctx.tmp_dir, "visible.txt"), "public")

      assert {:ok, entries} = FS.list(fs(ctx))
      ids = Enum.map(entries, & &1.id)
      assert ".hidden" in ids
      assert "visible.txt" in ids
    end

    test "includes dot-directories in nested mode", ctx do
      dot_dir = Path.join(ctx.tmp_dir, ".config")
      File.mkdir_p!(dot_dir)
      File.write!(Path.join(dot_dir, "settings.json"), "{}")

      assert {:ok, entries} = FS.list(fs(ctx))
      ids = Enum.map(entries, & &1.id)
      assert ".config/settings.json" in ids
    end
  end

  # -- delete/2 ---------------------------------------------------------------

  describe "delete/2" do
    test "happy path", ctx do
      File.write!(Path.join(ctx.tmp_dir, "temp.txt"), "gone")
      assert :ok = FS.delete(fs(ctx), "temp.txt")
      refute File.exists?(Path.join(ctx.tmp_dir, "temp.txt"))
    end

    test "missing file returns error", ctx do
      assert {:error, :not_found} = FS.delete(fs(ctx), "nope.txt")
    end

    test "returns error on read-only", ctx do
      File.write!(Path.join(ctx.tmp_dir, "keep.txt"), "stay")
      assert {:error, :read_only} = FS.delete(fs(ctx, read_only: true), "keep.txt")
    end
  end
end
