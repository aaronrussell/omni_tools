# Roadmap

Work tracking for `omni_tools`. This is a live document — add to it
freely, clean it up as items land or get rethought.

---

## Scheduled

*(empty)*

---

## Parked ideas

- **Config sanity check** — review all four tools' use of application
  config vs runtime options. The three-layer merge (module defaults →
  app config → explicit opts) was established early; check it still
  makes sense now that tools have settled (e.g. Files accepting `:fs`
  bypasses the merge entirely). Look for options that don't belong in
  app config, missing defaults, or inconsistencies between tools.
