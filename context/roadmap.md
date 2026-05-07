# Roadmap

Active and near-term work for `omni_tools`. The package is at the
start of its life — the roadmap right now is the path to a first
release with the four reference tools in place.

This is a live document. Add to it freely; clean it up as items land
or get rethought.

---

## Scheduled

### Initial four tools

The package's whole scope, in the order we're likely to tackle them.
Two are ports of working code from another project; two need design
work first.

- ~~**`Omni.Tools.FileSystem`**~~ — **done.** Ported, reviewed, and
  tested. See `context/design.md § 3.1` for the implemented contract.

- ~~**`Omni.Tools.Repl`**~~ — **done.** Ported, reviewed, and tested.
  Extension mechanism reworked: `Extension` is now a struct + behaviour
  supporting both module-based and inline extensions. See
  `context/design.md § 3.2`.

- **`Omni.Tools.Bash`** — design pass, then implementation. Open
  questions captured in `context/design.md § 3.3`: configuration
  surface, single-tool vs. family, streaming output, safety boundary
  story. Worth a short written design before code.

- **`Omni.Tools.WebFetch`** — design pass, then implementation. Open
  questions in `context/design.md § 3.4`: Markdown converter choice,
  simplification aggressiveness, batch shape, limit semantics.

No fixed ordering between Bash and WebFetch; the two ports come
first because they unblock real usage.

---

## Parked ideas

Open questions worth thinking about before committing to a shape.
Not scheduled.

*(Empty for now — add as ideas surface during implementation.)*
