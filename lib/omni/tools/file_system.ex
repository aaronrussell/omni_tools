defmodule Omni.Tools.FileSystem do
  @moduledoc """
  An `Omni.Tool` for file operations scoped to a base directory.

  Provides read, write, patch, list, and delete commands over a
  configurable directory. Configuration controls whether writes are
  allowed and whether subdirectories are supported.

      # Full read-write access with nested subdirectories
      tool = Omni.Tools.FileSystem.new(base_dir: "/data/workspace")

      # Read-only access, flat (no subdirectories)
      tool = Omni.Tools.FileSystem.new(base_dir: "/data/docs", read_only: true, nested: false)

  The tool delegates all operations to `Omni.Tools.FileSystem.FS`, which
  can also be used independently of the tool machinery.

  ## Options

    * `:base_dir` (required) — absolute path to an existing directory.
    * `:read_only` — restricts to `read` and `list` only. Default `false`.
    * `:nested` — allows subdirectory paths in ids. Default `true`.
  """

  use Omni.Tool,
    name: "file_system",
    description: "File operations scoped to a base directory."

  alias Omni.Tools.FileSystem.FS

  @impl Omni.Tool
  def init(opts), do: FS.new(opts)

  @impl Omni.Tool
  def schema(%FS{read_only?: true}) do
    import Omni.Schema

    object(
      %{
        command: enum(["read", "list"], description: "The operation to perform"),
        id: string(description: "File path relative to the base directory")
      },
      required: [:command]
    )
  end

  def schema(%FS{}) do
    import Omni.Schema

    object(
      %{
        command:
          enum(
            ["read", "list", "write", "patch", "delete"],
            description: "The operation to perform"
          ),
        id: string(description: "File path relative to the base directory"),
        content: string(description: "File content (for write)"),
        search: string(description: "Exact string to find (must match exactly once)"),
        replace: string(description: "Replacement string (for patch)")
      },
      required: [:command]
    )
  end

  @impl Omni.Tool
  def description(%FS{} = fs) do
    mode =
      cond do
        fs.read_only? -> "Read-only access"
        true -> "Read-write access"
      end

    path_note =
      if fs.nested?,
        do:
          "Subdirectories are allowed — use forward-slash-separated paths (e.g. \"sub/file.txt\").",
        else: "Flat mode — only bare filenames are accepted (no subdirectories)."

    commands =
      if fs.read_only?,
        do: "read, list",
        else: "read, list, write, patch, delete"

    """
    File operations scoped to #{fs.base_dir}.

    #{mode}. Available commands: #{commands}.

    #{path_note}

    All file paths (`id`) are relative to the base directory. Absolute paths, \
    ".." segments, and null bytes are rejected.

    ## Commands

    - **read** — returns the file content. Requires `id`.
    - **list** — lists all files with media types and sizes. No arguments.\
    #{unless fs.read_only? do
      """

      - **write** — creates or overwrites a file. Requires `id` and `content`.
      - **patch** — targeted find-and-replace. Requires `id`, `search`, and `replace`. \
      The `search` string must appear exactly once in the file — if it matches zero \
      or multiple times, the operation fails with a diagnostic message. Prefer patch \
      over write for targeted edits.
      - **delete** — removes a file. Requires `id`.\
      """
    end}
    """
  end

  @impl Omni.Tool
  def call(input, %FS{} = fs) do
    case input.command do
      "read" ->
        id = fetch!(input, :id, "read")

        case FS.read(fs, id) do
          {:ok, content} -> content
          {:error, reason} -> raise format_error(reason, id)
        end

      "list" ->
        {:ok, entries} = FS.list(fs)

        case entries do
          [] ->
            "No files"

          entries ->
            Enum.map_join(entries, "\n", fn e ->
              "#{e.id} (#{e.media_type}, #{e.size} bytes)"
            end)
        end

      "write" ->
        id = fetch!(input, :id, "write")
        content = fetch!(input, :content, "write")

        case FS.write(fs, id, content) do
          {:ok, entry} -> "Wrote #{entry.id} (#{entry.size} bytes)"
          {:error, reason} -> raise format_error(reason, id)
        end

      "patch" ->
        id = fetch!(input, :id, "patch")
        search = fetch!(input, :search, "patch")
        replace = fetch!(input, :replace, "patch")

        case FS.patch(fs, id, search, replace) do
          {:ok, entry} -> "Patched #{entry.id} (#{entry.size} bytes)"
          {:error, reason} -> raise format_error(reason, id)
        end

      "delete" ->
        id = fetch!(input, :id, "delete")

        case FS.delete(fs, id) do
          :ok -> "Deleted #{id}"
          {:error, reason} -> raise format_error(reason, id)
        end
    end
  end

  defp fetch!(input, key, command) do
    case Map.get(input, key) do
      nil -> raise "#{command} requires #{inspect(key)}"
      value -> value
    end
  end

  defp format_error(:read_only, _id), do: "file system is read-only"
  defp format_error(:not_found, id), do: "file not found: #{id}"
  defp format_error({:invalid_id, msg}, _id), do: msg

  defp format_error({:patch_no_match, search}, _id),
    do: "search string not found: #{inspect(search)}"

  defp format_error({:patch_multiple_matches, count}, _id),
    do: "search string matches #{count} times (must match exactly once)"

  defp format_error({:file_error, posix}, id), do: "file error on #{id}: #{posix}"
  defp format_error(other, id), do: "unexpected error on #{id}: #{inspect(other)}"
end
