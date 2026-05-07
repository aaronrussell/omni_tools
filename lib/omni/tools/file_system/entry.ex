defmodule Omni.Tools.FileSystem.Entry do
  @moduledoc """
  Metadata for a file managed by the filesystem tool.

  Built from an `id` (base-relative path) and the absolute path on disk.
  Content lives on disk; this struct is a lightweight view returned by
  write, patch, and list operations.

      Entry.new("notes/todo.md", "/data/workspace/notes/todo.md")
      #=> %Entry{id: "notes/todo.md", filename: "todo.md", media_type: "text/markdown", ...}
  """

  defstruct [:id, :filename, :media_type, :size, :mtime]

  @typedoc "File metadata returned by filesystem operations."
  @type t :: %__MODULE__{
          id: String.t(),
          filename: String.t(),
          media_type: String.t(),
          size: non_neg_integer(),
          mtime: DateTime.t()
        }

  @doc """
  Builds an entry from a base-relative `id` and the file's absolute path.

  Reads size and mtime from disk via `File.stat!/2`. Derives `filename`
  from `id` and `media_type` from the file extension.
  """
  @spec new(String.t(), String.t()) :: t()
  def new(id, abs_path) do
    stat = File.stat!(abs_path, time: :posix)

    %__MODULE__{
      id: id,
      filename: Path.basename(id),
      media_type: MIME.from_path(id),
      size: stat.size,
      mtime: DateTime.from_unix!(stat.mtime)
    }
  end
end
