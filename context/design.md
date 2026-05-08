# Omni Tools — Package Design

This is the reference for how `omni_tools` is built. It complements
`CLAUDE.md` (developer conventions and workflows) with the design
intent — what each tool does, why it's shaped the way it is, and the
cross-cutting decisions that hold the package together.

The package is at the start of its life. Most of this document will
fill in as tools are ported, fleshed out, and reviewed. For now the
sections sketch the intent; detail follows the work.

---

## 1. What the package is

`omni_tools` ships a small, fixed set of reference `Omni.Tool`
implementations. The goals, in order:

1. **Useful by default.** Each tool should be drop-in usable for
   common agent shapes (filesystem-bound assistants, code-eval
   sandboxes, web research, shell automation).
2. **Exemplary.** Each tool is a worked example of how to build an
   `Omni.Tool` — schema design, configuration via `init/1`,
   description tuning, error shapes. Other developers will read and
   copy these.
3. **Trivial to install.** Pure Elixir plus a handful of mainstream
   hex deps. No external runtimes, no fragile native code, no
   third-party service integrations.

The package is opinionated and deliberately small. The full scope
constraints live in `CLAUDE.md` § *Scope rules* — they apply to design
decisions just as firmly as to code.

---

## 2. Relationship to `omni`

`omni_tools` depends on `omni` and nothing else from the Omni stack.
The integration surface is small:

- `Omni.Tool` — the behaviour and `use` macro every tool builds on.
- `Omni.Schema` — JSON Schema builders used inside `schema/0`.
- `Omni.Content.{ToolUse, ToolResult}` — what tools produce and
  consume in practice (most tools just return strings or maps; the
  framework wraps them).

`omni_tools` adds no abstractions on top of `omni` — it's just a
collection of tools. There is no `Omni.Tools` umbrella module, no
shared registry, no auto-discovery. Apps include the tools they want
explicitly via `Tool.new/1`.

---

## 3. The tools

Brief sketches of what's coming. Each will get a dedicated section
fleshed out as it lands.

### 3.1 `Omni.Tools.FileSystem`

CRUD operations scoped to a configurable base directory.

#### Module layout

```
lib/omni/tools/file_system.ex          # Omni.Tool implementation (thin)
lib/omni/tools/file_system/fs.ex       # %FS{} + path resolution + file ops
lib/omni/tools/file_system/entry.ex    # %Entry{} result struct
```

**`Omni.Tools.FileSystem`** — the tool module. `use Omni.Tool`,
`init/1`, `schema/1`, `description/1`, `call/2`. Thin; delegates to
`FS` for all real work.

**`Omni.Tools.FileSystem.FS`** — the public, reusable filesystem API.
Carries the `%FS{}` struct (base dir, mode flags), path resolution,
and all file operations (`read`, `write`, `list`, `patch`, `delete`).
Independently usable without the tool machinery.

**`Omni.Tools.FileSystem.Entry`** — result struct returned by write,
patch, and list operations. Fields: `id`, `filename`, `media_type`,
`size`, `mtime`.

#### Configuration

