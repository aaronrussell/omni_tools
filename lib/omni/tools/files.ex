defmodule Omni.Tools.Files do
  @moduledoc """
  An `Omni.Tool` for file operations scoped to a base directory.

  Provides read, write, patch, list, and delete commands over a
  configurable directory. Configuration controls whether writes are
  allowed and whether subdirectories are supported.

      # Full read-write access with nested subdirectories
      tool = Omni.Tools.Files.new(base_dir: "/data/workspace")

      # Read-only access, flat (no subdirectories)
      tool = Omni.Tools.Files.new(base_dir: "/data/docs", read_only: true, nested: false)

  The tool delegates all operations to `Omni.Tools.Files.FS`, which
  can also be used independently of the tool machinery.

  ## REPL integration

  When using both Files and REPL tools together, the
  `Omni.Tools.Repl.Extensions.Files` extension lets agent code in
  the sandbox read and write files directly — without a separate tool
  use round-trip. See that module's docs for setup.

  ## Options

  Either pass a pre-built `%FS{}` struct or the options to build one:

  - `:fs` — a `%Omni.Tools.Files.FS{}` struct. When provided, `:base_dir`,
    `:read_only`, and `:nested` are ignored.
  - `:base_dir` (required if `:fs` is not given) — absolute path to the base
    directory (created on first write if it doesn't exist).
  - `:read_only` — restricts to `read` and `list` only. Default `false`.
  - `:nested` — allows subdirectory paths in ids. Default `true`.
  """

  use Omni.Tool, name: "files"

  alias Omni.Tools.Files.FS

  @defaults [
    read_only: false,
    nested: true
  ]

  @impl Omni.Tool
  def init(opts) do
    case Keyword.get(opts, :fs) do
      %FS{} = fs ->
        fs

      nil ->
        @defaults
        |> Keyword.merge(Application.get_env(:omni_tools, __MODULE__, []))
        |> Keyword.merge(opts || [])
        |> FS.new()
    end
  end

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
    intro =
      if fs.read_only? do
        """
        Browse and read files on demand from a directory of reference material.

        Read-only access. Available commands: read, list
        """
      else
        """
        Create and manage persistent files that you author directly: markdown notes, \
        HTML pages, data files, reports, code files, SVG graphics. The user can view or download them.

        Read-write access. Available commands: read, list, write, patch, delete
        """
      end

    scope =
      if fs.nested? do
        "All file paths (`id`) are relative to the base directory. Subdirectories are allowed."
      else
        "All file names (`id`) are bare filenames only (no subdirectories)."
      end

    commands = """
    - **read** — returns the file content. Requires `id`.
    - **list** — lists all files with media types and sizes. No arguments.
    """

    commands =
      if fs.read_only?,
        do: commands,
        else:
          commands <>
            """
            - **write** — creates or overwrites a file. Requires `id` and `content`.
            - **patch** — targeted find-and-replace. Requires `id`, `search`, and `replace`. \
            The `search` string must appear exactly once in the file — if it matches zero \
            or multiple times, the operation fails with a diagnostic message.
            - **delete** — removes a file. Requires `id`.

            ## Prefer patch over write
            When editing an existing file, always prefer patch for targeted changes. \
            Only use write to replace an entire file when most of the content is changing. \
            Ask yourself: can I describe the change as search → replace? If yes, use patch.
            """

    """
    #{intro}

    File operations are scoped to a base directory. \
    #{scope} Absolute paths, ".." sqeuences, and null bytes are rejected.

    ## Commands
    #{commands}
    """
  end

  @impl Omni.Tool
  def call(%{command: "read"} = input, %FS{} = fs) do
    id = fetch!(input, :id, "read")

    case FS.read(fs, id) do
      {:ok, content} -> content
      {:error, reason} -> raise format_error(reason, id)
    end
  end

  def call(%{command: "list"}, %FS{} = fs) do
    case FS.list(fs) do
      {:ok, []} ->
        "No files"

      {:ok, entries} ->
        Enum.map_join(entries, "\n", fn e ->
          "#{e.id} (#{e.media_type}, #{e.size} bytes)"
        end)
    end
  end

  def call(%{command: "write"} = input, %FS{} = fs) do
    id = fetch!(input, :id, "write")
    content = fetch!(input, :content, "write")

    case FS.write(fs, id, content) do
      {:ok, entry} -> "Wrote #{entry.id} (#{entry.size} bytes)"
      {:error, reason} -> raise format_error(reason, id)
    end
  end

  def call(%{command: "patch"} = input, %FS{} = fs) do
    id = fetch!(input, :id, "patch")
    search = fetch!(input, :search, "patch")
    replace = fetch!(input, :replace, "patch")

    case FS.patch(fs, id, search, replace) do
      {:ok, entry} -> "Patched #{entry.id} (#{entry.size} bytes)"
      {:error, reason} -> raise format_error(reason, id)
    end
  end

  def call(%{command: "delete"} = input, %FS{} = fs) do
    id = fetch!(input, :id, "delete")

    case FS.delete(fs, id) do
      :ok -> "Deleted #{id}"
      {:error, reason} -> raise format_error(reason, id)
    end
  end

  defp fetch!(input, key, command) do
    case Map.get(input, key) do
      nil -> raise "#{command} command requires #{inspect(key)} param"
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
