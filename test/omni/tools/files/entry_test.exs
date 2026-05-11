defmodule Omni.Tools.Files.EntryTest do
  use ExUnit.Case, async: true

  alias Omni.Tools.Files.Entry

  @moduletag :tmp_dir

  test "builds from id and absolute path", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "report.html")
    File.write!(path, "<h1>Hello</h1>")

    entry = Entry.new("report.html", path)

    assert entry.id == "report.html"
    assert entry.filename == "report.html"
    assert entry.media_type == "text/html"
    assert entry.size == byte_size("<h1>Hello</h1>")
    assert %DateTime{} = entry.mtime
  end

  test "filename is the basename of a nested id", %{tmp_dir: tmp_dir} do
    dir = Path.join(tmp_dir, "sub")
    File.mkdir_p!(dir)
    path = Path.join(dir, "data.json")
    File.write!(path, "{}")

    entry = Entry.new("sub/data.json", path)

    assert entry.id == "sub/data.json"
    assert entry.filename == "data.json"
  end

  test "media_type for known extensions", %{tmp_dir: tmp_dir} do
    for {name, expected} <- [{"a.json", "application/json"}, {"b.html", "text/html"}] do
      path = Path.join(tmp_dir, name)
      File.write!(path, "x")
      assert Entry.new(name, path).media_type == expected
    end
  end

  test "media_type falls back to application/octet-stream for unknown", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "mystery.xyz123")
    File.write!(path, "data")

    assert Entry.new("mystery.xyz123", path).media_type == "application/octet-stream"
  end

  test "mtime is a DateTime", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "file.txt")
    File.write!(path, "hello")

    assert %DateTime{} = Entry.new("file.txt", path).mtime
  end
end