| Option       | Default | Effect                                                     |
| ------------ | ------- | ---------------------------------------------------------- |
| `:base_dir`  | (req'd) | Absolute path. Must already exist.                         |
| `:read_only` | `false` | When `true`, only `read` and `list` are available.         |
| `:nested`    | `true`  | When `false` (flat), paths cannot contain path separators. |

All options support application config (see § 4).

#### Path policy

- Relative only. Rejects absolute (`/foo`, `~/foo`), any `..`
  segment, null bytes.
- Dotfiles and dot-directories are allowed and listed.
- In flat mode, path separators (`/`, `\`) are additionally rejected.
- On write in nested mode, parent directories are created
  automatically.

#### Operations

All operations return ok/error tuples from `FS`. The tool's `call/2`
raises on errors so the model sees tool errors.

- `read(fs, id)` → `{:ok, binary}` | `{:error, reason}`
- `write(fs, id, content)` → `{:ok, Entry.t}` | `{:error, reason}`
- `patch(fs, id, search, replace)` → `{:ok, Entry.t}` | `{:error, reason}`.
  Unique-required: errors if zero or >1 matches.
- `list(fs)` → `{:ok, [Entry.t]}`. Recursive in nested mode, flat
  in flat mode. Sorted by id.
- `delete(fs, id)` → `:ok` | `{:error, reason}`

#### Known boundaries

- Symlinks: follows them (inherits `File.*` behaviour). Not a
  security boundary.
- No size cap on read. No locking. No subdirectory filtering on list.
- Empty parent directories left behind after delete (invisible to
  list, which only returns files).

### 3.2 `Omni.Tools.Repl`

Evaluates Elixir code in an isolated peer node. Ported from
`omni_ui`, reworked extension mechanism.

#### Module layout

```
lib/omni/tools/repl.ex                  # Omni.Tool implementation (thin)
lib/omni/tools/repl/sandbox.ex          # Peer node execution engine
lib/omni/tools/repl/extension.ex        # Extension behaviour + struct
```

**`Omni.Tools.Repl`** — the tool module. `use Omni.Tool`, `init/1`,
`schema/0`, `description/1`, `call/2`. Thin; delegates execution to
`Sandbox` and reads resolved extensions from its state.

**`Omni.Tools.Repl.Sandbox`** — the execution engine. Starts a fresh
Erlang peer node per invocation, evaluates code with IO capture,
returns output + raw result. Independently usable without the tool
machinery. Handles timeouts, peer crashes, and output truncation.

**`Omni.Tools.Repl.Extension`** — both a struct and a behaviour.
Module-based extensions implement the behaviour (both `code/1` and
`description/1` required). Inline extensions use the struct via
`Extension.new/1` with at least one of `:code` or `:description`.

#### Configuration

| Option        | Default  | Effect                                               |
| ------------- | -------- | ---------------------------------------------------- |
| `:timeout`    | `60_000` | Execution timeout in milliseconds                    |
| `:max_output` | `50_000` | Output truncation limit in bytes                     |
| `:extensions` | `[]`     | List of extensions (module tuples or `%Extension{}`)  |

All options support application config (see § 4).

#### Extension mechanism

Extensions are resolved to `%Extension{}` structs at init time (when
`Tool.new/1` is called). Three input forms are accepted:

- `{module, opts}` — calls `module.code(opts)` and
  `module.description(opts)`, stores results in struct
- bare `module` — treated as `{module, []}`
- `%Extension{}` — passed through as-is

This means extension code and descriptions are captured once at
construction time, not re-evaluated on each tool use.

#### Sandbox contract

- **Fresh peer per invocation.** No state carries over between calls.
  Each `run/2` starts a new `:peer` node and stops it afterward.
- **IO capture.** A host-side `StringIO` captures all peer output.
  On timeout, partial output is still readable since the StringIO
  lives on the host.
- **Setup code.** Extensions inject code (string or AST) that runs in
  the peer before the user's code and before IO capture begins.
  Setup output is not included in the result.
- **Host code paths.** The peer inherits all host code paths via
  `:code.add_pathsa/1`, so application dependencies are available.
  `Mix.install/1` can add extra packages in dev (each peer is fresh).
- **Distribution.** Peer nodes require the host VM to be distributed.
  `Sandbox.ensure_distributed!/0` handles this lazily (idempotent).
  Callers may invoke it at application boot to avoid the distribution
  flip on first tool use.

Return type:

```
{:ok, %{output: String.t(), result: term()}}
{:error, :timeout | :noconnection, %{output: String.t()}}
{:error, {kind, reason, stacktrace}, %{output: String.t()}}
```

#### Safety boundary

The sandbox executes arbitrary code with full system access. It is
best-effort isolation, not a security boundary. For trusted use cases
only: agent-driven experimentation, scratchpad computation — not
adversarial input. This is documented in the Sandbox moduledoc and
in the tool description shown to the model.

#### Known boundaries

- Full system access in the peer — file system, network, etc.
- `binary_part` truncation can split multi-byte UTF-8 codepoints.
- No persistent REPL state — each invocation is independent.
- `ensure_distributed!` has a race window under concurrent first
  calls; handled by accepting `{:error, {:already_started, _}}`.

### 3.3 `Omni.Tools.Bash`

Executes shell commands scoped to a configurable working directory.

#### Module layout

```
lib/omni/tools/bash.ex              # Omni.Tool implementation (thin)
lib/omni/tools/bash/runner.ex       # Port-based execution engine
```

**`Omni.Tools.Bash`** — the tool module. `use Omni.Tool`, `init/1`,
`schema/1`, `description/1`, `call/2`. Thin; delegates to `Runner`
for all real work.

**`Omni.Tools.Bash.Runner`** — the execution engine. Opens a Port,
collects output, handles timeouts, applies truncation. Independently
usable without the tool machinery.

#### Configuration

| Option            | Default         | Effect                                                           |
| ----------------- | --------------- | ---------------------------------------------------------------- |
| `:dir`            | (required)      | Working directory. Must exist at init time.                      |
| `:env`            | `[]`            | Extra env vars as `[{String.t(), String.t()}]`. Merged with inherited env. |
| `:timeout`        | `30_000`        | Execution timeout in milliseconds. Kills the process on timeout. |
| `:max_output`     | `50_000`        | Output truncation limit in bytes. Tail-biased, line-snapped.    |
| `:shell`          | auto-resolved   | `{executable, args}` tuple. Auto: `/bin/bash` then `/bin/sh`.   |
| `:command_prefix` | `nil`           | String prepended to every command with a newline separator.      |

All options support application config (see § 4).

#### Shell resolution

At init time, the shell is resolved once and stored in state (so
`description/1` can report it):

1. Explicit `:shell` option — validated as `{binary, list}` tuple
2. `/bin/bash` — checked via `File.exists?/1`
3. `/bin/sh` — always-available fallback

The tool name is "bash" because models generate bashisms; the
resolution prefers bash to match that expectation. On macOS,
`/bin/bash` is bash 3.2 (Apple ships the last GPLv2 version) —
most common bashisms work, but bash 4+ features (associative arrays,
`&>>`, etc.) do not.

#### Execution model

- **Port-based.** `Port.open({:spawn_executable, shell}, opts)` with
  `:stderr_to_stdout`. Gives async chunk-by-chunk output for partial
  capture on timeout.
- **One command per invocation.** No persistent shell session. Each
  `call/2` spawns a fresh process.
- **Monotonic deadline.** Computed once at entry as
  `System.monotonic_time(:millisecond) + timeout`. Each receive loop
  iteration uses the remaining time, so a stream of output chunks
  can't reset the timeout.
- **Timeout cleanup.** `Port.close/1` sends SIGHUP to the process
  group. Remaining messages are drained from the mailbox.

#### Output handling

- **Merged stdout/stderr.** Via `:stderr_to_stdout` on the Port.
  Models rarely need to distinguish the two streams.
- **Tail-biased truncation.** When output exceeds `:max_output`, the
  beginning is discarded and the tail is kept — the most recent
  output is the most diagnostic for shell commands (build errors,
  test failures, command results).
- **Line-snapped.** After taking the last N bytes, the truncation
  point snaps forward to the next newline to avoid a partial first
  line. A notice is prepended:
  `...(truncated, showing last 48.8KB of 1.2MB)`.
- **Empty output.** When a command succeeds with no output, the tool
  returns `"(no output)"` so the model gets a clear signal.

#### Safety boundary

The tool executes arbitrary shell commands with full system access.
It is not a security boundary — there is no command allowlist,
denylist, or argument sanitization. OS-level sandboxing (containers,
restricted users, chroot) is the caller's responsibility. This is
documented in the Runner moduledoc and in the tool description shown
to the model.

#### Known boundaries

- No persistent state between invocations — env vars, shell
  variables, working directory changes are not carried over.
- `Port.close/1` sends SIGHUP, not SIGKILL. A process that traps
  signals or has detached children may survive.
- `binary_part` truncation can split multi-byte UTF-8 codepoints at
  the cut point (same caveat as Sandbox).
- Command prefix is string concatenation with a newline separator,
  not shell-level escaping.

### 3.4 `Omni.Tools.WebFetch`

Fetches content from URLs, simplifies it for LLM consumption.

#### Module layout

```
lib/omni/tools/web_fetch.ex                    # Omni.Tool implementation (thin)
lib/omni/tools/web_fetch/fetcher.ex             # HTTP orchestration, batch, truncation
lib/omni/tools/web_fetch/strategy.ex            # Strategy behaviour + resolution
lib/omni/tools/web_fetch/strategy/default.ex    # Generic content handler
lib/omni/tools/web_fetch/strategy/github.ex     # GitHub raw file redirect
lib/omni/tools/web_fetch/strategy/reddit.ex     # Reddit JSON extraction
```

**`Omni.Tools.WebFetch`** — the tool module. `use Omni.Tool`, `init/1`,
`schema/1`, `description/1`, `call/2`. Thin; delegates to `Fetcher` for
all real work.

**`Omni.Tools.WebFetch.Fetcher`** — HTTP orchestration engine. Builds
Req requests, dispatches to strategies, handles batch via
`Task.async_stream`, applies head-biased truncation. Independently
usable without the tool machinery.

**`Omni.Tools.WebFetch.Strategy`** — public module defining the strategy
behaviour and providing `resolve/1` (normalizes strategy specs) and
`find/2` (first-match dispatch). Strategies are the extensibility
mechanism for site-specific content extraction.

**`Omni.Tools.WebFetch.Strategy.Default`** — catch-all strategy.
Content-type dispatch: HTML → Markdown (via `html2markdown`), JSON →
pretty-printed, `text/*` → passthrough, everything else → metadata.

**`Omni.Tools.WebFetch.Strategy.GitHub`** — matches `github.com` blob
URLs. Rewrites to `raw.githubusercontent.com` so the LLM gets the raw
file content instead of the GitHub HTML page. Non-blob GitHub URLs
(issues, PRs, repo pages) fall through to the Default strategy.

**`Omni.Tools.WebFetch.Strategy.Reddit`** — matches `*.reddit.com`.
Rewrites URL to Reddit's JSON API (`.json` suffix), formats posts and
comments as readable Markdown.

#### Configuration

| Option        | Default      | Effect                                                  |
| ------------- | ------------ | ------------------------------------------------------- |
| `:req`        | `Req.new()`  | Base `Req.Request` struct. Full transport control.      |
| `:strategies` | `[]`         | User strategies prepended before Default catch-all.     |
| `:max_output`   | `100_000`    | Head-biased truncation per URL (bytes). `:infinity` to disable. |
| `:max_urls`   | `10`         | Maximum URLs per batch call.                            |
| `:timeout`    | `15_000`     | HTTP receive timeout (ms). Merged onto Req.             |

All options support application config (see § 4).

#### Strategy behaviour

Strategies implement `Omni.Tools.WebFetch.Strategy`:

- `match?(URI.t(), opts)` (required) — returns `true` if this strategy
  handles the URL.
- `request(Req.Request.t(), opts)` (optional) — modifies the request
  before execution (URL rewriting, custom headers, adapter attachment).
  Receives the fully-built `Req.Request` and returns a modified one.
- `extract(Req.Response.t(), opts)` (required) — converts the response
  to a content string.

Strategy resolution follows the extension pattern: `{module, opts}` or
bare `module` → `{module, []}`. Validated at init time via
`Code.ensure_loaded/1` + `function_exported?/3`. User strategies are
prepended; the built-in strategies (GitHub, Reddit, Default) are
appended in that order, with Default as the catch-all.

The `:req` option accepts a pre-configured `Req.Request` struct,
enabling downstream apps to attach custom middleware (e.g. browser TLS
impersonation via CloakedReq) without the tool needing to know about it.

#### Fetch flow

1. Parse URI → iterate strategies calling `match?/2` → first match wins.
2. Build per-request Req: base `:req` struct + URL + timeout + strategy
   `request/2` modification.
3. Execute via `Req.request/1`. Decode is disabled (`decode_body: false`)
   so strategies always receive raw binary bodies.
4. On success (2xx): call `extract/2` → head-biased truncation.
5. On HTTP error (4xx/5xx): return inline content (the tool executed
   successfully — the server responded with an error status).
6. On network error (Req returns `{:error, exception}`): raise. The
   tool failed to execute — connection refused, DNS failure, timeout.

Batch: `Task.async_stream` with `max_concurrency: 3`. HTTP errors are
isolated per-URL (inline content). Network errors raise the whole batch
(if one URL can't connect, the rest likely can't either). Single URL
returns content directly; multiple URLs return sections separated by
`## {url}` headers and `---` dividers.

#### Truncation

Head-biased (keeps the beginning — opposite of Bash's tail-biased).
Snaps back to the last newline before the cut point. Appends:
`...(truncated, showing first X of Y)`.

#### Dependencies

- `html2markdown` (~> 0.3) — pure Elixir HTML-to-Markdown converter.
  Depends on Floki. Handles content extraction (strips nav, scripts,
  styles, boilerplate) as part of conversion.
- `plug` (~> 1.0, test only) — required for `Req.Test.stub` plug-based
  HTTP stubbing in tests.

#### Known boundaries

- **No TLS fingerprint bypass.** Erlang/OTP's ssl module cannot
  impersonate browser TLS fingerprints (JA3/JA4). Some Cloudflare-
  protected sites will block requests. Downstream apps can work around
  this by attaching CloakedReq (Rust NIF) to the `:req` option.
- **No binary content extraction.** PDF, DOCX, images return metadata
  only (content-type + size). No pure-Elixir PDF text extraction exists.
- **No JavaScript rendering.** JS-heavy SPAs return the initial HTML
  shell, not the rendered content.
- **Encoding.** Charset conversion is best-effort: invalid UTF-8 bytes
  are dropped via `:unicode.characters_to_binary/2`. No `<meta charset>`
  parsing.
- **`binary_part` truncation** can split multi-byte UTF-8 codepoints at
  the cut point (same caveat as Bash/Repl).

---

## 4. Cross-cutting decisions

### Application configuration

Every tool supports the same three-layer configuration merge in
`init/1`:

```
module defaults → app config → explicit opts
```

Any option can be set at any layer. Explicit opts to `new/1` always
win. Application config is keyed under `:omni_tools` by tool module
name:

```elixir
# config/runtime.exs
config :omni_tools, Omni.Tools.Bash, timeout: 60_000, env: [{"MIX_ENV", "prod"}]
config :omni_tools, Omni.Tools.Repl, max_output: 100_000
config :omni_tools, Omni.Tools.WebFetch, timeout: 30_000
config :omni_tools, Omni.Tools.FileSystem, read_only: true
```

App config is never required — tools must work with zero app config
and sensible module-level defaults. Required options with no default
(`:dir`, `:base_dir`) still raise if missing after the merge.

---

## 5. Module layout

To be filled in once the first tool is ported. Expected shape:

```
lib/omni/tools/
├── file_system.ex                # public tool module
├── file_system/                  # @moduledoc false helpers
├── repl.ex
├── repl/
├── bash.ex
├── bash/
├── web_fetch.ex
└── web_fetch/
```

Helpers internal to a tool live under that tool's namespace, marked
`@moduledoc false`. There is no shared `Omni.Tools` module to put
cross-cutting helpers in — if shared logic emerges that's a signal
worth questioning, not an automatic abstraction.
