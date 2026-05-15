# Roadmap

Work tracking for `omni_tools`. This is a live document — add to it
freely, clean it up as items land or get rethought.

---

## Scheduled

- **Flaky Repl peer timeouts** — `Omni.Tools.ReplTest` "call successful
  code execution" (`repl_test.exs:110`) and
  `Omni.Tools.Repl.Extensions.FilesTest` "sandbox integration list
  returns entries after write" (`extensions/files_test.exs:76`) both
  intermittently fail with `(exit) time out` during `:peer.start_it/2`.
  Likely a race under concurrent peer node startup. Investigate whether
  `ensure_distributed!/0` has a timing issue or whether the tests need
  serial execution / longer timeouts.

---

## Parked ideas

- **Config sanity check** — review all four tools' use of application
  config vs runtime options. The three-layer merge (module defaults →
  app config → explicit opts) was established early; check it still
  makes sense now that tools have settled (e.g. Files accepting `:fs`
  bypasses the merge entirely). Look for options that don't belong in
  app config, missing defaults, or inconsistencies between tools.
