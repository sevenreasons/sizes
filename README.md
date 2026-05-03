# sizes

[![CI](https://github.com/sevenreasons/sizes/actions/workflows/ci.yml/badge.svg)](https://github.com/sevenreasons/sizes/actions/workflows/ci.yml)

```text
disk usage by extension
```

`sizes` scans a directory and prints a table grouped by file extension.

## Install

```sh
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/sevenreasons/sizes/master/sizes.sh -o ~/.local/bin/sizes && chmod +x ~/.local/bin/sizes
```

Requires GNU `find` for `-printf`. Linux usually has it already. On macOS:

```sh
brew install findutils
```

`sizes` will automatically use `gfind` when GNU `find` is not available as `find`.

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
│ ISO          │ other    │       3.01 GiB │         2 │   19.09% │ ███░░░░░░░░░░░░░░░ │
│ PDF          │ doc      │     845.56 MiB │        47 │    5.24% │ █░░░░░░░░░░░░░░░░░ │
├──────────────┼──────────┼────────────────┼───────────┼──────────┼────────────────────┤
│ TOTAL        │ all      │      15.75 GiB │       200 │  100.00% │ ██████████████████ │
╰──────────────┴──────────┴────────────────┴───────────┴──────────┴────────────────────╯
```

## Commands

```sh
sizes              # current directory
sizes -r           # recursive
sizes DIR          # chosen directory
sizes DIR -r       # chosen directory, recursive
sizes -r -n 50     # top 50 + OTHER
sizes -e           # exact extension names
sizes --no-color   # no ANSI colors
sizes --errors     # show unreadable paths
sizes --version
```

## Options

```text
-r, --recursive   scan recursively
-n, --limit N     show top N extensions and group the rest as OTHER
-e, --exact       do not merge extension aliases
-E, --errors      print skipped unreadable paths
--no-color        disable color output
--version         print version
-h, --help        show help
```

## Behavior

- Non-recursive by default.
- Shows all extensions by default.
- Sorted by total byte size.
- Merges common aliases by default, for example `JPEG` → `JPG`.
- Colors are disabled automatically when redirected.
- Supports `NO_COLOR=1` and `CLICOLOR=0`.

## Completions

Completion files are in `completions/` for Bash, Zsh, Fish, Nushell, and PowerShell.

## Files

- `sizes.sh` is the standalone script used by the curl installer.
- `sizes` is a checkout-friendly wrapper around `sizes.sh`.

## License

MIT
