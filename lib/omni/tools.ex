defmodule Omni.Tools do
  @moduledoc """
  ![License](https://img.shields.io/github/license/aaronrussell/omni_tools?color=informational)

  **Ready-to-use tools for Omni-powered agents** — filesystem, shell, REPL,
  and web fetch. Built on [Omni](https://github.com/aaronrussell/omni).

  Omni Tools is a small set of reference `Omni.Tool` implementations that
  ship ready-to-use and serve as worked examples of how to build tools for
  LLMs. Each tool validates configuration at construction time and works
  with any Omni provider that supports tool use.

  ## Installation

  Add Omni Tools to your dependencies:

      {:omni_tools, "~> 0.2"}

  Omni Tools depends on `omni`, which provides the LLM API layer. Configure
  your provider API keys as described in the
  [Omni README](https://github.com/aaronrussell/omni#setup).

  ## The tools

  | Module | What it does |
  | --- | --- |
  | `Omni.Tools.Files` | CRUD over a scoped directory with read-only and flat modes |
  | `Omni.Tools.Bash` | Executes shell commands with timeout and output capture |
  | `Omni.Tools.Repl` | Evaluates Elixir code in a sandboxed peer node |
  | `Omni.Tools.WebFetch` | Fetches URLs, simplifies content for LLM consumption |

  Each tool is created with `new/1` and returns an `%Omni.Tool{}` struct
  ready to pass into an Omni context:

      fs   = Omni.Tools.Files.new(base_dir: "/data/workspace")
      bash = Omni.Tools.Bash.new(dir: "/app")
      repl = Omni.Tools.Repl.new()
      web  = Omni.Tools.WebFetch.new()

  ### Files

  Read, write, patch, list, and delete files within a scoped directory.
  Configuration controls read-only access and whether subdirectories are
  allowed:

      # Full access with nested paths
      Omni.Tools.Files.new(base_dir: "/data/workspace")

      # Read-only, flat (no subdirectories)
      Omni.Tools.Files.new(base_dir: "/data/docs", read_only: true, nested: false)

  See `Omni.Tools.Files` for all options. The underlying operations
  are also available standalone via `Omni.Tools.Files.FS`.

  ### Bash

  Executes shell commands in a configured working directory with environment
  variables, timeout, and output truncation:

      Omni.Tools.Bash.new(dir: "/app", timeout: 60_000, env: [{"NODE_ENV", "test"}])

  See `Omni.Tools.Bash` for all options. The command runner is also
  available standalone via `Omni.Tools.Bash.Runner`.

  ### Repl

  Evaluates Elixir code in a fresh peer node — clean slate per execution,
  with IO capture and configurable extensions:

      alias Omni.Tools.Repl.Extension

      Omni.Tools.Repl.new(
        extensions: [
          {MyApp.ReplExtension, api_key: "sk-..."},
          Extension.new(description: "Req and Jason are available.")
        ]
      )

  See `Omni.Tools.Repl` for all options and `Omni.Tools.Repl.Extension`
  for the extension API.

  ### WebFetch

  Fetches one or more URLs and extracts content appropriate for LLM
  consumption — HTML to Markdown, JSON to pretty-printed, plain text
  passthrough:

      Omni.Tools.WebFetch.new(max_output: 30_000, timeout: 10_000)

  Three strategies are always active — GitHub (blob URLs to raw content),
  Reddit (JSON API to formatted Markdown), and a default catch-all.
  Custom strategies are prepended and matched first, so they can
  override or extend the built-ins:

      Omni.Tools.WebFetch.new(strategies: [{MyApp.WikiStrategy, []}])

  See `Omni.Tools.WebFetch` for all options and
  `Omni.Tools.WebFetch.Strategy` for the strategy behaviour.

  ## Using tools in a conversation

  Pass tools to `Omni.generate_text/3` or `Omni.stream_text/3` — the tool
  loop executes uses automatically and feeds results back to the model:

      fs   = Omni.Tools.Files.new(base_dir: "/data/workspace")
      bash = Omni.Tools.Bash.new(dir: "/data/workspace")

      context = Omni.context(
        system: "You are a coding assistant with access to a project workspace.",
        messages: [Omni.message("List all Elixir files and count the lines in each.")],
        tools: [fs, bash]
      )

      {:ok, response} = Omni.generate_text({:anthropic, "claude-sonnet-4-6"}, context)

  Tools work the same way with `Omni.Agent` — pass them as start options
  or set them in your agent's `init/1` callback:

      {:ok, agent} = Omni.Agent.start_link(
        model: {:anthropic, "claude-sonnet-4-6"},
        tools: [fs, bash],
        subscribe: true
      )

  ## Configuration

  Every tool supports a three-layer configuration merge:

      module defaults → application config → explicit opts

  Explicit opts to `new/1` always win. Application config provides
  per-environment defaults. Module defaults are sensible out of the box.

      # config/runtime.exs
      config :omni_tools, Omni.Tools.Bash,
        timeout: 60_000,
        max_output: 100_000

      # At call site — :dir is required, :timeout overrides the app config
      Omni.Tools.Bash.new(dir: "/app", timeout: 10_000)

  No application config is required — every tool works with zero config
  and sensible defaults.

  ## Writing custom tools

  These tools implement the `Omni.Tool` behaviour from the `omni` package.
  To build your own, see `Omni.Tool` — or read any of the tools in this
  package as worked examples.
  """
end
