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

CRUD operations against a configurable base directory. Existing
implementation in another project — work here is **port, review,
tweak**.

Intent:

- Configurable **base directory** that anchors all paths; relative
  paths in tool calls resolve under it; absolute or `..`-escaping
  paths are rejected.
- Configurable **scope mode** controlling what operations are
  available:
  - `:read_only` — read and list only.
  - `:flat` — read/write within the base, no subdirectories.
  - `:nested` — read/write across the full subtree.
- A single tool surface with sub-operations (read, write, list,
  delete, etc.) selected by argument, rather than one tool per
  operation. The exact split (single tool vs. small family) gets
  finalised during the port.
- Description tuning via `description/1` so the model knows which
  operations are actually available in the current configuration.

### 3.2 `Omni.Tools.Repl`

Evaluates Elixir code in a sandboxed REPL. Existing implementation in
another project — work here is **port, review, tweak**.

Intent:

- Each tool use evaluates a snippet of Elixir, streaming back stdout
  and the result.
- **Pluggable extensions** that inject modules into the REPL runtime
  before evaluation. Extensions are how callers expose capabilities to
  the REPL — for example, a `FileSystem` extension that gives the REPL
  access to a preconfigured directory, or app-specific helpers.
- The "sandbox" is best-effort, not a security boundary (consistent
  with the package's stance on sandboxing). The REPL is for trusted-
  enough use cases — agent-driven experimentation, scratchpad
  computation — not adversarial input. This must be documented
  prominently.

The extension shape, the evaluation contract (timeouts, output
capture, return-value rendering), and how state persists across calls
are all decisions to revisit during the port.

### 3.3 `Omni.Tools.Bash`

Executes shell commands. **No existing implementation — needs specing
out.**

Open questions to resolve before any code lands:

- What's the configuration surface? Working directory, environment
  variables, command allowlist or denylist, timeouts, output size
  caps?
- Single tool that runs arbitrary commands, or a tool family with
  separate primitives (run, read-output, kill)?
- Streaming vs. one-shot? Long-running commands need a story for
  output capture and cancellation.
- How to express the safety boundary in the tool description so the
  model has accurate expectations.

These get worked out in a design pass before implementation begins.

### 3.4 `Omni.Tools.WebFetch`

Fetches content from URLs, simplifies it for LLM consumption. **No
existing implementation — needs specing out.**

Intent:

- **Single fetch** and **batch fetch** in one tool surface. Batch is
  the common case — agents typically read several pages while
  researching.
- **Content simplification** for HTML — convert to Markdown,
  strip boilerplate, drop scripts/styles. Other content types (JSON,
  plain text, PDFs?) pass through with light handling.
- **Configurable limits** to keep the agent's context bounded:
  per-fetch byte cap, total batch cap, optional truncation strategy.
- HTTP via Req (already a transitive dep through `omni`).

Open questions:

- Markdown converter choice — pure-Elixir options exist; pick the
  most maintained one with the smallest dep tree.
- Redirect / robots.txt / authentication policy — keep it minimal
  for the reference tool; surface knobs only when concrete demand
  surfaces.
- How aggressively to simplify HTML, and whether to expose
  configuration of the simplification (terse vs. faithful modes).

---

## 4. Cross-cutting decisions

To be filled in as decisions accumulate. Topics likely to land here:
configuration patterns shared across tools, error shape conventions,
description-writing guidelines, how tools document their safety
boundaries, testing patterns for tools with side effects.

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
