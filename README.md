# sizes

[![CI](https://github.com/sevenreasons/sizes/actions/workflows/ci.yml/badge.svg)](https://github.com/sevenreasons/sizes/actions/workflows/ci.yml)

```text
disk usage by extension
```

`sizes` scans a directory and prints a compact summary grouped by file extension or file type. It can also browse results interactively with `fzf`.

## Install

```sh
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/sevenreasons/sizes/master/sizes.sh -o ~/.local/bin/sizes && chmod +x ~/.local/bin/sizes
```

Requires GNU `find` because `sizes` uses `find -printf`. `--interactive` also requires `fzf`. Optional image previews use `SIZES_IMAGE_PREVIEW=1` plus `chafa`, `viu`, `kitty`, `wezterm`, or `imgcat`.
Linux usually has it already. On macOS, install GNU findutils:

```sh
brew install findutils
```

## Example

```sh
sizes -r ~/Downloads
```

```text
sizes ~/Downloads — recursive
╭──────────────┬──────────┬────────────────┬───────────┬──────────┬────────────────────╮
│ EXT          │ TYPE     │           SIZE │     FILES │    SHARE │ BAR                │
├──────────────┼──────────┼────────────────┼───────────┼──────────┼────────────────────┤
│ ZIP          │ archive  │       6.49 GiB │        22 │   41.20% │ ███████░░░░░░░░░░░ │
│ MP4          │ video    │       4.12 GiB │        18 │   26.13% │ █████░░░░░░░░░░░░░ │
│ ISO          │ archive  │       3.01 GiB │         2 │   19.09% │ ███░░░░░░░░░░░░░░░ │
│ PDF          │ doc      │     845.56 MiB │        47 │    5.24% │ █░░░░░░░░░░░░░░░░░ │
├──────────────┼──────────┼────────────────┼───────────┼──────────┼────────────────────┤
│ TOTAL        │ all      │      15.75 GiB │       200 │  100.00% │ ██████████████████ │
╰──────────────┴──────────┴────────────────┴───────────┴──────────┴────────────────────╯
Scanned: 200 files · 15.75 GiB · 1s
```

## Usage

```sh
sizes                              # current directory only
sizes -r                           # recursive
sizes DIR                          # chosen directory
sizes DIR -r                       # chosen directory, recursive
sizes -r --depth 2                 # recurse up to 2 levels
sizes -r --follow                  # follow symlinks
sizes -r -x                        # stay on one filesystem
sizes -r --max-files 100000        # stop after N files and mark output partial
sizes -r -n 50                     # top 50 + OTHER
sizes -r --min-size 100M           # fold smaller rows into OTHER
sizes -r --min-share 0.1           # fold rows below 0.1% into OTHER
sizes -r --include '*.mp4'         # include matching paths only
sizes -r --exclude .git            # skip paths
sizes -r --type video              # include one detected type
sizes -r --top-files mp4           # largest files for extension
sizes -r --top-dirs                # directories using the most space
sizes -r --top-dirs mp4            # directories using the most MP4 space
sizes -r --by-dir                  # summarize by immediate child directory
sizes -r --interactive             # interactive fzf browser: modes, types, files, dirs
sizes -r --sort files              # sort by file count
sizes -r --group-by type           # summarize by type instead of extension
sizes -r --format json             # table, tsv, csv, json
sizes -r --save report.json        # save output; infers json/csv/tsv by extension
sizes --plain                      # simple ASCII table
sizes --no-progress                # disable scan spinner
sizes --upgrade --check            # check available upgrade
sizes --upgrade                    # self-upgrade installed script
sizes --upgrade --version v0.4.0   # install a tagged version
sizes --no-color                   # no ANSI colors
```

## Options

```text
-r, --recursive          recursive scan
    --depth N            recurse up to N directory levels; overrides -r
    --follow             follow symlinks while scanning
-x, --one-file-system    do not cross filesystem boundaries
    --max-files N        stop after N scanned files and show partial result
-n, --limit N            show top N rows and group the rest as OTHER
    --min-size SIZE      fold rows smaller than SIZE into OTHER
    --min-share PCT      fold rows below PCT percent into OTHER
-e, --exact              do not merge extension aliases like JPEG -> JPG
-E, --errors             show unreadable paths after the table
    --include PATTERN    include matching paths; can be used multiple times
    --exclude PATTERN    exclude matching paths; can be used multiple times
    --type TYPE          include only files of TYPE; can be used multiple times
    --top-files EXT      show largest files for an extension
    --top-dirs [EXT]     show directories using the most space, optionally for EXT
    --by-dir             summarize by immediate child directory
-i, --interactive        open the fzf interactive browser
    --sort FIELD         size, files, share, ext, type
    --format FORMAT      table, tsv, csv, json
    --save PATH          write output to PATH; infers format from .json/.csv/.tsv
    --group-by FIELD     ext, type
    --plain              simple ASCII table
    --no-progress        disable progress animation
    --no-color           disable ANSI colors
    --upgrade            upgrade the installed script
    --check              with --upgrade, check without installing
    --version [VERSION]  show version; with --upgrade, install tagged version
```

## Output behavior

- Non-recursive by default.
- Shows all rows unless `--limit`, `--min-size`, or `--min-share` folds rows into `OTHER`.
- Sorts by total size unless `--sort` is used.
- Groups extension aliases by default, for example `JPEG` into `JPG`.
- Colors are disabled automatically when output is redirected.
- Shows a progress spinner on interactive scans and only prints the table after scanning is done.
- Table output ends with a compact scan summary.
- Uses faster internal sorting with `LC_ALL=C` and robust unit-separator records for paths containing tabs.
- `--include` filters are pushed into `find` where possible, reducing work on large trees.
- `--top-files` streams candidates through `sort` instead of storing all matches in memory.
- `--top-dirs` and `--by-dir` help locate where space is coming from.
- `--interactive` opens a mode menu instead of dropping directly into rows. Browse extensions, types, top files, top directories, or directory summaries.
- Interactive extension/type previews show compact summaries with top directories and top files. Press `Enter` or `Ctrl-F` to open a selectable file browser; press `Ctrl-D` for directories; press `?` for help.
- Interactive file browser supports `Tab` multi-select, `Ctrl-O` open file, `Ctrl-P` open containing folder, `Ctrl-Y` copy path, and an action menu after `Enter`.
- Interactive previews are terminal-size aware. Use `Alt-J/K` to scroll previews, `Alt-U/D` to page them, and `Alt-T/B` for top/bottom.
- Optional image previews are available with `SIZES_IMAGE_PREVIEW=1` when `chafa`, `viu`, `kitty`, `wezterm`, or `imgcat` is installed.
- JSON output includes metadata such as version, root, mode, elapsed time, skipped paths, partial status, totals, and rows.
- `--save` writes the selected output directly to a file and infers JSON/CSV/TSV from the filename.
- Supports `NO_COLOR=1`, `CLICOLOR=0`, `SIZES_EXCLUDE=".git node_modules"`, `SIZES_DEBUG_TIMING=1`, `SIZES_FZF=...`, `SIZES_IMAGE_PREVIEW=1`, and `SIZES_UPGRADE_URL=...`.

## Completions

Completion files are included for Bash, Zsh, Fish, Nushell, and PowerShell in `completions/`.

## License

MIT
