# Changelog

All meaningful user-facing and developer-facing changes should be documented in this file.

Use newest entries first. Do not dump raw git commits here.

## Unreleased

### Added
- 

### Changed
- 

### Fixed
- 

### Removed
- 

### Deprecated
- 

### Security
- 

## 1.18.0 - 2026-06-18

### Changed
- Clarified C# control-flow convention: single-statement guard clauses may omit braces when the controlled statement is on the next line.
- Updated `.editorconfig` to prefer braces only for multiline control blocks.
- Replaced project-specific terminal/output examples with generic examples.

## 1.17.0 - 2026-06-18

### Added
- Added C# spacing convention requiring a blank line after a completed control block before the next independent statement.
- Added examples for spacing between an `if` block and a following `return` statement.

### Changed
- Updated C# quick reference and agent checklist to include completed-control-block spacing.

## 1.16.0 - 2026-06-18

### Added
- Added rule to preserve existing user-facing text/output style, including ASCII vs Unicode punctuation and decorative separators.
- Added C# and script convention examples for plain ASCII separators versus Unicode/box-drawing separators.

### Changed
- Updated agent checklist and convention docs to check terminal/UI/output string consistency.

## 1.15.0 - 2026-06-18

### Added
- Added explicit C# control-flow convention forbidding inline guard statements such as `if (...) return ...;`.
- Added examples showing `return` and `throw` on their own line instead of inline after the condition.

### Changed
- Updated C# quick reference to mention no inline control-flow statements.

## 1.14.0 - 2026-06-15

### Added
- Added `MUST` / `SHOULD` / `MAY` instruction strictness levels.
- Added rule to avoid AI assistant, tool, provider, or model names in branch names, commits, PR text, changelog entries, release notes, and generated helper text.
- Added indentation preservation guidance: use spaces when the existing file/repository uses spaces and tabs when it uses tabs.

### Changed
- Softened Git Flow and PR wording for solo/local repositories while keeping branch isolation and no auto-merge.
- Updated C# and script convention docs to preserve existing indentation style before applying defaults.

## 1.13.0 - 2026-06-12

### Added
- Added `CLAUDE.md` compatibility wrapper for Claude Code.

### Changed
- Updated `AGENTS.md` to version 1.13.
- Collapsed early version-history churn into a clean `1.12.0` baseline entry.
- Softened PR workflow wording for solo/local repositories where hosted PRs are unavailable.

## 1.12.0 - 2026-06-12

### Added
- Baseline public starter pack.
- Included `AGENTS.md`, `README.md`, `CHANGELOG.md`, `FEATURES.md`, `.editorconfig`, `.github/pull_request_template.md`, coding convention docs, and FSD/TSD/GDD templates.
