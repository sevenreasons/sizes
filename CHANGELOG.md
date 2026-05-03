# Changelog

## 0.4.0

- Add `--top-dirs [EXT]` to show directories using the most space, optionally filtered by extension.
- Add `--by-dir` for immediate child-directory summaries.
- Improve JSON output with scan metadata and a structured `rows` array.
- Add `--save PATH` with format inference for `.json`, `.csv`, and `.tsv`.
- Expand extension type detection for media, documents, data, databases, models, fonts, and archives.
- Update completions and tests.

## 0.3.1

- Push `--include` filters into the `find` scan where possible.
- Stream `--top-files` candidates instead of storing all matches in memory.
- Add `--max-files N` as a safety valve for huge scans.
- Add `--one-file-system` / `-x` to avoid crossing mount points.
- Use `LC_ALL=C` internally for faster, predictable sorting.
- Use ASCII unit-separator records internally for paths containing tabs.
- Cache extension parsing and type classification in AWK.
- Add optional timing diagnostics with `SIZES_DEBUG_TIMING=1`.
- Show a cheap scanned-file count in the interactive progress line.
- Fix progress counter writes to avoid shell null-byte warnings.
- Add performance and path-robustness tests.

## 0.3.0

- Add `--min-size` and `--min-share` filters.
- Add repeatable `--include` path filtering.
- Add repeatable `--type` filtering for detected file categories.
- Add `--top-files EXT` to show largest files for an extension.
- Add `--depth N` for limited recursive scans.
- Add `--follow` for following symlinks.
- Add scan summary footer with file count, total size, skipped paths, and elapsed time.
- Improve `--upgrade` with `--check` and tagged version selection.
- Update completions and tests.

## 0.2.1

- Add `--upgrade` for self-updating the installed script.
- Add an interactive progress spinner while scanning.
- Delay table output until the scan finishes.
- Add `--no-progress` for disabling the spinner.
- Update completions and tests.

## 0.2.0

- Add `--sort` for sorting by size, files, share, extension, or type.
- Add `--format` with table, TSV, CSV, and JSON output.
- Add repeatable `--exclude` path filtering.
- Add `--group-by type` for type-level summaries.
- Add `--plain` ASCII output mode.
- Expand extension type detection.
- Update completions and tests for the new CLI.

## 0.1.0

- Initial public release.
