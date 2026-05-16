# Changelog

## 0.7.11

- Add color coding to the interactive Types browser so type rows match extension rows.
- Add a Share column to the interactive Types browser.
- Show share percentage in interactive type previews.
- Recompute type drilldown extension rows against the selected type instead of leaking global totals/shares.

## 0.7.10

- Add interactive trash actions for files and directories.
- Add permanent delete actions behind `--allow-delete` / `SIZES_ALLOW_DELETE=1`.
- Require typed confirmation before permanent deletion.
- Add `SIZES_TRASH_CMD` for overriding the trash command.
- Document cleanup safety behavior.

## 0.7.9

- Fix the ShellCheck warning in the image-preview safety test.
- Keep optional image previews limited to safe chafa text/symbol output.
- Keep `SIZES_IMAGE_PREVIEW_SIZE` for tuning the chafa preview size.

## 0.7.7

- Preserve file and directory browser cursor position after returning from action menus using fzf's load event.
- Keep the search box empty while restoring the selected row.


## 0.7.6

- Fix interactive file and directory browsers to preserve cursor position after actions without leaking selected paths into the search box.


## 0.7.5

- Fix stale interactive search input after file and directory actions.
- Keep drilldown lists visible after opening, copying, or revealing selected paths.

## 0.7.4

- Add `--interactive-no-preview` and `SIZES_INTERACTIVE_PREVIEW=0`.
- Add full-path reveal with `Ctrl-L` in file and directory browsers.
- Add copy quoted path actions for shell-friendly paths.
- Add Open with… actions via `SIZES_OPEN_WITH` or an interactive command prompt.
- Add consistent Back and Quit rows to file and directory action menus.
- Improve empty preview fallbacks and selected-item detail output.
- Add interactive cleanup feedback after closing the browser.
- Expand interactive fake-fzf coverage.

## 0.7.3

- Polish interactive file and directory action menus.
- Show the selected item directly in action-menu headers.
- Add action-menu preview cards with path, size, type, and available shortcuts.
- Add feedback notices for file open, folder open, and copy actions.

## 0.7.2

- Fix interactive scan progress so it stays on one updating line instead of printing a duplicate scan line.

## 0.7.1

- Add back navigation in interactive mode with `Esc` and `Ctrl-B`.
- Add `Ctrl-Q` to quit interactive mode from nested views.
- Add breadcrumb prompts for the main menu, extension/type browsers, file browser, directory browser, and action menus.
- Preserve the selected row when returning from drilldown views.
- Make `Enter` behavior consistent by opening action menus in file and directory browsers.
- Improve file and directory action menus with clearer safe actions.
- Add `Browse files in directory` to the directory action menu.
- Add clearer empty-state screens for empty file, directory, and type drilldowns.
- Add `Refresh scan` / `Ctrl-R` to rescan from the interactive main menu.
- Update interactive help and tests.

## 0.6.1

- Fix interactive start menu spacing so labels and descriptions render as separate aligned text.

## 0.6.0

- Replace the direct interactive row view with a start menu for extensions, types, top files, top directories, and directory summaries.
- Add a type browser with drilldown into extensions, files, and directories.
- Add compact extension/type preview summaries with top directories and top files.
- Add interactive help preview via `?`.
- Add file action menu with open file, open parent folder, copy path, print path, and print details actions.
- Add `Ctrl-P` to open containing folders and `Ctrl-Y` to copy selected paths.
- Add multi-select support in the file browser.
- Make interactive previews terminal-size aware.
- Add optional image previews with `SIZES_IMAGE_PREVIEW=1` and compatible preview tools.
- Update README and tests.

## 0.5.4

- Polish `--interactive` layout so headers stay at the top and the left pane stays readable.
- Simplify right-side previews by showing size/path lists instead of boxed tables.
- Simplify file and directory browsers by removing repeated type columns from the selectable list.
- Add `Ctrl-O` in the file browser to open the selected file with the default associated app.

## 0.5.3

- Make `--interactive` a real drilldown flow instead of a static preview pane.
- Press `Enter` or `Ctrl-F` on an extension to open a selectable file browser.
- Press `Ctrl-D` on an extension to open a selectable directory browser.
- Add per-file and per-directory preview panes and selected item output.
- Keep the existing aligned, colored, size-sorted extension browser.
- Update tests.

## 0.5.1

- Improve `--interactive` with aligned colored rows that match the main table style.
- Add interactive preview switching: `Ctrl-F` for top files and `Ctrl-D` for top directories.
- Keep fzf ordering stable with `--no-sort` while still supporting search/filtering.
- Print both top files and top directories after accepting a row.
- Update tests.

## 0.5.0

- Add `--interactive` / `-i` for an `fzf`-powered extension browser.
- Add an interactive preview pane showing the largest files for the selected extension.
- Print a selected-extension detail table after pressing Enter.
- Respect existing filters such as `--include`, `--exclude`, `--type`, `--limit`, `--min-size`, and `--min-share` in interactive mode.
- Add `SIZES_FZF` for overriding the `fzf` command.
- Update completions and tests.

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
