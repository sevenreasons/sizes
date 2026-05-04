# sizes

[![CI](https://github.com/sevenreasons/sizes/actions/workflows/ci.yml/badge.svg)](https://github.com/sevenreasons/sizes/actions/workflows/ci.yml)

```text
disk usage by extension
```

`sizes` scans a directory and shows what kinds of files are taking space. It can print a pretty table, export reports, drill into top files/directories, or open an `fzf` interactive browser.

```text
╭──────────────┬──────────┬────────────────┬───────────┬──────────┬────────────────────╮
│ EXT          │ TYPE     │           SIZE │     FILES │    SHARE │ BAR                │
├──────────────┼──────────┼────────────────┼───────────┼──────────┼────────────────────┤
│ MP4          │ video    │     116.42 GiB │     3,129 │   42.91% │ ██████████████████ │
│ DUCKDB       │ database │      64.37 GiB │        33 │   23.72% │ ██████████░░░░░░░░ │
│ PARQUET      │ data     │      25.82 GiB │       335 │    9.51% │ ████░░░░░░░░░░░░░░ │
│ JPG          │ image    │      14.26 GiB │    16,392 │    5.25% │ ██░░░░░░░░░░░░░░░░ │
├──────────────┼──────────┼────────────────┼───────────┼──────────┼────────────────────┤
│ TOTAL        │ all      │     271.33 GiB │    61,564 │  100.00% │ ██████████████████ │
╰──────────────┴──────────┴────────────────┴───────────┴──────────┴────────────────────╯
Scanned: 61,564 files · 271.33 GiB · 1s
```

## Install

```sh
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/sevenreasons/sizes/master/sizes.sh -o ~/.local/bin/sizes && chmod +x ~/.local/bin/sizes
```

Make sure `~/.local/bin` is on your `PATH`.

Fish:

```fish
fish_add_path ~/.local/bin
```

Bash/Zsh:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
. ~/.profile
```

## Requirements

- GNU `find` (`find -printf` is required). Linux usually already has it.
- macOS: `brew install findutils`.
- Interactive mode: `fzf`.
- Optional image previews: `SIZES_IMAGE_PREVIEW=1` plus `chafa`, `viu`, `kitty`, `wezterm`, or `imgcat`.

## Quick use

```sh
sizes                    # current directory only
sizes -r                 # recursive
sizes -r -n 30           # top 30 + OTHER
sizes -r --min-size 1G   # fold smaller rows into OTHER
sizes -r --type video    # only detected video files
sizes -r --top-files mp4 # largest MP4 files
sizes -r --top-dirs mp4  # directories containing the most MP4 data
sizes -r --by-dir        # summarize immediate child directories
sizes -r -i              # interactive browser
sizes -r -i --interactive-no-preview  # start with preview hidden
```

## Interactive mode

```sh
sizes -r -i
```

Interactive mode is an `fzf` drilldown UI. It starts at a mode menu, then lets you browse extensions, types, top files, top directories, and directory summaries.

Main navigation:

```text
Enter    open selected mode / action menu
Esc      go back one screen
Ctrl-B   go back one screen
Ctrl-Q   quit
Ctrl-R   refresh scan from the main menu
?        contextual help
/        search
```

Extension/type screens:

```text
Enter    browse files
Ctrl-F   browse files
Ctrl-D   browse directories
```

File screens:

```text
Enter    action menu
Tab      multi-select files
Ctrl-O   open selected file
Ctrl-P   open containing folder
Ctrl-Y   copy selected path
Ctrl-L   reveal full path
Ctrl-/   toggle preview pane
```

Directory screens:

```text
Enter    action menu
Ctrl-O   open directory
Ctrl-Y   copy path
Ctrl-L   reveal full path
Ctrl-/   toggle preview pane
```

Action menus show the selected file or directory in the header and preview pane before running an action. They include safe actions such as open, open containing folder, open with another command, copy path, copy quoted path, print path, and print details.

Preview scrolling:

```text
Alt-J/K  scroll down/up
Alt-D/U  page down/up
Alt-T/B  top/bottom
```

## Output formats

```sh
sizes -r --format table
sizes -r --format tsv
sizes -r --format csv
sizes -r --format json
sizes -r --save report.json
```

JSON output includes scan metadata and rows:

```json
{
  "version": "0.7.4",
  "root": ".",
  "mode": "recursive",
  "total_bytes": 123456,
  "rows": []
}
```

## Common options

```text
-r, --recursive          recursive scan
    --depth N            recurse up to N levels
    --follow             follow symlinks
-x, --one-file-system    do not cross filesystem boundaries
    --max-files N        stop after N scanned files and mark output partial
-n, --limit N            top N rows + OTHER
    --min-size SIZE      fold rows smaller than SIZE into OTHER
    --min-share PCT      fold rows below PCT percent into OTHER
-e, --exact              do not merge aliases like JPEG -> JPG
-E, --errors             show unreadable paths
    --include PATTERN    include matching paths; repeatable
    --exclude PATTERN    exclude matching paths; repeatable
    --type TYPE          include detected type; repeatable
    --top-files EXT      show largest files for an extension
    --top-dirs [EXT]     show largest directories, optionally for EXT
    --by-dir             summarize immediate child directories
-i, --interactive        open interactive browser
    --interactive-no-preview
                         start interactive mode with preview hidden
    --sort FIELD         size, files, share, ext, type
    --format FORMAT      table, tsv, csv, json
    --save PATH          write output to PATH; infers .json/.csv/.tsv
    --group-by FIELD     ext, type
    --plain              simple ASCII table
    --no-progress        disable progress animation
    --no-color           disable ANSI colors
    --upgrade            upgrade installed script
    --check              with --upgrade, check without installing
    --version [VERSION]  show version; with --upgrade, install tagged version
```

## Environment

```text
NO_COLOR=1                 disable colors
CLICOLOR=0                 disable colors
SIZES_EXCLUDE=".git node_modules"
SIZES_DEBUG_TIMING=1       print timing diagnostics
SIZES_FZF=/path/to/fzf     override fzf command
SIZES_IMAGE_PREVIEW=1      enable image previews in interactive mode
SIZES_INTERACTIVE_PREVIEW=0 start interactive previews hidden
SIZES_OPEN_WITH=cmd        default command for interactive Open with…
SIZES_UPGRADE_URL=...      override upgrade source
```

## Completions

Completion files are in `completions/` for Bash, Zsh, Fish, Nushell, and PowerShell.

## License

MIT
