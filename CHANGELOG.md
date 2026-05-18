# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-05-18

### Added

- **WebSearch** — web search tool with a pluggable provider backend. Ships with Brave, Serper, and Tavily providers. API keys resolve via `{:system, "ENV_VAR"}` tuples (matching the omni provider pattern). The model can control result count and recency filtering; additional provider-specific options pass through as-is.

### Changed

- **Naming** — behaviour implementations now use plural namespaces (`Strategies.*`, `Providers.*`) for consistency with `omni`'s `Providers`/`Dialects` pattern and idiomatic Elixir convention (à la Ecto).
- **Repl / Sandbox** — peer nodes now communicate over stdio (`connection: :standard_io`) instead of Erlang distribution. This removes the dependency on EPMD and `ensure_distributed!/0` (which has been removed). Peer boot is faster and no longer subject to intermittent hangs from EPMD/port contention.
- **Files** / **Files extension** — both now accept either a pre-built `%FS{}` struct via the `:fs` option or raw options (`:base_dir`, `:read_only`, `:nested`), so callers using both can share a single FS.
- **Files.FS** — `base_dir` no longer needs to exist at init time. The directory is created automatically on the first write.

## [0.2.0] - 2026-05-11

### Changed

- **FileSystem → Files** — renamed `Omni.Tools.FileSystem` to `Omni.Tools.Files` (and all sub-modules). The tool provides scoped file CRUD, not full filesystem access — "Files" better reflects the bounded nature of the tool.

### Added

- **Files REPL extension** (`Omni.Tools.Repl.Extensions.Files`) — bridges the Files tool into the REPL sandbox, injecting a `Files` module so agent code can read and write files directly without a separate tool use round-trip.

## [0.1.0] - 2026-05-08

Initial release — a small, opinionated set of reference tools for the
[Omni](https://github.com/aaronrussell/omni) ecosystem.

### Added

- **FileSystem** — file CRUD scoped to a configurable base directory, with read-only, flat, and nested scope modes.
- **Repl** — evaluates Elixir code in a sandboxed REPL with pluggable extensions for injecting modules into the runtime.
- **Bash** — executes shell commands with configurable working directory.
- **WebFetch** — fetches URLs and simplifies HTML to Markdown, with support for batch fetching and configurable size limits.

---

[Unreleased]: https://github.com/aaronrussell/omni_tools/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/aaronrussell/omni_tools/releases/tag/v0.3.0
[0.2.0]: https://github.com/aaronrussell/omni_tools/releases/tag/v0.2.0
[0.1.0]: https://github.com/aaronrussell/omni_tools/releases/tag/v0.1.0
