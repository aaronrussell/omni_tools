# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-08

Initial release — a small, opinionated set of reference tools for the
[Omni](https://github.com/aaronrussell/omni) ecosystem.

### Added

- **FileSystem** — file CRUD scoped to a configurable base directory, with read-only, flat, and nested scope modes.
- **Repl** — evaluates Elixir code in a sandboxed REPL with pluggable extensions for injecting modules into the runtime.
- **Bash** — executes shell commands with configurable working directory.
- **WebFetch** — fetches URLs and simplifies HTML to Markdown, with support for batch fetching and configurable size limits.

---

[Unreleased]: https://github.com/aaronrussell/omni_tools/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/aaronrussell/omni_tools/releases/tag/v0.1.0
