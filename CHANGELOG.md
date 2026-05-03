# Changelog

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
