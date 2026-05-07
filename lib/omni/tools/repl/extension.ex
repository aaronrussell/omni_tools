defmodule Omni.Tools.Repl.Extension do
  @moduledoc """
  Behaviour and struct for extending the REPL sandbox environment.

  Extensions inject code and documentation into the sandbox. There are
  two ways to define an extension:

  ## Inline extensions

  Use `new/1` to create lightweight extensions without defining a module.
  At least one of `:code` or `:description` must be provided.

      # Description-only — document available host modules
      Extension.new(description: "Req and Jason are available.")

      # Code-only — inject setup code
      Extension.new(code: quote(do: defmodule(Helper, do: def(ping, do: :pong))))

      # Both
      Extension.new(
        code: quote(do: defmodule(Helper, do: def(ping, do: :pong))),
        description: "- `Helper.ping/0` — returns `:pong`"
      )

  ## Module-based extensions

  For reusable extensions, define a module implementing the behaviour.
  Both callbacks are required.

      defmodule MyApp.ReplExtension do
        @behaviour Omni.Tools.Repl.Extension

        @impl true
        def code(opts) do
          api_key = Keyword.fetch!(opts, :api_key)

          quote do
            defmodule MyAPI do
              def fetch(path) do
                Req.get!(path, headers: [{"authorization", unquote(api_key)}]).body
              end
            end
          end
        end

        @impl true
        def description(_opts) do
          \"""
          ## MyAPI
          - `MyAPI.fetch(path)` — authenticated GET request
          \"""
        end
      end

  ## Usage

  Pass extensions to `Omni.Tools.Repl.new/1`:

      Omni.Tools.Repl.new(
        extensions: [
          {MyApp.ReplExtension, api_key: "sk-..."},
          Extension.new(description: "Extra context for the model")
        ]
      )
  """

  @typedoc "Code to evaluate in the sandbox — AST (preferred) or a string."
  @type setup_code :: String.t() | Macro.t()

  @typedoc "A resolved extension with optional code and description."
  @type t :: %__MODULE__{
          code: setup_code() | nil,
          description: String.t() | nil
        }

  defstruct [:code, :description]

  @doc """
  Returns code to evaluate in the sandbox before the user's code.

  Receives the opts from the `{module, opts}` tuple in the extensions
  list. Return a quoted expression (preferred) or a code string. The
  code is evaluated in the peer node before IO capture begins.
  """
  @callback code(opts :: keyword()) :: setup_code()

  @doc """
  Returns a description fragment appended to the REPL tool description.

  Receives the same opts as `code/1`. The returned string should document
  the APIs made available by `code/1` so the agent knows how to use them.
  """
  @callback description(opts :: keyword()) :: String.t()

  @doc """
  Creates an inline extension.

  At least one of `:code` or `:description` must be provided.

      Extension.new(description: "Req is available. Do not Mix.install it.")
      Extension.new(code: "defmodule(H, do: def(hi, do: :hello))")
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    code = Keyword.get(opts, :code)
    description = Keyword.get(opts, :description)

    if is_nil(code) and is_nil(description) do
      raise ArgumentError, "extension requires at least one of :code or :description"
    end

    %__MODULE__{code: code, description: description}
  end
end
