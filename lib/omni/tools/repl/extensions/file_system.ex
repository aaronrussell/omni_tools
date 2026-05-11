defmodule Omni.Tools.Repl.Extensions.FileSystem do
  @moduledoc """
  REPL extension that bridges `Omni.Tools.FileSystem` into the sandbox.

  When an agent has both REPL and FileSystem tools, it can generate data
  in the REPL and then write it via a separate FileSystem tool use. This
  extension removes that round-trip — code running in the sandbox can
  read and write files directly through a `Files` module that operates
  on the same configured filesystem scope.

  The extension accepts a `%Omni.Tools.FileSystem.FS{}` struct, so the
  sandbox inherits the same base directory, read-only flag, and nesting
  policy as the FileSystem tool it's paired with.

      Files.write("chart.html", html_content)   #=> %Entry{}
      Files.read("data.csv")                     #=> "csv,content..."
      Files.patch("chart.html", "old", "new")    #=> %Entry{}
      Files.list()                                #=> [%Entry{}, ...]
      Files.delete("temp.txt")                    #=> :ok

  ## Usage

      fs = Omni.Tools.FileSystem.FS.new(base_dir: "/tmp/workspace")

      Omni.Tools.Repl.new(
        extensions: [{Omni.Tools.Repl.Extensions.FileSystem, fs: fs}]
      )
  """

  @behaviour Omni.Tools.Repl.Extension

  @impl true
  def code(opts) do
    fs = Keyword.fetch!(opts, :fs)
    escaped = Macro.escape(fs)

    quote do
      defmodule Files do
        @moduledoc false
        @fs unquote(escaped)

        def read(id) do
          case Omni.Tools.FileSystem.FS.read(@fs, id) do
            {:ok, content} -> content
            {:error, reason} -> raise format_error(reason, id)
          end
        end

        def write(id, content) do
          case Omni.Tools.FileSystem.FS.write(@fs, id, content) do
            {:ok, entry} -> entry
            {:error, reason} -> raise format_error(reason, id)
          end
        end

        def patch(id, search, replace) do
          case Omni.Tools.FileSystem.FS.patch(@fs, id, search, replace) do
            {:ok, entry} -> entry
            {:error, reason} -> raise format_error(reason, id)
          end
        end

        def list do
          {:ok, entries} = Omni.Tools.FileSystem.FS.list(@fs)
          entries
        end

        def delete(id) do
          case Omni.Tools.FileSystem.FS.delete(@fs, id) do
            :ok -> :ok
            {:error, reason} -> raise format_error(reason, id)
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
    end
  end

  @impl true
  def description(opts) do
    fs = Keyword.fetch!(opts, :fs)

    intro =
      if fs.read_only? do
        """
        Use the `Files` module to browse and read files on demand from a \
        scoped directory of reference material. Read-only access.
        """
      else
        """
        Use the `Files` module to create and manage persistent files in a \
        scoped directory. The user can view or download them. Read-write access.
        """
      end

    scope =
      if fs.nested? do
        "All file paths (`id`) are relative to the base directory. Subdirectories are allowed."
      else
        "All file names (`id`) are bare filenames only (no subdirectories)."
      end

    functions =
      if fs.read_only? do
        """
        - `Files.read(id)` — returns file content as a string
        - `Files.list()` — returns a list of `%Entry{id, filename, media_type, size, mtime}` structs
        """
      else
        """
        - `Files.read(id)` — returns file content as a string
        - `Files.write(id, content)` — creates or overwrites a file, returns `%Entry{}`
        - `Files.patch(id, search, replace)` — targeted find-and-replace (search must match exactly once), returns `%Entry{}`
        - `Files.list()` — returns a list of `%Entry{id, filename, media_type, size, mtime}` structs
        - `Files.delete(id)` — removes a file, returns `:ok`
        """
      end

    """
    ## Files

    #{intro}

    #{scope}

    #{functions}

    All functions raise on errors with descriptive messages.
    """
  end
end
