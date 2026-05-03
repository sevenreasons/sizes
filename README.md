# sizes

[![CI](https://github.com/sevenreasons/sizes/actions/workflows/ci.yml/badge.svg)](https://github.com/sevenreasons/sizes/actions/workflows/ci.yml)

```text
disk usage by extension
```

`sizes` scans a directory and prints a compact summary grouped by file extension or file type.

## Install

```sh
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/sevenreasons/sizes/master/sizes.sh -o ~/.local/bin/sizes && chmod +x ~/.local/bin/sizes
```

Requires GNU `find` because `sizes` uses `find -printf`.
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
```

## Usage

```sh
sizes                         # current directory only
sizes -r                      # recursive
sizes DIR                     # chosen directory
sizes DIR -r                  # chosen directory, recursive
sizes -r -n 50                # top 50 + OTHER
sizes -r --exclude .git       # skip paths
sizes -r --exclude node_modules --exclude .venv
sizes -r --sort files         # sort by file count
sizes -r --group-by type      # summarize by type instead of extension
sizes -r --format json        # table, tsv, csv, json
sizes --plain                 # simple ASCII table
sizes --no-progress           # disable scan spinner
sizes --upgrade               # self-upgrade installed script
sizes --no-color              # no ANSI colors
```

## Options

```text
-r, --recursive          recursive scan
-n, --limit N            show top N rows and group the rest as OTHER
-e, --exact              do not merge extension aliases like JPEG -> JPG
-E, --errors             show unreadable paths after the table
    --exclude PATTERN    exclude matching paths; can be used multiple times
    --sort FIELD         size, files, share, ext, type
    --format FORMAT      table, tsv, csv, json
    --group-by FIELD     ext, type
    --plain              simple ASCII table
    --no-progress        disable progress animation
    --no-color           disable ANSI colors
    --upgrade            upgrade the installed script
    --version            show version
```

## Output behavior

- Non-recursive by default.
- Shows all rows unless `--limit` is used.
- Sorts by total size unless `--sort` is used.
- Groups extension aliases by default, for example `JPEG` into `JPG`.
- Colors are disabled automatically when output is redirected.
- Shows a progress spinner on interactive scans and only prints the table after scanning is done.
- Supports `NO_COLOR=1`, `CLICOLOR=0`, `SIZES_EXCLUDE=".git node_modules"`, and `SIZES_UPGRADE_URL=...`.

## Completions

Completion files are included for Bash, Zsh, Fish, Nushell, and PowerShell in `completions/`.

## License

MIT
