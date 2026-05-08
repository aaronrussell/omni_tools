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

- ~~**`Omni.Tools.Bash`**~~ — **done.** Port-based shell execution
  with bash-first resolution, tail-biased output truncation, and
  configurable timeout/env/prefix. See `context/design.md § 3.3`.

- ~~**`Omni.Tools.WebFetch`**~~ — **done.** Extensible strategy pattern
  for site-specific extraction, `html2markdown` for HTML→Markdown,
  GitHub raw-file and Reddit JSON built-in strategies, batch fetch via
  `Task.async_stream`, head-biased truncation. See
  `context/design.md § 3.4`.

---

## Parked ideas

Open questions worth thinking about before committing to a shape.
Not scheduled.

*(Empty for now — add as ideas surface during implementation.)*
