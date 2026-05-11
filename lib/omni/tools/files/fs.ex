defmodule Omni.Tools.Files.FS do
  @moduledoc """
  Filesystem operations scoped to a base directory.

  This module is the reusable core of `Omni.Tools.Files` — it works
  independently of the tool machinery. Construct an `%FS{}` with `new/1`,
  then call operations directly:

      fs = FS.new(base_dir: "/data/workspace", read_only: true)
      {:ok, content} = FS.read(fs, "notes/todo.md")
      {:ok, entries} = FS.list(fs)

  All user-supplied ids are validated against a path policy before any
  disk access. See `resolve/2` for the rules.

  ## Symlinks

  Path resolution follows symlinks (inherits `File.*` behaviour). This
  module does not attempt to detect or block symlink escapes — it is not
  a security boundary. OS-level sandboxing is the right tool for that.
  """

  alias Omni.Tools.Files.Entry

  defstruct [:base_dir, read_only?: false, nested?: true]

  @typedoc "A configured filesystem scope."
  @type t :: %__MODULE__{
          base_dir: String.t(),
          read_only?: boolean(),
          nested?: boolean()
        }

  @doc """
  Creates a new filesystem scope.

  ## Options

    * `:base_dir` (required) — absolute path to an existing directory.
    * `:read_only` — when `true`, write/patch/delete operations return
      `{:error, :read_only}`. Defaults to `false`.
    * `:nested` — when `true`, ids may contain path separators (subdirectories).
      When `false`, only bare filenames are accepted. Defaults to `true`.

  Raises `ArgumentError` if `:base_dir` is missing, not absolute, or
  does not exist on disk.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    base_dir = Keyword.get(opts, :base_dir) || raise ArgumentError, "missing required :base_dir"

    unless Path.type(base_dir) == :absolute do
      raise ArgumentError, ":base_dir must be an absolute path, got: #{inspect(base_dir)}"
    end

    unless File.dir?(base_dir) do
      raise ArgumentError, ":base_dir does not exist or is not a directory: #{inspect(base_dir)}"
    end

    %__MODULE__{
      base_dir: Path.expand(base_dir),
      read_only?: Keyword.get(opts, :read_only, false),
      nested?: Keyword.get(opts, :nested, true)
    }
  end

  @doc """
  Resolves a user-supplied `id` to an absolute path under the base directory.

  Returns `{:ok, abs_path}` or `{:error, {:invalid_id, message}}`.

  ## Path policy

    * Must be non-empty.
    * Must be relative (no leading `/`, `~/`, or `..` segments).
    * Must not contain null bytes.
    * In flat mode, must not contain path separators (`/` or `\\`).
  """
  @spec resolve(t(), String.t()) :: {:ok, String.t()} | {:error, {:invalid_id, String.t()}}
  def resolve(%__MODULE__{} = fs, id) do
    with :ok <- validate_id(fs, id) do
      {:ok, Path.join(fs.base_dir, id)}
    end
  end

  @doc """
  Reads the content of a file.

      {:ok, content} = FS.read(fs, "notes/todo.md")
  """
  @spec read(t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read(%__MODULE__{} = fs, id) do
    with {:ok, abs_path} <- resolve(fs, id) do
      read_file(abs_path)
    end
  end

  @doc """
  Writes content to a file (creates or overwrites).

  In nested mode, parent directories are created automatically.
  Returns `{:ok, %Entry{}}` on success.

      {:ok, entry} = FS.write(fs, "report.html", "<h1>Hello</h1>")
  """
  @spec write(t(), String.t(), binary()) :: {:ok, Entry.t()} | {:error, term()}
  def write(%__MODULE__{read_only?: true}, _id, _content), do: {:error, :read_only}

  def write(%__MODULE__{} = fs, id, content) do
    with {:ok, abs_path} <- resolve(fs, id) do
      if fs.nested?, do: File.mkdir_p!(Path.dirname(abs_path))
      File.write!(abs_path, content)
      {:ok, Entry.new(id, abs_path)}
    end
  end

  @doc """
  Applies a targeted find-and-replace edit to a file.

  The `search` string must appear exactly once in the file. Returns an
  error if it appears zero times or more than once — the error includes
  the count so the caller can refine the search string.

      {:ok, entry} = FS.patch(fs, "config.json", ~s("v1"), ~s("v2"))
  """
  @spec patch(t(), String.t(), String.t(), String.t()) :: {:ok, Entry.t()} | {:error, term()}
  def patch(%__MODULE__{read_only?: true}, _id, _search, _replace), do: {:error, :read_only}

  def patch(%__MODULE__{} = fs, id, search, replace) do
    with {:ok, abs_path} <- resolve(fs, id),
         {:ok, content} <- read_file(abs_path) do
      count = count_occurrences(content, search)

      cond do
        count == 0 ->
          {:error, {:patch_no_match, search}}

        count > 1 ->
          {:error, {:patch_multiple_matches, count}}

        true ->
          updated = String.replace(content, search, replace, global: false)
          File.write!(abs_path, updated)
          {:ok, Entry.new(id, abs_path)}
      end
    end
  end

  @doc """
  Lists all regular files under the base directory.

  In nested mode, walks recursively and returns ids as base-relative paths
  (e.g. `"sub/dir/file.txt"`). In flat mode, lists only direct children.
  Includes dotfiles and dot-directories. Results are sorted by id.

      {:ok, entries} = FS.list(fs)
  """
  @spec list(t()) :: {:ok, [Entry.t()]}
  def list(%__MODULE__{} = fs) do
    paths =
      case fs.nested? do
        true -> list_recursive(fs.base_dir)
        false -> list_flat(fs.base_dir)
      end

    entries =
      paths
      |> Enum.sort()
      |> Enum.map(fn id ->
        Entry.new(id, Path.join(fs.base_dir, id))
      end)

    {:ok, entries}
  end

  @doc """
  Deletes a file.

      :ok = FS.delete(fs, "old-report.html")
  """
  @spec delete(t(), String.t()) :: :ok | {:error, term()}
  def delete(%__MODULE__{read_only?: true}, _id), do: {:error, :read_only}

  def delete(%__MODULE__{} = fs, id) do
    with {:ok, abs_path} <- resolve(fs, id) do
      case File.rm(abs_path) do
        :ok -> :ok
        {:error, :enoent} -> {:error, :not_found}
        {:error, posix} -> {:error, {:file_error, posix}}
      end
    end
  end

  # -- Private ----------------------------------------------------------------

  defp validate_id(%__MODULE__{} = fs, id) do
    cond do
      id == "" ->
        {:error, {:invalid_id, "id must not be empty"}}

      String.contains?(id, <<0>>) ->
        {:error, {:invalid_id, "id must not contain null bytes"}}

      String.starts_with?(id, "/") or String.starts_with?(id, "~") ->
        {:error, {:invalid_id, "id must be a relative path"}}

      has_dotdot_segment?(id) ->
        {:error, {:invalid_id, "id must not contain '..' segments"}}

      not fs.nested? and String.contains?(id, ["/", "\\"]) ->
        {:error, {:invalid_id, "id must not contain path separators in flat mode"}}

      true ->
        :ok
    end
  end

  defp has_dotdot_segment?(id) do
    id
    |> String.split(["/", "\\"])
    |> Enum.any?(&(&1 == ".."))
  end

  defp read_file(abs_path) do
    case File.read(abs_path) do
      {:ok, _content} = ok -> ok
      {:error, :enoent} -> {:error, :not_found}
      {:error, posix} -> {:error, {:file_error, posix}}
    end
  end

  defp count_occurrences(string, pattern) do
    parts = String.split(string, pattern)
    length(parts) - 1
  end

  defp list_flat(base_dir) do
    case File.ls(base_dir) do
      {:ok, names} ->
        Enum.filter(names, fn name ->
          File.regular?(Path.join(base_dir, name))
        end)

      {:error, :enoent} ->
        []
    end
  end

  defp list_recursive(dir), do: list_recursive(dir, dir)

  defp list_recursive(dir, base_dir) do
    case File.ls(dir) do
      {:ok, names} ->
        Enum.flat_map(names, fn name ->
          abs_path = Path.join(dir, name)

          cond do
            File.regular?(abs_path) -> [Path.relative_to(abs_path, base_dir)]
            File.dir?(abs_path) -> list_recursive(abs_path, base_dir)
            true -> []
          end
        end)

      {:error, _} ->
        []
    end
  end
end
