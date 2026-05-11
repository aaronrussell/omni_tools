# Omni Tools

![Hex.pm](https://img.shields.io/hexpm/v/omni_tools?color=informational)
![License](https://img.shields.io/github/license/aaronrussell/omni_tools?color=informational)
![Build Status](https://img.shields.io/github/actions/workflow/status/aaronrussell/omni_tools/elixir.yml?branch=main)

**Ready-to-use tools for Omni-powered agents** — files, shell, REPL, and web fetch. Built on [Omni](https://github.com/aaronrussell/omni).

## Features

- **Files** — scoped file CRUD with read-only and flat modes
- **Bash** — shell command execution with timeout, environment, and output capture
- **Repl** — Elixir code evaluation in isolated peer nodes with pluggable extensions
- **WebFetch** — URL fetching with HTML-to-Markdown, JSON pretty-printing, and pluggable strategies
- **Three-layer config** — module defaults → app config → explicit opts, with zero config required
- **Reference quality** — clean, documented implementations you can use as-is or copy as starting points for custom tools

## Installation

Add Omni Tools to your dependencies:

```elixir
def deps do
  [
    {:omni_tools, "~> 0.2"}
  ]
end
```

Omni Tools depends on `omni`, which provides the LLM API layer. Configure
your provider API keys as described in the [Omni
README](https://github.com/aaronrussell/omni#setup).

## The tools

| Module | What it does |
| --- | --- |
| `Omni.Tools.Files` | CRUD over a scoped directory with read-only and flat modes |
| `Omni.Tools.Bash` | Executes shell commands with timeout and output capture |
| `Omni.Tools.Repl` | Evaluates Elixir code in a sandboxed peer node |
| `Omni.Tools.WebFetch` | Fetches URLs, simplifies content for LLM consumption |

Each tool is created with `new/1` and returns an `%Omni.Tool{}` struct:

### Files

Read, write, patch, list, and delete files within a scoped directory:

```elixir
# Full access with nested paths
Omni.Tools.Files.new(base_dir: "/data/workspace")

# Read-only, flat (no subdirectories)
Omni.Tools.Files.new(base_dir: "/data/docs", read_only: true, nested: false)
```

### Bash

Execute shell commands in a configured working directory:

```elixir
Omni.Tools.Bash.new(dir: "/app", timeout: 60_000, env: [{"NODE_ENV", "test"}])
```

### Repl

Evaluate Elixir code in a fresh peer node with optional extensions:

```elixir
alias Omni.Tools.Repl.Extension

Omni.Tools.Repl.new(
  extensions: [
    {MyApp.ReplExtension, api_key: "sk-..."},
    Extension.new(description: "Req and Jason are available.")
  ]
)
```

### WebFetch

Fetch URLs and extract content appropriate for LLM consumption:

```elixir
Omni.Tools.WebFetch.new(max_output: 30_000, timeout: 10_000)
```

Three strategies are always active — GitHub (blob URLs to raw content),
Reddit (JSON API to formatted Markdown), and a default catch-all. Custom
strategies are prepended and matched first, so they can override or extend
the built-ins:

```elixir
Omni.Tools.WebFetch.new(strategies: [{MyApp.WikiStrategy, []}])
```

## Using tools in a conversation

Pass tools to `Omni.generate_text/3` or `Omni.stream_text/3` — the tool
loop executes uses automatically and feeds results back to the model:

```elixir
fs   = Omni.Tools.Files.new(base_dir: "/data/workspace")
bash = Omni.Tools.Bash.new(dir: "/data/workspace")

context = Omni.context(
  system: "You are a coding assistant with access to a project workspace.",
  messages: [Omni.message("List all Elixir files and count the lines in each.")],
  tools: [fs, bash]
)

{:ok, response} = Omni.generate_text({:anthropic, "claude-sonnet-4-6"}, context)
```

Tools work the same way with `Omni.Agent` — pass them as start options
or set them in your agent's `init/1` callback:

```elixir
{:ok, agent} = Omni.Agent.start_link(
  model: {:anthropic, "claude-sonnet-4-6"},
  tools: [fs, bash],
  subscribe: true
)
```

## Configuration

Every tool supports a three-layer configuration merge:

```
module defaults → application config → explicit opts
```

Explicit opts to `new/1` always win. Application config provides
per-environment defaults. Module defaults are sensible out of the box.

```elixir
# config/runtime.exs
config :omni_tools, Omni.Tools.Bash,
  timeout: 60_000,
  max_output: 100_000

# At call site — :dir is required, :timeout overrides the app config
Omni.Tools.Bash.new(dir: "/app", timeout: 10_000)
```

No application config is required — every tool works with zero config
and sensible defaults.

## Documentation

Full API reference is available on [HexDocs](https://hexdocs.pm/omni_tools).

## License

This package is open source and released under the [Apache-2 License](https://github.com/aaronrussell/omni_tools/blob/main/LICENSE).

© Copyright 2026 [Push Code Ltd](https://www.pushcode.com/).
