# CLAUDE.md

Guidance for Claude Code working in `omni_tools`. This file covers what
to know as a developer on this codebase and the conventions to follow.
For the design intent and the state of the work, see
`context/design.md` and `context/roadmap.md`.

## What this package is

`omni_tools` is a small, opinionated set of **reference tools** for the
[Omni](https://github.com/aaronrussell/omni) ecosystem. Each tool is an
`Omni.Tool` implementation that ships ready-to-use *and* serves as a
worked example of how to build tools for LLMs. The four tools currently
in scope:

- `Omni.Tools.FileSystem` — CRUD over a configurable base directory,
  with read-only / flat / nested scope modes.
- `Omni.Tools.Repl` — evaluates Elixir code in a sandboxed REPL with
  pluggable extensions that inject modules into the runtime.
- `Omni.Tools.Bash` — executes shell commands. Shape still being
  worked out.
- `Omni.Tools.WebFetch` — fetches URLs, simplifies content (HTML →
  Markdown), supports batch fetch and configurable size limits.

That list is the whole package. We are deliberately strict about scope
— see [Scope rules](#scope-rules).

This is the **third package** of the Omni family:

```
omni_tools         — reference Omni.Tool implementations (this package)
omni_agent         — stateful agents, sessions, persistence
omni               — stateless LLM API (providers, dialects, streaming)
```

`omni_tools` depends only on `omni`. Nothing in the Omni stack depends
on `omni_tools` — apps that want these tools opt in.

## Build & test commands

```bash
mix compile                    # Compile
mix test                       # Run all tests
mix test path/to/test.exs      # Single file
mix test path/to/test.exs:42   # Single test by line
mix format                     # Format
mix format --check-formatted   # CI formatting check
```

## Dependencies

- **`omni`** — the stateless LLM API package, source of `Omni.Tool`,
  `Omni.Schema`, and the content blocks. Local path dep during
  development, hex dep for release.

Beyond that, **proportionate** hex dependencies are fine — a Markdown
converter for `WebFetch`, an HTTP client (Req), etc. — but the package
must remain trivially installable. See [Scope rules](#scope-rules).

## Scope rules

These are firm. They exist because this package is meant to be a
clean, maintainable reference — not an open-ended toolbox.

- **No third-party service integrations.** No Slack, GitHub, Linear,
  search APIs, etc. Those belong in downstream packages.
- **No external runtimes.** No Python sidecars, no Node bridges, no
  Docker dependencies for the package itself (a tool *user* may
  configure one — `Bash` running inside a container is the user's
  choice to wire up, not ours).
- **No fragile NIFs.** Pure Elixir or stable hex packages with
  pure-Elixir or well-established native deps only. If a dep needs
  manual compilation steps to install, it doesn't belong here.
- **Reference-quality, not best-in-class.** The bar is "clear,
  correct, broadly useful, and easy to read." We are not trying to
  ship the most secure sandbox or the fastest HTML simplifier — just
  solid examples that work and that other developers can fork or
  extend.
- **The four tools listed above are the package.** New tool
  proposals should go to a separate package or be argued for in
  `context/roadmap.md` first — don't just add a fifth.

## Conventions

### Tool authoring

- Every tool is a module using `use Omni.Tool, name: "...",
  description: "..."`. Implement `schema/0` and `call/1` (or
  `init/1` + `call/2` when the tool needs configuration).
- Configuration goes through `init/1`. Callers pass options to
  `Tool.new/1`; the returned `%Omni.Tool{}` carries a closure over
  the resolved state. Validate aggressively in `init/1` so failures
  surface at construction time, not mid-conversation.
- Use `import Omni.Schema` inside `schema/0` — never at module level.
- Tool descriptions are written for the model, not for humans. Keep
  them precise about what the tool does, what arguments it takes,
  and what it returns. Override `description/1` when configuration
  changes the behaviour the model needs to know about (e.g.
  `FileSystem` exposing whether writes are allowed).
- Return strings or simple maps from `call`. The tool result content
  must serialize cleanly when round-tripped through a dialect.
- On failure, raise. Omni's tool executor catches the exception and
  feeds it back to the model as a tool error, so the loop continues
  and the model can react. Return values are successful tool results;
  raised errors are tool errors. Don't invent `{:ok, _}` / `{:error, _}`
  tuples or string error results at the `call/1`/`call/2` boundary.

### Terminology

- **Tool use**, not "tool call" (aligns with `omni`).
- A tool's **scope** or **base** refers to the configured boundary
  it operates within (the `FileSystem` base dir, the `Bash` working
  directory, etc.).

### Public vs internal

- All tool modules under `Omni.Tools.*` are public; each must have a
  `@moduledoc`, `@typedoc` for any exported types, and `@doc` +
  `@spec` on public functions.
- Internal helpers (path resolution, content simplification,
  extension wiring) live in nested `@moduledoc false` modules under
  the tool's namespace, e.g. `Omni.Tools.FileSystem.Path`.
- Doc tone: practical, concise, example-driven. Lead with what the
  tool does and how to wire it up. Rely on `@spec` for types — don't
  repeat type info in prose.
- Private functions don't need `@doc`.

### Testing

- Pure-logic tests for input validation, path resolution, and
  configuration handling. No network access, no real shell exec.
- For tools that touch the filesystem, use `tmp_dir: true` test tags
  and lean on ExUnit's automatic cleanup.
- For tools that touch the network (`WebFetch`), use `Req.Test.stub`
  with `plug` (test-only dep, mirrors `omni`'s pattern).
- Where a tool exposes a configuration surface (scope modes,
  extensions, limits), exercise each branch — the configuration
  matrix *is* the contract.

## Development do's and don'ts

### Do

- **Treat each tool as exemplary code.** Other developers will read
  and copy these. If a pattern is awkward in our code it'll be
  awkward in theirs.
- **Lean on `omni` primitives.** `Omni.Schema`, `Omni.Tool`,
  `Omni.Schema.Adapter` — don't reimplement.
- **Run the affected test file before claiming done.** No network
  required for any test.
- **Keep configuration explicit.** Explicit opts to `new/1` always
  take precedence. Application config may provide fallback defaults
  for operational parameters (timeouts, limits) but is never
  required — tools must work with zero app config and sensible
  defaults.

### Don't

- **Don't add deps casually.** Each new hex dep is a long-term
  commitment for a package whose value is being lightweight.
- **Don't reach for NIFs or external runtimes** to make a tool faster
  or fancier — write a simpler tool instead.
- **Don't try to be a security boundary.** These tools have safety
  rails (path scoping, command allowlists, fetch limits) but they
  are not a replacement for OS-level sandboxing. Document the
  boundary; don't pretend it's stronger than it is.
- **Don't bake third-party service knowledge into the package.** If a
  tool needs to know about Slack or GitHub specifically, it's the
  wrong package.

## Where to look

- **Design** — `context/design.md`. Detailed intent for each tool
  and for cross-cutting design decisions.
- **Roadmap** — `context/roadmap.md`. Active work and parked ideas.
- **Sister packages** — `../omni` (LLM API) and `../omni_agent`
  (stateful agents). Their `context/design.md` files are useful
  background, especially `omni`'s tool / schema sections.
- **Feedback / help** — `/help` or
  https://github.com/anthropics/claude-code/issues.
