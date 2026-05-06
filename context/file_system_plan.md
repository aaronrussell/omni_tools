# `Omni.Tools.FileSystem` — Implementation Plan

This is the working plan for porting and reshaping the `FileSystem`
tool from `omni_ui` into `omni_tools`. It is split into two **primary
phases**:

- **Phase 1 — Foundations.** Ships the data types (`Scope`, `Entry`)
  and the public FS operations on `Omni.Tools.FileSystem`, fully
  tested. Self-contained; no upstream dependency. **Stop after Phase 1
  and wait for the user to confirm before starting Phase 2.**
- **Phase 2 — Tool integration.** Adds the `Omni.Tool` callbacks on
  top of the foundation. **Blocked** on an `omni` release exposing a
  `schema/1` callback — the user is driving that work in parallel
  (tracked in `omni`'s roadmap).

Both phases share the design decisions captured below; a fresh session
should be able to read this file and CLAUDE.md and pick up the work.

---

## Reference material

- Existing port source — `/Users/aaron/Dev/ai/omni_ui/lib/omni_ui/artifacts/`
  - `file_system.ex` — operations
  - `tool.ex` — Omni.Tool wrapper (artifact-flavoured; description
    will be rewritten for omni_tools, not copied)
  - `artifact.ex` — analogue of our `Entry` struct
- Existing tests for inspiration — `/Users/aaron/Dev/ai/omni_ui/test/omni_ui/artifacts/`
- `Omni.Tool` behaviour — `/Users/aaron/Dev/ai/omni/lib/omni/tool.ex`
- Repo conventions — `CLAUDE.md`
- Tool design intent — `context/design.md § 3.1`

---

## Decisions (locked in)

These were settled during design. Treat as fixed unless the user
revisits.

### Module layout

```
lib/omni/tools/file_system.ex          # public Tool + public FS ops
lib/omni/tools/file_system/scope.ex    # %Scope{} + path resolution
lib/omni/tools/file_system/entry.ex    # %Entry{} result struct
```

`Omni.Tools.FileSystem` does double duty: it implements `Omni.Tool`
(via `use Omni.Tool`) **and** exposes a public FS API
(`FileSystem.read/2`, `write/3`, `list/1`, `patch/4`, `delete/2`). The
`Omni.Tool` callbacks are tagged with `@impl Omni.Tool`; the public
ops carry `@doc` + `@spec`. Moduledoc explains both roles.

The Tool's `init/1` builds a `%Scope{}` and the `call/2` dispatcher
routes commands through the public ops. Outside callers who want the
standalone FS API construct a `Scope` directly and use the same ops.

### Configuration shape

Two orthogonal booleans on `Tool.new/1` (and on `Scope.new/1`):

| Option       | Default | Effect                                                         |
| ------------ | ------- | -------------------------------------------------------------- |
| `:base_dir`  | (req'd) | Absolute path. Created if missing.                             |
| `:read_only` | `false` | When `true`, only `read` and `list` are available.             |
| `:nested`    | `true`  | When `false` (flat), paths cannot contain path separators.     |

Defaults give the agent the broadest capability; callers opt in to
restrictions.

### Path policy

Applies to every user-supplied id (filename / path).

- Relative only. Reject absolute (`/foo`, `~/foo`), any `..` segment,
  null bytes.
- Dotfiles and dot-directories are **allowed** in nested mode and
  **listed** by `list/1` (consistency: if we allow them, we surface
  them).
- In flat mode, additionally reject path separators (`/`, `\`).
- On `write/3` in nested mode, parent directories are created
  automatically (`File.mkdir_p`).

### Operations contract

- `read(scope, id)` → binary
- `write(scope, id, content)` → `%Entry{}`
- `patch(scope, id, search, replace)` → `%Entry{}`. **Unique-required:**
  raises if `search` appears zero or more than once. (Stricter than
  the omni_ui port's first-occurrence semantics; safer for model use.)
- `list(scope)` → `[%Entry{}]`. Recursive in nested mode, flat in flat
  mode. Sorted by `id`. Includes dotfiles / dot-directories.
- `delete(scope, id)` → `:ok`

### Error convention

Operations **raise** on failure. Omni's tool executor catches
exceptions and surfaces them to the model as tool errors; the loop
continues. No `{:error, _}` tuples or string error returns at the
public boundary. (Internal `Scope.resolve/2` may use tuple returns;
the boundary converts to raises.)

### Struct shapes

```elixir
%Omni.Tools.FileSystem.Scope{
  base_dir: String.t(),    # absolute, normalised
  read_only?: boolean(),
  nested?: boolean()
}

%Omni.Tools.FileSystem.Entry{
  id:         String.t(),  # base-relative full path, e.g. "sub/foo.txt"
  filename:   String.t(),  # basename, derived from id
  media_type: String.t(),  # via MIME.from_path/1
  size:       non_neg_integer(),
  mtime:      DateTime.t()
}
```

`id` is the single round-trippable identifier the model uses for any
subsequent command. `filename`, `media_type` are derived in
`Entry.new/2` from the id and a `%File.Stat{}`.

### Dependencies

Promote `mime` from a transitive dep (via `omni → req`) to a direct
dep in `mix.exs`. Small, mainstream, and we use it by name — relying
on it transitively is fragile.

### Naming the schema argument

The Tool's schema takes a single id-style argument. **Argument name:
`id`** (matches the `Entry` field). One name across both modes; in
flat mode `id` is a bare filename, in nested mode it's a relative
path.

---

## Phase 1 — Foundations

Ships `Scope`, `Entry`, and the public FS ops on
`Omni.Tools.FileSystem` (without `use Omni.Tool` yet — purely the FS
API). Fully tested. Self-contained.

At the end of Phase 1: `mix test` green, `mix format --check-formatted`
clean, `mix compile --warnings-as-errors` clean. **Stop and report
back; do not start Phase 2 without explicit user confirmation.**

### 1.1 — `Omni.Tools.FileSystem.Scope`

File: `lib/omni/tools/file_system/scope.ex`

Public API:

```elixir
@spec new(keyword()) :: t()
def new(opts)
# Required: :base_dir
# Optional: :read_only (default false), :nested (default true)
# Validates base_dir is absolute. Creates dir if missing (File.mkdir_p).
# Raises ArgumentError on bad opts (CLAUDE.md: "validate aggressively
# in init/1").

@spec resolve(t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
def resolve(scope, id)
# Returns absolute path under scope.base_dir, or an error string.
# Rejects:
#   - empty id
#   - absolute id ("/foo", "~/foo")
#   - ".." segments anywhere
#   - null bytes
#   - in flat mode: any path separator (/, \)
# Internal use; the public ops convert errors to raises.
```

Internal helpers (private):

- `validate_id(scope, id)` — runs the policy checks, returns `:ok`
  or `{:error, reason}`.
- Whatever else falls out — keep flat, no premature abstractions.

Tests: `test/omni/tools/file_system/scope_test.exs`

Cover the path-validation matrix:

- `Scope.new/1` accepts valid opts, rejects missing `:base_dir`,
  rejects relative `:base_dir`, creates the directory.
- Default values for `:read_only` and `:nested`.
- `Scope.resolve/2` accepts valid ids in flat and nested modes.
- `Scope.resolve/2` rejects: empty, absolute, `..` segment (leading,
  middle, trailing), null bytes, path separators in flat mode.
- Dotfiles and dot-dirs accepted in both modes.

Use `tmp_dir: true` for tests that create directories.

### 1.2 — `Omni.Tools.FileSystem.Entry`

File: `lib/omni/tools/file_system/entry.ex`

Public API:

```elixir
defstruct [:id, :filename, :media_type, :size, :mtime]

@type t :: %__MODULE__{
  id: String.t(),
  filename: String.t(),
  media_type: String.t(),
  size: non_neg_integer(),
  mtime: DateTime.t()
}

@spec new(String.t(), File.Stat.t()) :: t()
def new(id, %File.Stat{} = stat)
# Derives filename via Path.basename/1.
# Derives media_type via MIME.from_path/1.
# mtime from posix stat (stat.mtime is a posix integer when stat
# was taken with time: :posix).
```

Tests: `test/omni/tools/file_system/entry_test.exs`

- Builds correctly from id + stat.
- `filename` is the basename of `id` (test with both flat and
  nested-style ids).
- `media_type` is set via MIME for known extensions (`.html`,
  `.json`) and falls back to `application/octet-stream` for unknown.
- `mtime` is a `DateTime`.

### 1.3 — Public FS ops on `Omni.Tools.FileSystem`

File: `lib/omni/tools/file_system.ex` (no `use Omni.Tool` yet — that
is Phase 2)

Public API:

```elixir
@spec read(Scope.t(), String.t()) :: binary()
def read(scope, id)
# Resolves id, reads file. Raises on resolve error or missing file.

@spec write(Scope.t(), String.t(), binary()) :: Entry.t()
def write(scope, id, content)
# Raises if scope.read_only?. Resolves id. mkdir_p parents (nested
# mode only — in flat mode parents == base_dir, already exists).
# Writes file. Returns Entry.

@spec patch(Scope.t(), String.t(), String.t(), String.t()) :: Entry.t()
def patch(scope, id, search, replace)
# Raises if scope.read_only?. Reads existing file. Counts occurrences
# of `search`. Raises if 0 or >1. Replaces, writes, returns Entry.

@spec list(Scope.t()) :: [Entry.t()]
def list(scope)
# In flat mode: ls base_dir, regular files only, sorted.
# In nested mode: walk recursively, yield ids relative to base_dir,
# regular files only (skip directories themselves), sorted by id.
# Includes dotfiles and dot-directories.
# Returns [] if base_dir is empty (it always exists per Scope.new/1).

@spec delete(Scope.t(), String.t()) :: :ok
def delete(scope, id)
# Raises if scope.read_only?. Resolves id. Deletes file. Raises if
# missing.
```

Failure modes raise — pick `ArgumentError` for policy violations
(read-only writes, invalid ids that bypassed `Scope.resolve/2`),
`File.Error` for FS-level failures (missing file on read/delete,
permission errors, etc.). Use `File.read!/1`, `File.write!/2`,
`File.rm!/1` where convenient — they raise `File.Error` with a useful
message already.

Tests: `test/omni/tools/file_system_test.exs`

Use `tmp_dir: true` and a small helper that builds a scope from `ctx`
and mode flags. Cover each op in **both** flat and nested modes:

- `read` — happy path; missing file raises; resolve-rejected id raises.
- `write` — happy path; overwrites existing; creates parent dirs in
  nested mode; raises on read-only scope; rejects bad ids.
- `patch` — unique match replaces and returns Entry; zero matches
  raises; multiple matches raises; missing file raises; raises on
  read-only scope.
- `list` — empty dir → `[]`; lists regular files; recursive in nested
  mode (returns ids like `"sub/dir/file.txt"`); ignores directories
  themselves; **does** include dotfiles / dot-dirs; sorted by id.
- `delete` — happy path; missing file raises; raises on read-only
  scope.

Then a small set of read-only-mode tests asserting that `write`,
`patch`, and `delete` raise.

### Phase 1 acceptance

- All three modules implemented with `@moduledoc`, `@typedoc` (where
  types are exported), `@doc` and `@spec` on public functions.
- Test files green via `mix test`.
- `mix format --check-formatted` clean.
- `mix compile --warnings-as-errors` clean.
- `mime` added as a direct dep in `mix.exs`; `mix.lock` updated.
- Quick sanity loop: launch `iex -S mix`, build a `%Scope{}`, run a
  write+read+list cycle, see Entries come back.

---

## STOP — wait for confirmation

**Do not proceed to Phase 2 until the user explicitly says so.**

Reasons to halt here:

1. Phase 2 depends on `omni` shipping a `schema/1` callback (tracked
   on `omni`'s roadmap; user is driving that work in parallel). Phase
   1 is fully usable on its own as a standalone FS API.
2. The user wants a checkpoint to review Phase 1 before integration.
3. A different session may pick up Phase 2 — that session should re-
   read this file and CLAUDE.md before starting.

When the user gives the green light for Phase 2, also confirm that
the local `omni` dep has been bumped to a version exposing
`schema/1`, and that the callback's signature matches what's used
below.

---

## Phase 2 — Tool integration

Adds the `Omni.Tool` callbacks on top of the Phase 1 foundation.
Requires `omni`'s `schema/1` callback.

### 2.1 — Tool callbacks on `Omni.Tools.FileSystem`

Same file: `lib/omni/tools/file_system.ex`. Add:

```elixir
use Omni.Tool,
  name: "file_system",
  description: "..."   # base description; description/1 may extend
```

Implement:

```elixir
@impl Omni.Tool
def init(opts)
# Builds and returns a %Scope{}. Scope.new/1 raises on bad input,
# which surfaces as a Tool.new/1 failure (correct — caller fixes it
# at construction time, not mid-conversation).

@impl Omni.Tool
def schema(scope)
# Dynamic schema. The `command` enum lists only the commands
# available under scope.read_only?:
#   read_only -> [:read, :list]
#   else      -> [:read, :list, :write, :patch, :delete]
# Other properties: id (string), content (string, used by write),
# search/replace (strings, used by patch). Required: [:command].

@impl Omni.Tool
def description(scope)
# Plain-language description tailored to the configured scope.
# Mentions: base directory (or a friendly redaction — see open
# questions), whether writes are allowed, whether subdirectories are
# allowed, the available commands, the path/id rules.
# Reference-quality writing — other tool authors will read this.

@impl Omni.Tool
def call(input, scope)
# Dispatch on input.command:
#   :read   -> FileSystem.read(scope, input.id)
#   :list   -> FileSystem.list(scope) |> format_list/1
#   :write  -> FileSystem.write(scope, input.id, input.content) |> format_write/1
#   :patch  -> FileSystem.patch(scope, input.id, input.search, input.replace) |> format_patch/1
#   :delete -> FileSystem.delete(scope, input.id) ; "Deleted #{id}"
# Handlers raise on failure — Omni surfaces those to the model.
```

Response formatting (string returns, model-facing):

- `read` — return raw content.
- `list` — `"id (media_type, N bytes)"` per line, joined with
  newlines. Empty list → `"No files"` (or similar).
- `write` — `"Wrote #{id} (#{size} bytes)"`.
- `patch` — `"Patched #{id} (#{size} bytes)"`.
- `delete` — `"Deleted #{id}"`.

Tests: extend `test/omni/tools/file_system_test.exs` (or split into
`tool_test.exs` if the file gets large).

Light coverage at this layer — the heavy lifting was in Phase 1.

- `Tool.new/1` returns `%Omni.Tool{}` with the right `name`.
- Schema enum includes only `read`/`list` when `read_only: true`;
  full enum otherwise.
- `description` mentions whether writes are allowed and whether
  subdirectories are allowed.
- Dispatch correctness for each command (one happy-path call per
  command via `tool.handler`).
- A read-only-mode call to `write` raises (the model would see a
  tool error).

### 2.2 — Polish

- Update `context/design.md § 3.1` from sketch to implemented
  contract — module layout, mode flags, path policy, struct shapes.
  Cross out the open questions, replace with what we shipped.
- Update `context/roadmap.md` — mark `FileSystem` complete; flag
  what's unblocked next (`Repl`).
- Final `mix test`, `mix format --check-formatted`, `mix compile
  --warnings-as-errors`.

### Phase 2 acceptance

- `Omni.Tools.FileSystem.new/1` returns a `%Omni.Tool{}` with handler,
  schema, and description that all reflect the configured scope.
- All tests green.
- `context/design.md` and `context/roadmap.md` updated.

---

## Open / deferred questions

Things we noticed but explicitly chose not to resolve up front. Park
here so a future pass can pick them up.

- **Description redaction.** Should `description/1` show the absolute
  `base_dir` to the model, or a friendlier label? The agent doesn't
  need the absolute path to use the tool, but it's not sensitive in
  most use cases. Decision: show the absolute path for now; revisit if
  a real use case argues otherwise.
- **Symlinks.** Behaviour under symlinks isn't specified. Phase 1
  inherits whatever `File.*` does (follows them). Out of scope to
  fully sandbox. Document this in the moduledoc as a known boundary.
- **Large files.** No size cap on `read`. A pathological file could
  blow the model's context. Out of scope for the first cut; a
  `:max_read_bytes` knob could be added later if real use surfaces it.
- **Concurrent writes.** No locking. The reference tool isn't a
  database. Document and move on.
