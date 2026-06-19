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

## 1.25.0 - 2026-06-19

### Added
- Added CI/CD and workflow automation guidance.
- Added `docs/ci-cd-guidelines.md` for safe CI/CD changes, validation, and staged adoption.
- Added CI/CD completion checklist guidance.

### Changed
- Clarified that CI/CD workflow, deployment, secret, permission, and release automation changes require explicit task scope.
- Updated README links and sync metadata for pack version `1.25.0`.

## 1.24.0 - 2026-06-19

### Added
- Added comment discipline guidance for code, scripts, public API documentation, and generated documentation.
- Added summary discipline guidance for task summaries, PR summaries, and agent completion notes.
- Added examples showing useful comments versus obvious/noisy comments.

### Changed
- Updated completion and PR checklists to include concise comments/summaries.
- Bumped sync script metadata to pack version `1.24.0`.

## 1.23.0 - 2026-06-19

### Added
- Added mandatory Git/PR preflight guidance before agents create branches, start duplicate work, or open pull requests.
- Added duplicate-work protection for changes already merged into `develop` or already covered by an existing open PR.
- Added generic-example guidance so shared templates avoid project-specific enum/domain names.

### Changed
- Updated sync script metadata to pack version `1.23.0` and added remote fetch/prune during branch preparation unless skipped.
- Updated C# examples to use the generic `OrderStatusEnum` example instead of project-specific terminal enums.

## 1.22.0 - 2026-06-19

### Changed
- Renamed the repo-seed sync script from a versioned filename to the stable path `scripts/sync-agent-guidelines.py` so Git history tracks script changes cleanly.
- Clarified script filename/versioning guidance: scripts committed to a repository should use stable filenames, while distributed standalone copies, generated output files, and archive artifacts may use semantic-version suffixes.
- Updated sync examples, README links, and managed-file manifest paths to use the stable sync script name.

## 1.21.0 - 2026-06-19

### Added
- Added `scripts/sync-agent-guidelines.py` for syncing this pack from `repo-seed` into other repositories.
- Added `.agent-guidelines-version` to track the synced pack version in target repositories.
- Added repo-seed sync workflow guidance.
- Added managed-file hash tracking through `.agent-guidelines-manifest.json`.
- Added conservative conflict behavior that writes incoming versions under `.agent-guidelines-conflicts/`.
- Added separated Python and shell script convention files.

### Changed
- Replaced mixed branch type policy with strict Git Flow branch families: `feature/*`, `release/*`, and `hotfix/*`.
- Set `develop` as the default integration branch, normal PR target, and recommended hosted default branch for Git Flow repositories.
- Clarified that normal documentation, tests, refactors, chores, and non-emergency bug fixes use `feature/*` branches under strict Git Flow.
- Renamed the central guideline source example from `project-seed` to `repo-seed`.

## 1.19.0 - 2026-06-19

### Added
- Added unified branch type table and branch naming policy.
- Added explicit PR creation/proposal policy so agents do not randomly skip pull requests.
- Added fallback PR reporting requirements when PR creation is unavailable.

### Changed
- Clarified when to use `feature`, `bugfix`, `docs`, `test`, `refactor`, `chore`, `release`, and `hotfix` branches.
- Updated PR checklist to verify branch type, branch naming, and PR target.

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
