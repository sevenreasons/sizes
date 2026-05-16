#!/usr/bin/env sh
# sizes - show total file size by extension in a pretty terminal table.
# Requires GNU find-compatible find for -printf. Uses gfind automatically when available.

set -u

VERSION="0.7.11"

usage() {
    cat <<'USAGE'
Usage: sizes [OPTIONS] [DIR]

Pretty terminal table for total file size by extension.

Options:
  -r, --recursive          Scan recursively. Default: current directory only.
      --depth N            Scan up to N directory levels. Overrides -r.
      --follow             Follow symlinks while scanning.
  -x, --one-file-system    Do not cross filesystem boundaries.
      --max-files N        Stop after scanning N files and show a partial result.
  -n, --limit N            Show top N rows and fold the rest into OTHER.
                           Default: show all rows. With --top-files, default: 20.
      --min-size SIZE      Fold rows smaller than SIZE into OTHER. Examples: 100M, 1G.
      --min-share PCT      Fold rows below PCT percent into OTHER. Example: 0.1.
  -e, --exact              Do not merge aliases like JPEG -> JPG.
  -E, --errors             Print unreadable-path errors after the table.
      --include PATTERN    Include only matching paths. Can be used multiple times.
      --exclude PATTERN    Exclude matching paths. Can be used multiple times.
      --type TYPE          Include only files of TYPE. Can be used multiple times.
      --top-files EXT      Show largest files for an extension instead of summary rows.
      --top-dirs [EXT]     Show directories using the most space, optionally for EXT.
      --by-dir             Summarize usage by immediate child directory.
  -i, --interactive        Open the fzf interactive browser.
      --interactive-no-preview
                           Start interactive mode with preview hidden.
      --allow-delete       Enable permanent delete actions in interactive mode.
      --sort FIELD         Sort by size, files, share, ext, or type. Default: size.
      --format FORMAT      Output table, tsv, csv, or json. Default: table.
      --save PATH          Save output to a file. Infers format from .json/.csv/.tsv.
      --group-by FIELD     Group by ext or type. Default: ext.
      --plain              Use a simple ASCII table.
      --no-progress        Disable progress animation.
      --no-color           Disable ANSI colors.
      --upgrade            Upgrade this script from GitHub.
      --check              With --upgrade, check available version without installing.
      --version [VERSION]  Print version. With --upgrade, install a tagged version.
  -h, --help               Show this help.

Environment:
  NO_COLOR=1               Disable ANSI colors.
  CLICOLOR=0               Disable ANSI colors.
  SIZES_EXCLUDE="..."      Space-separated default exclude patterns.
  SIZES_FIND=/path/to/find Override find command.
  SIZES_UPGRADE_URL=URL    Override --upgrade download source.
  SIZES_UPGRADE_TARGET=PATH Override --upgrade target path.
  SIZES_DEBUG_TIMING=1     Print coarse timing diagnostics to stderr.
  SIZES_FZF=/path/to/fzf   Override fzf command for --interactive.
  SIZES_IMAGE_PREVIEW=1    Enable optional image previews in file browser.
  SIZES_INTERACTIVE_PREVIEW=0
                           Start interactive previews hidden.
  SIZES_OPEN_WITH=cmd      Default command for interactive Open with… action.
  SIZES_TRASH_CMD=cmd      Override trash command for interactive trash actions.
  SIZES_ALLOW_DELETE=1     Enable permanent delete actions in interactive mode.

Examples:
  sizes
  sizes -r
  sizes ~/Downloads -r
  sizes -r --depth 2
  sizes -r -x
  sizes -r --max-files 100000
  sizes -r -n 40
  sizes -r --min-size 100M --min-share 0.1
  sizes -r --include '*.mp4' --exclude node_modules
  sizes -r --type video
  sizes -r --top-files mp4
  sizes -r --top-dirs
  sizes -r --top-dirs mp4
  sizes -r --by-dir
  sizes -r --interactive
  sizes -r --interactive --interactive-no-preview
  sizes -r --interactive --allow-delete
  sizes -r --group-by type
  sizes -r --format json
  sizes -r --save report.json
  sizes --plain
  sizes --upgrade --check
  sizes --upgrade --version v0.4.0
USAGE
}

fail() {
    printf '%s\n' "sizes: $*" >&2
    exit 2
}

parse_size() {
    awk -v raw="$1" '
        BEGIN {
            s = toupper(raw)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            if (s !~ /^[0-9]+([.][0-9]+)?([KMGTPE]?I?B?|B)?$/)
                exit 1

            n = s + 0
            unit = s
            sub(/^[0-9]+([.][0-9]+)?/, "", unit)

            mult = 1
            if (unit ~ /^K/) mult = 1024
            else if (unit ~ /^M/) mult = 1024 ^ 2
            else if (unit ~ /^G/) mult = 1024 ^ 3
            else if (unit ~ /^T/) mult = 1024 ^ 4
            else if (unit ~ /^P/) mult = 1024 ^ 5
            else if (unit ~ /^E/) mult = 1024 ^ 6

            printf "%.0f\n", n * mult
        }
    ' || return 1
}

is_number() {
    awk -v n="$1" 'BEGIN { exit !(n ~ /^[0-9]+([.][0-9]+)?$/) }'
}

DEFAULT_UPGRADE_URL="https://raw.githubusercontent.com/sevenreasons/sizes/master/sizes.sh"
DEFAULT_UPGRADE_BASE="https://raw.githubusercontent.com/sevenreasons/sizes"

download_to() {
    url=$1
    dest=$2

    case "$url" in
        file://*) cp "${url#file://}" "$dest"; return $? ;;
        /*|./*|../*) cp "$url" "$dest"; return $? ;;
    esac

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    elif command -v fetch >/dev/null 2>&1; then
        fetch -q -o "$dest" "$url"
    else
        printf '%s\n' "sizes: --upgrade needs curl, wget, or fetch" >&2
        return 1
    fi
}

upgrade_url_for() {
    requested=$1

    if [ "${SIZES_UPGRADE_URL:-}" != "" ]; then
        printf '%s\n' "$SIZES_UPGRADE_URL"
        return 0
    fi

    if [ "$requested" != "" ]; then
        case "$requested" in
            v*) ref=$requested ;;
            *) ref="v$requested" ;;
        esac
        printf '%s\n' "$DEFAULT_UPGRADE_BASE/$ref/sizes.sh"
        return 0
    fi

    printf '%s\n' "$DEFAULT_UPGRADE_URL"
}

self_upgrade() {
    url=$(upgrade_url_for "$upgrade_version")
    target=${SIZES_UPGRADE_TARGET:-}

    if [ "$upgrade_check" -eq 1 ]; then
        tmp=$(mktemp "${TMPDIR:-/tmp}/sizes-upgrade-check.XXXXXX") || exit 1
        if ! download_to "$url" "$tmp"; then
            rm -f "$tmp"
            printf '%s\n' "sizes: upgrade check failed: $url" >&2
            exit 1
        fi
        if ! sh "$tmp" --version >/dev/null 2>&1; then
            rm -f "$tmp"
            printf '%s\n' "sizes: downloaded file does not look like a working sizes script" >&2
            exit 1
        fi
        new_version=$(sh "$tmp" --version 2>/dev/null | sed 's/^sizes //')
        rm -f "$tmp"
        printf '%s\n' "sizes: current $VERSION, available $new_version"
        if [ "$new_version" = "$VERSION" ]; then
            printf '%s\n' "sizes: already up to date"
        else
            printf '%s\n' "sizes: upgrade available"
        fi
        return 0
    fi

    if [ "$target" = "" ]; then
        case "$0" in
            */*) target=$0 ;;
            *) target=$(command -v "$0" 2>/dev/null || printf '%s\n' "$0") ;;
        esac
    fi

    if [ ! -f "$target" ]; then
        printf '%s\n' "sizes: cannot find current script: $target" >&2
        exit 1
    fi

    target_dir=$(CDPATH='' cd -- "$(dirname -- "$target")" && pwd) || exit 1
    target_base=$(basename -- "$target")

    if [ ! -w "$target" ] && [ ! -w "$target_dir" ]; then
        printf '%s\n' "sizes: current script is not writable: $target" >&2
        exit 1
    fi

    tmp=$(mktemp "$target_dir/.${target_base}.upgrade.XXXXXX") || exit 1

    if ! download_to "$url" "$tmp"; then
        rm -f "$tmp"
        printf '%s\n' "sizes: upgrade download failed: $url" >&2
        exit 1
    fi

    if ! sh "$tmp" --version >/dev/null 2>&1; then
        rm -f "$tmp"
        printf '%s\n' "sizes: downloaded file does not look like a working sizes script" >&2
        exit 1
    fi

    new_version=$(sh "$tmp" --version 2>/dev/null | sed 's/^sizes //')
    chmod +x "$tmp" 2>/dev/null || true

    if ! mv "$tmp" "$target"; then
        rm -f "$tmp"
        printf '%s\n' "sizes: failed to replace current script: $target" >&2
        exit 1
    fi

    chmod +x "$target" 2>/dev/null || true
    printf '%s\n' "sizes: upgraded $target from $VERSION to $new_version"
}

recursive=0
merge=1
limit=0
show_errors=0
color=1
plain=0
sort_by="size"
format="table"
format_seen=0
group_by="ext"
progress=1
upgrade=0
upgrade_check=0
upgrade_version=""
dir="."
dir_seen=0
follow=0
one_file_system=0
depth=""
max_files=0
min_size=0
min_share=-1
top_files=""
top_dirs=0
top_dirs_ext=""
by_dir=0
interactive=0
interactive_preview=1
allow_delete=0
save_path=""
include_data=""
include_count=0
exclude_data=""
exclude_count=0
type_data=""
type_count=0
sep=$(printf '\034')

append_data() {
    current=$1
    value=$2
    if [ "$current" = "" ]; then
        printf '%s\n' "$value"
    else
        printf '%s%s%s\n' "$current" "$sep" "$value"
    fi
}

add_include() {
    [ "$1" != "" ] || return 0
    include_data=$(append_data "$include_data" "$1")
    include_count=$((include_count + 1))
}

add_exclude() {
    [ "$1" != "" ] || return 0
    exclude_data=$(append_data "$exclude_data" "$1")
    exclude_count=$((exclude_count + 1))
}

add_type() {
    [ "$1" != "" ] || return 0
    type_data=$(append_data "$type_data" "$1")
    type_count=$((type_count + 1))
}

for pattern in ${SIZES_EXCLUDE:-}; do
    add_exclude "$pattern"
done

# Respect common no-color conventions and avoid ANSI escapes in redirected output.
if [ ! -t 1 ] || [ "${NO_COLOR:-}" != "" ] || [ "${CLICOLOR:-1}" = "0" ]; then
    color=0
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        -r|--recursive)
            recursive=1
            shift
            ;;
        --depth)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            depth=$2
            case "$depth" in ''|*[!0-9]*) fail "--depth must be a non-negative integer" ;; esac
            shift 2
            ;;
        --depth=*)
            depth=${1#*=}
            case "$depth" in ''|*[!0-9]*) fail "--depth must be a non-negative integer" ;; esac
            shift
            ;;
        --follow)
            follow=1
            shift
            ;;
        -x|--one-file-system)
            one_file_system=1
            shift
            ;;
        --max-files)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            max_files=$2
            case "$max_files" in ''|*[!0-9]*) fail "--max-files must be a non-negative integer" ;; esac
            shift 2
            ;;
        --max-files=*)
            max_files=${1#*=}
            case "$max_files" in ''|*[!0-9]*) fail "--max-files must be a non-negative integer" ;; esac
            shift
            ;;
        -e|--exact)
            merge=0
            shift
            ;;
        -E|--errors)
            show_errors=1
            shift
            ;;
        --include)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            add_include "$2"
            shift 2
            ;;
        --include=*)
            add_include "${1#*=}"
            shift
            ;;
        --exclude)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            add_exclude "$2"
            shift 2
            ;;
        --exclude=*)
            add_exclude "${1#*=}"
            shift
            ;;
        --type)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            add_type "$2"
            shift 2
            ;;
        --type=*)
            add_type "${1#*=}"
            shift
            ;;
        --top-files)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            top_files=$2
            shift 2
            ;;
        --top-files=*)
            top_files=${1#*=}
            [ "$top_files" != "" ] || fail "--top-files needs an extension"
            shift
            ;;
        --top-dirs)
            top_dirs=1
            if [ "$#" -ge 2 ]; then
                case "$2" in
                    -*) ;;
                    *)
                        if [ ! -d "$2" ]; then
                            top_dirs_ext=$2
                            shift
                        fi
                        ;;
                esac
            fi
            shift
            ;;
        --top-dirs=*)
            top_dirs=1
            top_dirs_ext=${1#*=}
            shift
            ;;
        --by-dir)
            by_dir=1
            shift
            ;;
        -i|--interactive)
            interactive=1
            shift
            ;;
        --interactive-no-preview)
            interactive_preview=0
            shift
            ;;
        --allow-delete)
            allow_delete=1
            shift
            ;;
        --min-size)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            min_size=$(parse_size "$2") || fail "--min-size must be a size like 100M or 1G"
            shift 2
            ;;
        --min-size=*)
            min_size=$(parse_size "${1#*=}") || fail "--min-size must be a size like 100M or 1G"
            shift
            ;;
        --min-share)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            is_number "$2" || fail "--min-share must be a number"
            min_share=$2
            shift 2
            ;;
        --min-share=*)
            min_share=${1#*=}
            is_number "$min_share" || fail "--min-share must be a number"
            shift
            ;;
        --sort)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            sort_by=$2
            shift 2
            ;;
        --sort=*)
            sort_by=${1#*=}
            shift
            ;;
        --format)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            format=$2
            format_seen=1
            shift 2
            ;;
        --format=*)
            format=${1#*=}
            format_seen=1
            shift
            ;;
        --save)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            save_path=$2
            shift 2
            ;;
        --save=*)
            save_path=${1#*=}
            [ "$save_path" != "" ] || fail "--save needs a path"
            shift
            ;;
        --group-by)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            group_by=$2
            shift 2
            ;;
        --group-by=*)
            group_by=${1#*=}
            shift
            ;;
        --plain)
            plain=1
            color=0
            shift
            ;;
        --no-progress)
            progress=0
            shift
            ;;
        --no-color)
            color=0
            shift
            ;;
        --upgrade)
            upgrade=1
            shift
            ;;
        --check)
            upgrade_check=1
            shift
            ;;
        --version)
            if [ "$upgrade" -eq 1 ] && [ "$#" -ge 2 ]; then
                case "$2" in
                    -*) printf 'sizes %s\n' "$VERSION"; exit 0 ;;
                    *) upgrade_version=$2; shift 2 ;;
                esac
            else
                printf 'sizes %s\n' "$VERSION"
                exit 0
            fi
            ;;
        --version=*)
            if [ "$upgrade" -eq 1 ]; then
                upgrade_version=${1#*=}
                shift
            else
                fail "--version does not take a value unless used after --upgrade"
            fi
            ;;
        -n|--limit)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            limit=$2
            case "$limit" in ''|*[!0-9]*) fail "--limit must be a non-negative integer" ;; esac
            shift 2
            ;;
        --limit=*)
            limit=${1#*=}
            case "$limit" in ''|*[!0-9]*) fail "--limit must be a non-negative integer" ;; esac
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            fail "unknown option: $1"
            ;;
        *)
            if [ "$dir_seen" -eq 1 ]; then
                fail "only one directory can be provided"
            fi
            dir=$1
            dir_seen=1
            shift
            ;;
    esac
done

while [ "$#" -gt 0 ]; do
    if [ "$dir_seen" -eq 1 ]; then
        fail "only one directory can be provided"
    fi
    dir=$1
    dir_seen=1
    shift
done

if [ "$upgrade_check" -eq 1 ] && [ "$upgrade" -ne 1 ]; then
    fail "--check must be used with --upgrade"
fi

if [ "$upgrade" -eq 1 ]; then
    self_upgrade
    exit 0
fi

case "$sort_by" in
    size|files|share|ext|type) ;;
    *) fail "--sort must be one of: size, files, share, ext, type" ;;
esac

case "$format" in
    table|tsv|csv|json) ;;
    *) fail "--format must be one of: table, tsv, csv, json" ;;
esac

case "$group_by" in
    ext|type) ;;
    *) fail "--group-by must be one of: ext, type" ;;
esac

mode_count=0
[ "$top_files" != "" ] && mode_count=$((mode_count + 1))
[ "$top_dirs" -eq 1 ] && mode_count=$((mode_count + 1))
[ "$by_dir" -eq 1 ] && mode_count=$((mode_count + 1))
[ "$interactive" -eq 1 ] && mode_count=$((mode_count + 1))
if [ "$mode_count" -gt 1 ]; then
    fail "--top-files, --top-dirs, --by-dir, and --interactive are mutually exclusive"
fi

if [ "$save_path" != "" ] && [ "$format_seen" -eq 0 ]; then
    case "$save_path" in
        *.json|*.JSON) format="json" ;;
        *.csv|*.CSV) format="csv" ;;
        *.tsv|*.TSV) format="tsv" ;;
    esac
fi

if [ "$interactive" -eq 1 ]; then
    [ "$save_path" = "" ] || fail "--interactive cannot be used with --save"
    [ "$format" = "table" ] || fail "--interactive cannot be used with --format"
    [ "$group_by" = "ext" ] || fail "--interactive currently supports --group-by ext only"
fi

if [ "${SIZES_INTERACTIVE_PREVIEW:-1}" = "0" ]; then
    interactive_preview=0
fi

if [ "$format" != "table" ]; then
    color=0
    plain=0
    progress=0
fi

if { [ "$top_files" != "" ] || [ "$top_dirs" -eq 1 ]; } && [ "$limit" -eq 0 ]; then
    limit=20
fi

if [ "$save_path" != "" ]; then
    color=0
    progress=0
fi

if [ ! -t 2 ]; then
    progress=0
fi

if [ ! -d "$dir" ]; then
    printf '%s\n' "sizes: not a directory: $dir" >&2
    exit 1
fi

find_cmd=${SIZES_FIND:-}
if [ "$find_cmd" = "" ]; then
    if command find "$dir" -maxdepth 0 -printf '' >/dev/null 2>&1; then
        find_cmd='find'
    elif command -v gfind >/dev/null 2>&1 && gfind "$dir" -maxdepth 0 -printf '' >/dev/null 2>&1; then
        find_cmd='gfind'
    else
        printf '%s\n' "sizes: GNU find is required because this tool uses find -printf" >&2
        exit 1
    fi
elif ! command "$find_cmd" "$dir" -maxdepth 0 -printf '' >/dev/null 2>&1; then
    printf '%s\n' "sizes: SIZES_FIND does not support GNU find -printf: $find_cmd" >&2
    exit 1
fi

mode="top-level"
if [ "$recursive" -eq 1 ]; then
    mode="recursive"
fi
if [ "$depth" != "" ]; then
    mode="depth $depth"
fi
if [ "$follow" -eq 1 ]; then
    mode="$mode, follow"
fi
if [ "$one_file_system" -eq 1 ]; then
    mode="$mode, one filesystem"
fi

errfile=$(mktemp "${TMPDIR:-/tmp}/sizes-errors.XXXXXX") || exit 1
exclude_file=$(mktemp "${TMPDIR:-/tmp}/sizes-exclude.XXXXXX") || exit 1
include_file=$(mktemp "${TMPDIR:-/tmp}/sizes-include.XXXXXX") || exit 1
partial_file=$(mktemp "${TMPDIR:-/tmp}/sizes-partial.XXXXXX") || exit 1
top_stats_file=$(mktemp "${TMPDIR:-/tmp}/sizes-top-stats.XXXXXX") || exit 1
progress_count_file=""
cleanup() {
    rm -f "$errfile" "$exclude_file" "$include_file" "$partial_file" "$top_stats_file"
    if [ "$progress_count_file" != "" ]; then
        rm -f "$progress_count_file"
    fi
}
trap cleanup EXIT HUP INT TERM

if [ "$exclude_data" != "" ]; then
    awk -v excludes="$exclude_data" 'BEGIN { n = split(excludes, ex, "\034"); for (i = 1; i <= n; i++) if (ex[i] != "") print ex[i] }' >"$exclude_file"
fi

if [ "$include_data" != "" ]; then
    awk -v includes="$include_data" 'BEGIN { n = split(includes, inc, "\034"); for (i = 1; i <= n; i++) if (inc[i] != "") print inc[i] }' >"$include_file"
fi

start_ts=$(date +%s 2>/dev/null || printf '0')
field_sep=$(printf '\037')
find_printf="%s${field_sep}%p${field_sep}%f\\0"

run_find() {
    set --

    if [ "$follow" -eq 1 ]; then
        set -- "$@" -L
    fi

    set -- "$@" "$dir"

    if [ "$one_file_system" -eq 1 ]; then
        set -- "$@" -xdev
    fi

    if [ "$depth" != "" ]; then
        set -- "$@" -maxdepth "$depth"
    elif [ "$recursive" -eq 0 ]; then
        set -- "$@" -maxdepth 1
    fi

    if [ "$exclude_count" -gt 0 ]; then
        set -- "$@" "("
        first=1
        while IFS= read -r pattern; do
            [ "$pattern" != "" ] || continue

            if [ "$first" -eq 0 ]; then
                set -- "$@" -o
            fi

            case "$pattern" in
                */*) set -- "$@" "(" -path "$pattern" -o -path "*/$pattern" ")" ;;
                *) set -- "$@" -name "$pattern" ;;
            esac

            first=0
        done <"$exclude_file"
        set -- "$@" ")" -prune -o -type f
    else
        set -- "$@" -type f
    fi

    if [ "$include_count" -gt 0 ]; then
        set -- "$@" "("
        first=1
        while IFS= read -r pattern; do
            [ "$pattern" != "" ] || continue

            if [ "$first" -eq 0 ]; then
                set -- "$@" -o
            fi

            case "$pattern" in
                */*) set -- "$@" "(" -path "$pattern" -o -path "*/$pattern" ")" ;;
                *) set -- "$@" -name "$pattern" ;;
            esac

            first=0
        done <"$include_file"
        set -- "$@" ")"
    fi

    set -- "$@" -printf "$find_printf"
    command "$find_cmd" "$@" 2>"$errfile"
}

scan_stream() {
    run_find \
    | LC_ALL=C awk -v RS='\0' -v ORS='\0' \
        -v max_files="$max_files" \
        -v progress_file="$progress_count_file" \
        -v partial_file="$partial_file" '
        NF > 0 {
            seen++
            if (max_files + 0 > 0 && seen > max_files) {
                printf "%d\n", max_files > partial_file
                close(partial_file)
                exit
            }

            print $0

            if (progress_file != "" && seen % 256 == 0) {
                printf "%d\n", seen > progress_file
                close(progress_file)
            }
        }
        END {
            if (progress_file != "") {
                printf "%d\n", seen > progress_file
                close(progress_file)
            }
        }'
}


sort_records() {
    case "$sort_by" in
        size|share|files) LC_ALL=C sort -t "$field_sep" -k1,1nr ;;
        ext|type) LC_ALL=C sort -t "$field_sep" -k1,1f ;;
    esac
}

# shellcheck disable=SC2016
common_awk_functions='
    function regex_escape(s,    out, i, ch) {
        out = ""
        for (i = 1; i <= length(s); i++) {
            ch = substr(s, i, 1)
            if (ch ~ /[][\\.^$()+{}|]/) out = out "\\" ch
            else out = out ch
        }
        return out
    }
    function glob_to_regex(s,    out, i, ch) {
        out = ""
        for (i = 1; i <= length(s); i++) {
            ch = substr(s, i, 1)
            if (ch == "*") out = out ".*"
            else if (ch == "?") out = out "."
            else if (ch ~ /[][\\.^$()+{}|]/) out = out "\\" ch
            else out = out ch
        }
        return out
    }
    function has_glob(s) { return s ~ /[*?]/ }
    function relpath(path) {
        if (substr(path, 1, length(dir) + 1) == dir "/") return substr(path, length(dir) + 2)
        if (substr(path, 1, 2) == "./") return substr(path, 3)
        return path
    }
    function matches_pattern(pattern, path, base,    rel, rx) {
        rel = relpath(path)
        if (pattern == "") return 0
        if (has_glob(pattern)) {
            rx = "^" glob_to_regex(pattern) "$"
            if (rel ~ rx || path ~ rx || base ~ rx) return 1
            rx = "/" glob_to_regex(pattern) "(/|$)"
            if (path ~ rx || rel ~ rx) return 1
        } else if (pattern ~ /\//) {
            if (rel == pattern || substr(rel, 1, length(pattern) + 1) == pattern "/" || path == pattern || substr(path, 1, length(pattern) + 1) == pattern "/") return 1
        } else {
            rx = "(^|/)" regex_escape(pattern) "(/|$)"
            if (base == pattern || rel ~ rx || path ~ rx) return 1
        }
        return 0
    }
    function excluded(path, base,    i) {
        for (i = 1; i <= nex; i++) if (matches_pattern(ex[i], path, base)) return 1
        return 0
    }
    function included(path, base,    i) {
        if (ninc <= 0) return 1
        for (i = 1; i <= ninc; i++) if (matches_pattern(inc[i], path, base)) return 1
        return 0
    }
    function allowed_type(k,    i, want) {
        if (ntypes <= 0) return 1
        for (i = 1; i <= ntypes; i++) {
            want = tolower(types[i])
            if (want == tolower(k)) return 1
        }
        return 0
    }
    function extname(name,    n, a, e) {
        if (name ~ /^\.[^.]+$/) return "NO_EXT"
        n = split(name, a, ".")
        e = (n > 1 && a[n] != "") ? toupper(a[n]) : "NO_EXT"
        if (merge) {
            if (e == "JPEG" || e == "JPE" || e == "JFIF") e = "JPG"
            else if (e == "MPEG") e = "MPG"
            else if (e == "3GPP") e = "3GP"
            else if (e == "TIF") e = "TIFF"
            else if (e == "HTM") e = "HTML"
            else if (e == "YML") e = "YAML"
            else if (e == "SQLITE3" || e == "DB3") e = "SQLITE"
        }
        return e
    }
    function kind(ext) {
        if (ext == "NO_EXT") return "none"
        if (ext == "OTHER") return "mixed"
        if (ext == "TOTAL") return "all"
        if (ext ~ /^(MP4|M4V|MOV|MKV|WEBM|AVI|WMV|MTS|M2TS|FLV|MPG|MPEG|3GP|3GPP|TS|Y4M|VOB|OGV|ASF|RM|RMVB|M2V|F4V|HEVC)$/) return "video"
        if (ext ~ /^(JPG|JPEG|JPE|JFIF|JP2|J2K|PNG|WEBP|GIF|AVIF|JXL|BMP|PSD|TIFF|TIF|HEIC|HEIF|SVG|XCF|KRA|ICO|RAW|CR2|NEF|ARW|DNG|RW2|RAF|ORF|SR2|XMP)$/) return "image"
        if (ext ~ /^(MP3|MP2|M4A|MKA|FLAC|WAV|OGG|OPUS|AAC|AIF|AIFF|WMA|MID|MIDI|AMR|AC3|DTS|WEM|XWB|BNK|BANK)$/) return "audio"
        if (ext ~ /^(ZIP|RAR|7Z|TAR|TGZ|GZ|XZ|ZST|BZ2|LZMA|CAB|RPM|DEB|APK|APPIMAGE|ISO|DMG|Z[0-9][0-9])$/) return "archive"
        if (ext ~ /^(TXT|MD|RST|PDF|DJVU|DOC|DOCX|ODT|RTF|XLS|XLSX|PPT|PPTX|EPUB|CBZ|CBR)$/) return "doc"
        if (ext ~ /^(JSON|JSONL|NDJSON|CSV|TSV|PARQUET|ARROW|FEATHER|ORC|AVRO|XML|YAML|YML|TOML|INI|CONF|NPY|NPZ|PKL|PICKLE|HDF|HDF5)$/) return "data"
        if (ext ~ /^(SQL|DB|DB3|DUCKDB|SQLITE|SQLITE3|MDB|WAL|LDB|SST|FDB|GDB)$/) return "database"
        if (ext ~ /^(GGUF|GGML|SAFETENSORS|ONNX|PTH|PT|CKPT|PB|TFLITE|H5|ORT|MODEL|SPM|TOKENIZER|LLAMAFILE|BIN)$/) return "model"
        if (ext ~ /^(PY|PYI|PYC|PYD|PYX|JS|MJS|CJS|TS|TSX|JSX|HTML|CSS|SCSS|SASS|RS|GO|CPP|CXX|CC|C|H|HPP|JAVA|KT|KTS|SH|BASH|ZSH|FISH|LUA|R|RB|PHP|PL|PM|SWIFT|WASM|IPYNB)$/) return "code"
        if (ext ~ /^(TTF|OTF|TTC|WOFF|WOFF2|FON|EOT)$/) return "font"
        if (ext ~ /^(OBJ|FBX|GLB|GLTF|BLEND|BLEND[0-9]+|MESH|STL|PLY|DAE|3DS)$/) return "3d"
        if (ext ~ /^(EXE|DLL|SO|DYLIB|LIB|SYS|OCX|DRV|TLB|A|O|OBJ)$/) return "binary"
        if (ext ~ /^(SRT|VTT|ASS|SSA|SUB)$/) return "subs"
        if (ext ~ /^(LOG|MAP|LOCK|BAK|BACKUP|OLD|TMP|CACHE|PART|CRDOWNLOAD)$/) return "meta"
        if (ext ~ /^(PAK|RESS|RESOURCE|ASSETS|BUNDLE|LOTPACK|LOTHEADER|UNITY3D|DAT|ARC|WAD|PK3|PK4)$/) return "game"
        return "other"
    }
    function cached_extname(name) {
        if (!(name in ext_cache)) ext_cache[name] = extname(name)
        return ext_cache[name]
    }
    function cached_kind(ext) {
        if (!(ext in kind_cache)) kind_cache[ext] = kind(ext)
        return kind_cache[ext]
    }'

# shellcheck disable=SC2016
generate_report() {
scan_stream \
| awk -v RS='\0' -F"$field_sep" \
    -v merge="$merge" \
    -v group_by="$group_by" \
    -v sort_by="$sort_by" \
    -v dir="$dir" \
    -v excludes="$exclude_data" \
    -v includes="$include_data" \
    -v typedata="$type_data" \
    -v OFS="$field_sep" \
    "$common_awk_functions"'
    BEGIN {
        nex = split(excludes, ex, "\034")
        ninc = split(includes, inc, "\034")
        ntypes = split(typedata, types, "\034")
    }
    NF >= 3 {
        size = $1 + 0
        path = $2
        base = $3
        if (excluded(path, base) || !included(path, base)) next
        ext = cached_extname(base)
        k = cached_kind(ext)
        if (!allowed_type(k)) next
        key = (group_by == "type") ? k : ext
        bytes[key] += size
        count[key] += 1
        total += size
        total_count += 1
        if (!(key in row_kind)) row_kind[key] = (group_by == "type") ? key : k
    }
    END {
        for (key in bytes) {
            k = row_kind[key]
            share = total ? bytes[key] * 100 / total : 0
            if (sort_by == "files") sortkey = count[key]
            else if (sort_by == "ext") sortkey = key
            else if (sort_by == "type") sortkey = k " " key
            else if (sort_by == "share") sortkey = share
            else sortkey = bytes[key]
            printf "%s%s%.0f%s%d%s%s%s%s%s%.0f%s%d\n", sortkey, OFS, bytes[key], OFS, count[key], OFS, key, OFS, k, OFS, total, OFS, total_count
        }
    }' \
| sort_records \
| awk -F"$field_sep" \
    -v limit="$limit" \
    -v dir="$dir" \
    -v mode="$mode" \
    -v color="$color" \
    -v plain="$plain" \
    -v format="$format" \
    -v group_by="$group_by" \
    -v min_size="$min_size" \
    -v min_share="$min_share" \
    -v errfile="$errfile" \
    -v partial_file="$partial_file" \
    -v top_stats_file="$top_stats_file" \
    -v start_ts="$start_ts" \
    -v version="$VERSION" \
    '
    BEGIN {
        if (color) {
            reset = "\033[0m"; bold = "\033[1m"; dim = "\033[2m"
            red = "\033[31m"; green = "\033[32m"; yellow = "\033[33m"; blue = "\033[34m"; magenta = "\033[35m"; cyan = "\033[36m"; white = "\033[97m"; gray = "\033[90m"
        } else {
            reset = bold = dim = red = green = yellow = blue = magenta = cyan = white = gray = ""
        }
        barw = plain ? 16 : 18
        limited = limit + 0 > 0
        filtering = (min_size + 0 > 0 || min_share + 0 >= 0)

        if (format == "json") { }
        else if (format == "tsv") {
            if (group_by == "type") print "type\tbytes\tsize\tfiles\tshare_pct"
            else print "ext\ttype\tbytes\tsize\tfiles\tshare_pct"
        } else if (format == "csv") {
            if (group_by == "type") print "type,bytes,size,files,share_pct"
            else print "ext,type,bytes,size,files,share_pct"
        } else if (plain) {
            printf "sizes %s - %s\n", dir, mode
            if (group_by == "type") printf "%-12s %14s %9s %8s %s\n", "TYPE", "SIZE", "FILES", "SHARE", "BAR"
            else printf "%-12s %-10s %14s %9s %8s %s\n", "EXT", "TYPE", "SIZE", "FILES", "SHARE", "BAR"
        } else {
            if (group_by == "type") {
                top = "╭──────────────┬────────────────┬───────────┬──────────┬────────────────────╮"
                mid = "├──────────────┼────────────────┼───────────┼──────────┼────────────────────┤"
                bottom = "╰──────────────┴────────────────┴───────────┴──────────┴────────────────────╯"
            } else {
                top = "╭──────────────┬──────────┬────────────────┬───────────┬──────────┬────────────────────╮"
                mid = "├──────────────┼──────────┼────────────────┼───────────┼──────────┼────────────────────┤"
                bottom = "╰──────────────┴──────────┴────────────────┴───────────┴──────────┴────────────────────╯"
            }
            printf "%s%s%s %s%s — %s%s\n", bold, "sizes", reset, dim, dir, mode, reset
            print gray top reset
            if (group_by == "type") {
                printf "%s│%s %s%-12s%s %s│%s %s%14s%s %s│%s %s%9s%s %s│%s %s%8s%s %s│%s %s%-18s%s %s│%s\n", gray, reset, bold cyan, "TYPE", reset, gray, reset, bold cyan, "SIZE", reset, gray, reset, bold cyan, "FILES", reset, gray, reset, bold cyan, "SHARE", reset, gray, reset, bold cyan, "BAR", reset, gray, reset
            } else {
                printf "%s│%s %s%-12s%s %s│%s %s%-8s%s %s│%s %s%14s%s %s│%s %s%9s%s %s│%s %s%8s%s %s│%s %s%-18s%s %s│%s\n", gray, reset, bold cyan, "EXT", reset, gray, reset, bold cyan, "TYPE", reset, gray, reset, bold cyan, "SIZE", reset, gray, reset, bold cyan, "FILES", reset, gray, reset, bold cyan, "SHARE", reset, gray, reset, bold cyan, "BAR", reset, gray, reset
            }
            print gray mid reset
        }
    }
    function clip(s, w) { return length(s) > w ? substr(s, 1, w - 1) "~" : s }
    function commas(n,    s, out) { s = sprintf("%d", n); out = ""; while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) } return s out }
    function human(n,    u, units) { split("B KiB MiB GiB TiB PiB", units, " "); u = 1; while (n >= 1024 && u < 6) { n /= 1024; u++ } if (u == 1) return sprintf("%9.0f %s", n, units[u]); return sprintf("%9.2f %s", n, units[u]) }
    function trimhuman(s) { sub(/^ +/, "", s); return s }
    function pctfmt(p) { if (p > 0 && p < 0.01) return sprintf("%8s", "<0.01%"); return sprintf("%7.2f%%", p) }
    function csvq(s,    t) { t = s; gsub(/"/, "\"\"", t); return "\"" t "\"" }
    function jsonq(s,    t) { t = s; gsub(/\\/, "\\\\", t); gsub(/"/, "\\\"", t); gsub(/\t/, "\\t", t); gsub(/\r/, "\\r", t); gsub(/\n/, "\\n", t); return "\"" t "\"" }
    function kind_color(k) { if (k == "video") return red; if (k == "image") return magenta; if (k == "audio") return blue; if (k == "archive") return yellow; if (k == "doc") return green; if (k == "data" || k == "database" || k == "code") return cyan; if (k == "model" || k == "game") return yellow; if (k == "font") return magenta; if (k == "3d" || k == "subs") return green; if (k == "binary") return red; if (k == "meta" || k == "none") return gray; if (k == "mixed" || k == "all") return white; return cyan }
    function heat_color(bytes, p) { if (bytes >= 10 * 1024 * 1024 * 1024 || p >= 20) return red; if (bytes >= 1024 * 1024 * 1024 || p >= 5) return yellow; if (bytes >= 100 * 1024 * 1024 || p >= 1) return green; if (bytes > 0) return gray; return gray }
    function makebar(p, c,    filled, i, full, empty, fullc, emptyc) { filled = int((p * barw / 100) + 0.5); if (filled > barw) filled = barw; full = empty = ""; fullc = plain ? "#" : "█"; emptyc = plain ? "." : "░"; for (i = 1; i <= filled; i++) full = full fullc; for (i = filled + 1; i <= barw; i++) empty = empty emptyc; return c full reset gray empty reset }
    function count_skipped(    line, n) { n = 0; while ((getline line < errfile) > 0) n++; close(errfile); return n }
    function is_partial(    line) { if ((getline line < partial_file) > 0) { close(partial_file); return 1 } close(partial_file); return 0 }
    function emit_json(    i, skipped, elapsed, partial) {
        skipped = count_skipped(); elapsed = (start_ts > 0) ? systime() - start_ts : 0; partial = is_partial() ? "true" : "false"
        printf "{\n  \"version\": %s,\n  \"root\": %s,\n  \"mode\": %s,\n  \"group_by\": %s,\n  \"elapsed_seconds\": %d,\n  \"scanned_files\": %d,\n  \"skipped_paths\": %d,\n  \"partial\": %s,\n  \"total_bytes\": %.0f,\n  \"rows\": [\n", jsonq(version), jsonq(dir), jsonq(mode), jsonq(group_by), elapsed, total_count, skipped, partial, total_bytes
        for (i = 1; i <= json_count; i++) printf "%s%s\n", (i > 1 ? "," : ""), json_rows[i]
        print "  ]\n}"
    }
    function emit_summary(    skipped, elapsed, msg) { if (format != "table") return; skipped = count_skipped(); elapsed = (start_ts > 0) ? systime() - start_ts : 0; msg = "Scanned: " commas(total_count) " files · " trimhuman(human(total_bytes)) " · " elapsed "s"; if (is_partial()) msg = msg " · partial"; if (skipped > 0) msg = msg " · " skipped " skipped"; print gray msg reset }
    function emit_machine(name, k, bytes, files, total, is_total,    share, h) { share = total ? bytes * 100 / total : 0; if (is_total && total > 0) share = 100; h = trimhuman(human(bytes)); if (format == "tsv") { if (group_by == "type") printf "%s\t%.0f\t%s\t%d\t%.2f\n", name, bytes, h, files, share; else printf "%s\t%s\t%.0f\t%s\t%d\t%.2f\n", name, k, bytes, h, files, share } else if (format == "csv") { if (group_by == "type") printf "%s,%.0f,%s,%d,%.2f\n", csvq(name), bytes, csvq(h), files, share; else printf "%s,%s,%.0f,%s,%d,%.2f\n", csvq(name), csvq(k), bytes, csvq(h), files, share } else if (format == "json") { if (group_by == "type") json_rows[++json_count] = sprintf("    {\"type\":%s,\"bytes\":%.0f,\"size\":%s,\"files\":%d,\"share_pct\":%.2f}", jsonq(name), bytes, jsonq(h), files, share); else json_rows[++json_count] = sprintf("    {\"ext\":%s,\"type\":%s,\"bytes\":%.0f,\"size\":%s,\"files\":%d,\"share_pct\":%.2f}", jsonq(name), jsonq(k), bytes, jsonq(h), files, share) } }
    function emit_row(name, k, bytes, files, total, is_total,    share, barpct, sc, kc, label, h, c, pct, b) { if (format != "table") { emit_machine(name, k, bytes, files, total, is_total); return } share = total ? bytes * 100 / total : 0; if (is_total && total > 0) { share = 100; barpct = 100 } else { barpct = max_bytes ? bytes * 100 / max_bytes : 0 } sc = is_total ? bold white : heat_color(bytes, share); kc = is_total ? bold white : kind_color(k); label = clip(name, 12); h = human(bytes); c = commas(files); pct = pctfmt(share); b = makebar(barpct, sc); if (plain) { if (group_by == "type") printf "%-12s %14s %9s %8s %s\n", label, h, c, pct, b; else printf "%-12s %-10s %14s %9s %8s %s\n", label, k, h, c, pct, b } else if (group_by == "type") { printf "%s│%s %s%-12s%s %s│%s %s%14s%s %s│%s %9s %s│%s %8s %s│%s %s %s│%s\n", gray, reset, kc, label, reset, gray, reset, sc, h, reset, gray, reset, c, gray, reset, pct, gray, reset, b, gray, reset } else { printf "%s│%s %s%-12s%s %s│%s %s%-8s%s %s│%s %s%14s%s %s│%s %9s %s│%s %8s %s│%s %s %s│%s\n", gray, reset, kc, label, reset, gray, reset, kc, k, reset, gray, reset, sc, h, reset, gray, reset, c, gray, reset, pct, gray, reset, b, gray, reset } }
    {
        seen = 1; bytes = $2 + 0; files = $3 + 0; name = $4; k = $5; total_bytes = $6 + 0; total_count = $7 + 0; share = total_bytes ? bytes * 100 / total_bytes : 0
        filtered = ((min_size + 0 > 0 && bytes < min_size) || (min_share + 0 >= 0 && share < min_share))
        if (!filtered && (!limited || shown < limit)) { if (shown == 0 || bytes > max_bytes) max_bytes = bytes; emit_row(name, k, bytes, files, total_bytes, 0); shown++ } else { other_bytes += bytes; other_count += files; other_types++ }
    }
    END {
        if (!seen) {
            total_bytes = 0; total_count = 0
            if (format == "table") {
                if (plain) { if (group_by == "type") printf "%-12s %14s %9s %8s %s\n", "NO_FILES", "-", "-", "-", "No files found"; else printf "%-12s %-10s %14s %9s %8s %s\n", "NO_FILES", "-", "-", "-", "-", "No files found" }
                else if (group_by == "type") printf "%s│%s %-12s %s│%s %14s %s│%s %9s %s│%s %8s %s│%s %-18s %s│%s\n", gray, reset, "NO_FILES", gray, reset, "-", gray, reset, "-", gray, reset, "-", gray, reset, "No files found", gray, reset
                else printf "%s│%s %-12s %s│%s %-8s %s│%s %14s %s│%s %9s %s│%s %8s %s│%s %-18s %s│%s\n", gray, reset, "NO_FILES", gray, reset, "-", gray, reset, "-", gray, reset, "-", gray, reset, "-", gray, reset, "No files found", gray, reset
            }
        } else if (other_types > 0) { if (format == "table" && !plain) print gray mid reset; if (max_bytes == 0 || other_bytes > max_bytes) max_bytes = other_bytes; emit_row("OTHER", "mixed", other_bytes, other_count, total_bytes, 0) }
        if (format == "table" && !plain) print gray mid reset
        emit_row("TOTAL", "all", total_bytes, total_count, total_bytes, 1)
        if (format == "table" && !plain) print gray bottom reset
        else if (format == "json") emit_json()
        emit_summary()
    }'
}

# shellcheck disable=SC2016
generate_top_files() {
scan_stream \
| awk -v RS='\0' -F"$field_sep" \
    -v merge="$merge" \
    -v dir="$dir" \
    -v excludes="$exclude_data" \
    -v includes="$include_data" \
    -v typedata="$type_data" \
    -v target_ext="$top_files" \
    -v OFS="$field_sep" \
    -v top_stats_file="$top_stats_file" \
    "$common_awk_functions"'
    BEGIN {
        nex = split(excludes, ex, "\034")
        ninc = split(includes, inc, "\034")
        ntypes = split(typedata, types, "\034")
        target = toupper(target_ext)
        if (target == "NO-EXT" || target == "NO_EXT" || target == "NONE") target = "NO_EXT"
    }
    NF >= 3 {
        size = $1 + 0; path = $2; base = $3
        if (excluded(path, base) || !included(path, base)) next
        ext = cached_extname(base); k = cached_kind(ext)
        if (!allowed_type(k)) next
        total += size; total_count += 1
        if (toupper(ext) == target)
            printf "%.0f%s%s%s%s%s%s\n", size, OFS, path, OFS, ext, OFS, k
    }
    END {
        printf "%.0f%s%d\n", total, OFS, total_count > top_stats_file
        close(top_stats_file)
    }' \
| LC_ALL=C sort -t "$field_sep" -k1,1nr \
| awk -F"$field_sep" \
    -v limit="$limit" \
    -v dir="$dir" \
    -v mode="$mode" \
    -v color="$color" \
    -v plain="$plain" \
    -v format="$format" \
    -v target_ext="$top_files" \
    -v errfile="$errfile" \
    -v partial_file="$partial_file" \
    -v top_stats_file="$top_stats_file" \
    -v start_ts="$start_ts"  \
    -v version="$VERSION" '
    BEGIN {
        if (color) { reset = "\033[0m"; bold = "\033[1m"; dim = "\033[2m"; cyan = "\033[36m"; gray = "\033[90m"; white = "\033[97m" } else { reset = bold = dim = cyan = gray = white = "" }
        if (format == "json") { }
        else if (format == "tsv") print "bytes\tsize\text\ttype\tpath"
        else if (format == "csv") print "bytes,size,ext,type,path"
        else if (plain) { printf "sizes %s - top %s files - %s\n", dir, target_ext, mode; printf "%14s %-8s %-10s %s\n", "SIZE", "EXT", "TYPE", "PATH" }
        else {
            top = "╭────────────────┬──────────┬──────────┬────────────────────────────────────────────────────────────╮"
            mid = "├────────────────┼──────────┼──────────┼────────────────────────────────────────────────────────────┤"
            bottom = "╰────────────────┴──────────┴──────────┴────────────────────────────────────────────────────────────╯"
            printf "%s%s%s %s%s — top %s files — %s%s\n", bold, "sizes", reset, dim, dir, target_ext, mode, reset
            print gray top reset
            printf "%s│%s %s%14s%s %s│%s %s%-8s%s %s│%s %s%-8s%s %s│%s %s%-58s%s %s│%s\n", gray, reset, bold cyan, "SIZE", reset, gray, reset, bold cyan, "EXT", reset, gray, reset, bold cyan, "TYPE", reset, gray, reset, bold cyan, "PATH", reset, gray, reset
            print gray mid reset
        }
    }
    function human(n,    u, units) { split("B KiB MiB GiB TiB PiB", units, " "); u = 1; while (n >= 1024 && u < 6) { n /= 1024; u++ } if (u == 1) return sprintf("%9.0f %s", n, units[u]); return sprintf("%9.2f %s", n, units[u]) }
    function trimhuman(s) { sub(/^ +/, "", s); return s }
    function clip(s, w) { return length(s) > w ? substr(s, 1, w - 1) "~" : s }
    function csvq(s,    t) { t = s; gsub(/"/, "\"\"", t); return "\"" t "\"" }
    function jsonq(s,    t) { t = s; gsub(/\\/, "\\\\", t); gsub(/"/, "\\\"", t); gsub(/\t/, "\\t", t); gsub(/\r/, "\\r", t); gsub(/\n/, "\\n", t); return "\"" t "\"" }
    function count_skipped(    line, n) { n = 0; while ((getline line < errfile) > 0) n++; close(errfile); return n }
    function commas(n,    s, out) { s = sprintf("%d", n); out = ""; while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) } return s out }
    function read_top_stats(    line, a) { if ((getline line < top_stats_file) > 0) { split(line, a, FS); total_bytes = a[1] + 0; total_count = a[2] + 0 } close(top_stats_file) }
    function is_partial(    line) { if ((getline line < partial_file) > 0) { close(partial_file); return 1 } close(partial_file); return 0 }
    function emit_summary(    skipped, elapsed, msg) { if (format != "table") return; read_top_stats(); skipped = count_skipped(); elapsed = (start_ts > 0) ? systime() - start_ts : 0; msg = "Scanned: " commas(total_count) " files · " trimhuman(human(total_bytes)) " · " elapsed "s"; if (is_partial()) msg = msg " · partial"; if (skipped > 0) msg = msg " · " skipped " skipped"; print gray msg reset }
    function emit_json(    i, skipped, elapsed, partial) {
        read_top_stats(); skipped = count_skipped(); elapsed = (start_ts > 0) ? systime() - start_ts : 0; partial = is_partial() ? "true" : "false"
        printf "{\n  \"version\": %s,\n  \"root\": %s,\n  \"mode\": %s,\n  \"view\": \"top-files\",\n  \"target_ext\": %s,\n  \"elapsed_seconds\": %d,\n  \"scanned_files\": %d,\n  \"skipped_paths\": %d,\n  \"partial\": %s,\n  \"total_bytes\": %.0f,\n  \"rows\": [\n", jsonq(version), jsonq(dir), jsonq(mode), jsonq(target_ext), elapsed, total_count, skipped, partial, total_bytes
        for (i = 1; i <= json_count; i++) printf "%s%s\n", (i > 1 ? "," : ""), json_rows[i]
        print "  ]\n}"
    }
    function emit_row(bytes, path, ext, k,    h) { h = trimhuman(human(bytes)); if (format == "tsv") printf "%.0f\t%s\t%s\t%s\t%s\n", bytes, h, ext, k, path; else if (format == "csv") printf "%.0f,%s,%s,%s,%s\n", bytes, csvq(h), csvq(ext), csvq(k), csvq(path); else if (format == "json") { json_rows[++json_count] = sprintf("    {\"bytes\":%.0f,\"size\":%s,\"ext\":%s,\"type\":%s,\"path\":%s}", bytes, jsonq(h), jsonq(ext), jsonq(k), jsonq(path)) } else if (plain) printf "%14s %-8s %-10s %s\n", human(bytes), ext, k, path; else printf "%s│%s %s%14s%s %s│%s %-8s %s│%s %-8s %s│%s %-58s %s│%s\n", gray, reset, white, human(bytes), reset, gray, reset, ext, gray, reset, k, gray, reset, clip(path, 58), gray, reset }
    {
        seen = 1; bytes = $1 + 0; path = $2; ext = $3; k = $4
        if (shown < limit) { emit_row(bytes, path, ext, k); shown++ }
    }
    END {
        if (!seen && format == "table") {
            total_bytes = 0; total_count = 0
            if (plain) printf "%14s %-8s %-10s %s\n", "-", "-", "-", "No matching files"
            else printf "%s│%s %14s %s│%s %-8s %s│%s %-8s %s│%s %-58s %s│%s\n", gray, reset, "-", gray, reset, "-", gray, reset, "-", gray, reset, "No matching files", gray, reset
        }
        if (format == "table" && !plain) print gray bottom reset
        else if (format == "json") emit_json()
        emit_summary()
    }'
}


# shellcheck disable=SC2016
generate_dirs() {
scan_stream \
| awk -v RS='\0' -F"$field_sep" \
    -v merge="$merge" \
    -v sort_by="$sort_by" \
    -v dir="$dir" \
    -v excludes="$exclude_data" \
    -v includes="$include_data" \
    -v typedata="$type_data" \
    -v top_dirs="$top_dirs" \
    -v top_dirs_ext="$top_dirs_ext" \
    -v by_dir="$by_dir" \
    -v OFS="$field_sep" \
    "$common_awk_functions"'
    BEGIN {
        nex = split(excludes, ex, "\034")
        ninc = split(includes, inc, "\034")
        ntypes = split(typedata, types, "\034")
        target = toupper(top_dirs_ext)
        if (target == "NO-EXT" || target == "NO_EXT" || target == "NONE") target = "NO_EXT"
    }
    function parent_dir(path,    rel, d) {
        rel = relpath(path)
        if (rel !~ /\//) return "."
        d = rel
        sub(/\/[^\/]*$/, "", d)
        return "./" d
    }
    function first_dir(path,    rel, a, n) {
        rel = relpath(path)
        n = split(rel, a, "/")
        return (n > 1) ? "./" a[1] : "."
    }
    NF >= 3 {
        size = $1 + 0; path = $2; base = $3
        if (excluded(path, base) || !included(path, base)) next
        ext = cached_extname(base); k = cached_kind(ext)
        if (!allowed_type(k)) next
        if (top_dirs && target != "" && toupper(ext) != target) next
        key = by_dir ? first_dir(path) : parent_dir(path)
        bytes[key] += size
        count[key] += 1
        ext_bytes[key SUBSEP ext] += size
        total += size
        total_count += 1
    }
    END {
        for (combo in ext_bytes) {
            split(combo, parts, SUBSEP)
            key = parts[1]; ext = parts[2]
            if (!(key in top_ext_bytes) || ext_bytes[combo] > top_ext_bytes[key]) {
                top_ext_bytes[key] = ext_bytes[combo]
                top_ext[key] = ext
            }
        }
        for (key in bytes) {
            share = total ? bytes[key] * 100 / total : 0
            if (sort_by == "files") sortkey = count[key]
            else if (sort_by == "ext" || sort_by == "type") sortkey = key
            else if (sort_by == "share") sortkey = share
            else sortkey = bytes[key]
            printf "%s%s%.0f%s%d%s%s%s%s%s%.0f%s%d\n", sortkey, OFS, bytes[key], OFS, count[key], OFS, key, OFS, top_ext[key], OFS, total, OFS, total_count
        }
    }' \
| sort_records \
| awk -F"$field_sep" \
    -v limit="$limit" \
    -v dir="$dir" \
    -v mode="$mode" \
    -v color="$color" \
    -v plain="$plain" \
    -v format="$format" \
    -v by_dir="$by_dir" \
    -v top_dirs_ext="$top_dirs_ext" \
    -v errfile="$errfile" \
    -v partial_file="$partial_file" \
    -v start_ts="$start_ts" \
    -v version="$VERSION" '
    BEGIN {
        if (color) { reset = "\033[0m"; bold = "\033[1m"; dim = "\033[2m"; cyan = "\033[36m"; gray = "\033[90m"; white = "\033[97m" } else { reset = bold = dim = cyan = gray = white = "" }
        limited = limit + 0 > 0
        title = by_dir ? "by directory" : "top directories"
        if (!by_dir && top_dirs_ext != "") title = title " for " top_dirs_ext
        if (format == "tsv") print "dir\tbytes\tsize\tfiles\tshare_pct\ttop_ext"
        else if (format == "csv") print "dir,bytes,size,files,share_pct,top_ext"
        else if (format == "table" && plain) { printf "sizes %s - %s - %s\n", dir, title, mode; printf "%-30s %14s %9s %8s %-8s\n", "DIR", "SIZE", "FILES", "SHARE", "TOP_EXT" }
        else if (format == "table") {
            top = "╭────────────────────────────────┬────────────────┬───────────┬──────────┬──────────╮"
            mid = "├────────────────────────────────┼────────────────┼───────────┼──────────┼──────────┤"
            bottom = "╰────────────────────────────────┴────────────────┴───────────┴──────────┴──────────╯"
            printf "%s%s%s %s%s — %s — %s%s\n", bold, "sizes", reset, dim, dir, title, mode, reset
            print gray top reset
            printf "%s│%s %s%-30s%s %s│%s %s%14s%s %s│%s %s%9s%s %s│%s %s%8s%s %s│%s %s%-8s%s %s│%s\n", gray, reset, bold cyan, "DIR", reset, gray, reset, bold cyan, "SIZE", reset, gray, reset, bold cyan, "FILES", reset, gray, reset, bold cyan, "SHARE", reset, gray, reset, bold cyan, "TOP_EXT", reset, gray, reset
            print gray mid reset
        }
    }
    function human(n,    u, units) { split("B KiB MiB GiB TiB PiB", units, " "); u = 1; while (n >= 1024 && u < 6) { n /= 1024; u++ } if (u == 1) return sprintf("%9.0f %s", n, units[u]); return sprintf("%9.2f %s", n, units[u]) }
    function trimhuman(s) { sub(/^ +/, "", s); return s }
    function clip(s, w) { return length(s) > w ? substr(s, 1, w - 1) "~" : s }
    function pctfmt(p) { if (p > 0 && p < 0.01) return sprintf("%8s", "<0.01%"); return sprintf("%7.2f%%", p) }
    function csvq(s,    t) { t = s; gsub(/"/, "\"\"", t); return "\"" t "\"" }
    function jsonq(s,    t) { t = s; gsub(/\\/, "\\\\", t); gsub(/"/, "\\\"", t); gsub(/\t/, "\\t", t); gsub(/\r/, "\\r", t); gsub(/\n/, "\\n", t); return "\"" t "\"" }
    function commas(n,    s, out) { s = sprintf("%d", n); out = ""; while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) } return s out }
    function count_skipped(    line, n) { n = 0; while ((getline line < errfile) > 0) n++; close(errfile); return n }
    function is_partial(    line) { if ((getline line < partial_file) > 0) { close(partial_file); return 1 } close(partial_file); return 0 }
    function emit_json(    i, skipped, elapsed, partial) {
        skipped = count_skipped(); elapsed = (start_ts > 0) ? systime() - start_ts : 0; partial = is_partial() ? "true" : "false"
        printf "{\n  \"version\": %s,\n  \"root\": %s,\n  \"mode\": %s,\n  \"view\": %s,\n  \"elapsed_seconds\": %d,\n  \"scanned_files\": %d,\n  \"skipped_paths\": %d,\n  \"partial\": %s,\n  \"total_bytes\": %.0f,\n  \"rows\": [\n", jsonq(version), jsonq(dir), jsonq(mode), jsonq(by_dir ? "by-dir" : "top-dirs"), elapsed, total_count, skipped, partial, total_bytes
        for (i = 1; i <= json_count; i++) printf "%s%s\n", (i > 1 ? "," : ""), json_rows[i]
        print "  ]\n}"
    }
    function emit_summary(    skipped, elapsed, msg) { if (format != "table") return; skipped = count_skipped(); elapsed = (start_ts > 0) ? systime() - start_ts : 0; msg = "Scanned: " commas(total_count) " files · " trimhuman(human(total_bytes)) " · " elapsed "s"; if (is_partial()) msg = msg " · partial"; if (skipped > 0) msg = msg " · " skipped " skipped"; print gray msg reset }
    function emit_row(path, bytes, files, top_ext, total, is_total,    share, h, pct) {
        share = total ? bytes * 100 / total : 0; if (is_total && total > 0) share = 100; h = trimhuman(human(bytes)); pct = pctfmt(share)
        if (format == "tsv") printf "%s\t%.0f\t%s\t%d\t%.2f\t%s\n", path, bytes, h, files, share, top_ext
        else if (format == "csv") printf "%s,%.0f,%s,%d,%.2f,%s\n", csvq(path), bytes, csvq(h), files, share, csvq(top_ext)
        else if (format == "json") { json_rows[++json_count] = sprintf("    {\"dir\":%s,\"bytes\":%.0f,\"size\":%s,\"files\":%d,\"share_pct\":%.2f,\"top_ext\":%s}", jsonq(path), bytes, jsonq(h), files, share, jsonq(top_ext)) }
        else if (plain) printf "%-30s %14s %9s %8s %-8s\n", clip(path, 30), human(bytes), commas(files), pct, top_ext
        else printf "%s│%s %s%-30s%s %s│%s %s%14s%s %s│%s %9s %s│%s %8s %s│%s %-8s %s│%s\n", gray, reset, white, clip(path, 30), reset, gray, reset, white, human(bytes), reset, gray, reset, commas(files), gray, reset, pct, gray, reset, top_ext, gray, reset
    }
    {
        seen = 1; bytes = $2 + 0; files = $3 + 0; path = $4; top_ext = $5; total_bytes = $6 + 0; total_count = $7 + 0
        if (!limited || shown < limit) { emit_row(path, bytes, files, top_ext, total_bytes, 0); shown++ } else { other_bytes += bytes; other_count += files; other_types++ }
    }
    END {
        if (!seen && format == "table") {
            total_bytes = 0; total_count = 0
            if (plain) printf "%-30s %14s %9s %8s %-8s\n", "NO_FILES", "-", "-", "-", "-"
            else printf "%s│%s %-30s %s│%s %14s %s│%s %9s %s│%s %8s %s│%s %-8s %s│%s\n", gray, reset, "NO_FILES", gray, reset, "-", gray, reset, "-", gray, reset, "-", gray, reset, "-", gray, reset
        } else if (other_types > 0) { if (format == "table" && !plain) print gray mid reset; emit_row("OTHER", other_bytes, other_count, "mixed", total_bytes, 0) }
        if (format == "table" && !plain) print gray mid reset
        emit_row("TOTAL", total_bytes, total_count, "all", total_bytes, 1)
        if (format == "table" && !plain) print gray bottom reset
        else if (format == "json") emit_json()
        emit_summary()
    }'
}

print_errors() {
    err_count=$(wc -l < "$errfile" | tr -d '[:space:]')
    if [ "${err_count:-0}" -gt 0 ] 2>/dev/null; then
        if [ "$color" -eq 1 ]; then
            printf '\033[90m%s\033[0m\n' "sizes: skipped $err_count unreadable path(s); use --errors to print them" >&2
        else
            printf '%s\n' "sizes: skipped $err_count unreadable path(s); use --errors to print them" >&2
        fi

        if [ "$show_errors" -eq 1 ]; then
            cat "$errfile" >&2
        fi
    fi
}

generate() {
    if [ "${SIZES_DEBUG_TIMING:-}" != "" ]; then
        timing_start=$(date +%s 2>/dev/null || printf '0')
    else
        timing_start=0
    fi

    if [ "$top_files" != "" ]; then
        generate_top_files
    elif [ "$top_dirs" -eq 1 ] || [ "$by_dir" -eq 1 ]; then
        generate_dirs
    else
        generate_report
    fi
    print_errors

    if [ "${SIZES_DEBUG_TIMING:-}" != "" ]; then
        timing_end=$(date +%s 2>/dev/null || printf '0')
        if [ "$timing_start" -gt 0 ] && [ "$timing_end" -ge "$timing_start" ]; then
            printf '%s\n' "sizes: timing total=$((timing_end - timing_start))s" >&2
        fi
    fi
}


# shellcheck disable=SC2016
generate_interactive_data() {
    records_file=$1

    scan_stream \
    | awk -v RS='\0' -F"$field_sep" \
        -v merge="$merge" \
        -v dir="$dir" \
        -v excludes="$exclude_data" \
        -v includes="$include_data" \
        -v typedata="$type_data" \
        -v records_file="$records_file" \
        -v color="$color" \
        -v OFS="$field_sep" \
        "$common_awk_functions"'
        BEGIN {
            nex = split(excludes, ex, "\034")
            ninc = split(includes, inc, "\034")
            ntypes = split(typedata, types, "\034")
        }
        NF >= 3 {
            size = $1 + 0; path = $2; base = $3
            if (excluded(path, base) || !included(path, base)) next
            ext = cached_extname(base); k = cached_kind(ext)
            if (!allowed_type(k)) next

            bytes[ext] += size
            count[ext] += 1
            type_for[ext] = k
            total += size
            total_count += 1

            printf "%.0f%s%s%s%s%s%s\n", size, OFS, path, OFS, ext, OFS, k >> records_file
        }
        END {
            close(records_file)
            for (e in bytes) {
                sortkey = bytes[e]
                printf "%s%s%.0f%s%d%s%s%s%s%s%.0f%s%d\n", sortkey, OFS, bytes[e], OFS, count[e], OFS, e, OFS, type_for[e], OFS, total, OFS, total_count
            }
        }' \
    | sort_records \
    | awk -F"$field_sep" \
        -v OFS="$field_sep" \
        -v limit="$limit" \
        -v min_size="$min_size" \
        -v min_share="$min_share" \
        -v color="$color" '
        function human(n,    u, units) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            u = 1
            while (n >= 1024 && u < 6) { n /= 1024; u++ }
            if (u == 1) return sprintf("%.0f %s", n, units[u])
            return sprintf("%.2f %s", n, units[u])
        }
        function commas(n,    s, out) {
            s = sprintf("%d", n); out = ""
            while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) }
            return s out
        }
        function kind_color(k) {
            if (!color) return ""
            if (k == "video") return red
            if (k == "image") return magenta
            if (k == "audio") return blue
            if (k == "archive") return yellow
            if (k == "doc") return green
            if (k == "data" || k == "database" || k == "code") return cyan
            if (k == "model" || k == "game") return yellow
            if (k == "font") return magenta
            if (k == "3d" || k == "subs") return green
            if (k == "binary") return red
            if (k == "meta" || k == "none") return gray
            if (k == "mixed" || k == "all") return white
            return cyan
        }
        function heat_color(bytes, p) {
            if (!color) return ""
            if (bytes >= 10 * 1024 * 1024 * 1024 || p >= 20) return red
            if (bytes >= 1024 * 1024 * 1024 || p >= 5) return yellow
            if (bytes >= 100 * 1024 * 1024 || p >= 1) return green
            if (bytes > 0) return gray
            return gray
        }
        function row_display(ext, k, bytes, files, total,    share, kc, sc, h, c) {
            share = total ? bytes * 100 / total : 0
            kc = kind_color(k); sc = heat_color(bytes, share); h = human(bytes); c = commas(files)
            return sprintf("%s%-12s%s  %s%-10s%s  %s%14s%s  %9s  %7.2f%%", kc, ext, reset, kc, k, reset, sc, h, reset, c, share)
        }
        BEGIN {
            limited = limit + 0 > 0
            if (color) {
                reset = "\033[0m"; red = "\033[31m"; green = "\033[32m"; yellow = "\033[33m"; blue = "\033[34m"; magenta = "\033[35m"; cyan = "\033[36m"; white = "\033[97m"; gray = "\033[90m"
            } else {
                reset = red = green = yellow = blue = magenta = cyan = white = gray = ""
            }
        }
        {
            seen = 1
            bytes = $2 + 0
            files = $3 + 0
            ext = $4
            k = $5
            total_bytes = $6 + 0
            total_count = $7 + 0
            share = total_bytes ? bytes * 100 / total_bytes : 0
            filtered = ((min_size + 0 > 0 && bytes < min_size) || (min_share + 0 >= 0 && share < min_share))
            if (!filtered && (!limited || shown < limit)) {
                printf "%s%s%s%s%s%s%.0f%s%s%s%d%s%.2f\n", ext, OFS, row_display(ext, k, bytes, files, total_bytes), OFS, k, OFS, bytes, OFS, human(bytes), OFS, files, OFS, share
                shown++
            } else {
                other_bytes += bytes
                other_count += files
                other_types++
            }
        }
        END {
            if (other_types > 0) {
                share = total_bytes ? other_bytes * 100 / total_bytes : 0
                printf "%s%s%s%s%s%s%.0f%s%s%s%d%s%.2f\n", "OTHER", OFS, row_display("OTHER", "mixed", other_bytes, other_count, total_bytes), OFS, "mixed", OFS, other_bytes, OFS, human(other_bytes), OFS, other_count, OFS, share
            }
            if (seen) printf "%s%s%s%s%s%s%.0f%s%s%s%d%s%.2f\n", "TOTAL", OFS, row_display("TOTAL", "all", total_bytes, total_count, total_bytes), OFS, "all", OFS, total_bytes, OFS, human(total_bytes), OFS, total_count, OFS, 100
        }'
}


write_interactive_preview_script() {
    preview_script=$1
    cat >"$preview_script" <<'PREVIEW'
#!/usr/bin/env sh
set -eu

records_file=${1:-}
target=${2:-}
preview_mode=${3:-summary}
field_sep=$(printf '\037')

label=$target
target_type=
case "$target" in
    TYPE:*)
        target_type=${target#TYPE:}
        label=$target_type
        ;;
esac

if [ "$preview_mode" = "help" ] || [ "$target" = "HELP" ]; then
    case "$preview_mode" in
        main-help|help)
            cat <<'HELP'
sizes › main
────────────

Enter    open selected mode
Ctrl-R   refresh scan
Esc      quit
Ctrl-Q   quit
/        search menu

Views
  Extensions       extension totals → files / directories
  Types            category totals → extensions / files / dirs
  Top files        largest files in the scan
  Top directories  largest directories in the scan
  By directory     directory summaries
HELP
            ;;
        type-help)
            cat <<'HELP'
sizes › types
─────────────

Enter    browse extensions in selected type
Ctrl-F   browse files in selected type
Ctrl-D   browse directories in selected type
?        show help
Esc      back
Ctrl-Q   quit
HELP
            ;;
        file-help)
            cat <<'HELP'
sizes › files
─────────────

Enter    action menu
Tab      select multiple files
Ctrl-O   open selected file
Ctrl-P   open containing folder
Ctrl-Y   copy selected path
?        show help
Esc      back
Ctrl-Q   quit

Preview: Alt-J/K scroll · Alt-U/D page · Alt-T/B top/bottom
HELP
            ;;
        dir-help)
            cat <<'HELP'
sizes › directories
──────────────────

Enter    action menu
Ctrl-O   open selected directory
Ctrl-Y   copy selected path
?        show help
Esc      back
Ctrl-Q   quit

Preview: Alt-J/K scroll · Alt-U/D page · Alt-T/B top/bottom
HELP
            ;;
        *)
            cat <<'HELP'
sizes › extensions
──────────────────

Enter    browse files for selected extension
Ctrl-F   browse files for selected extension
Ctrl-D   browse directories for selected extension
?        show help
Esc      back
Ctrl-Q   quit
HELP
            ;;
    esac
    exit 0
fi

if [ "$target" = "" ]; then
    cat <<'EMPTY'
No selection
────────────

Use ↑/↓ to choose an item.
Press ? for contextual help.
EMPTY
    exit 0
fi

if [ "$target" = "OTHER" ]; then
    printf '%s\n' 'OTHER'
    printf '%s\n\n' '─────'
    printf '%s\n' 'This is a folded summary row.'
    printf '%s\n' 'Try increasing --limit or removing min filters.'
    exit 0
fi

filter_awk='function keep() {
    if (target == "TOTAL") return 1
    if (target_type != "") return $4 == target_type
    return toupper($3) == toupper(target)
}'

case "$preview_mode" in
    dirs)
        awk -F"$field_sep" -v target="$target" -v target_type="$target_type" "$filter_awk"'
            function dirname(path,    d) {
                d = path
                sub(/\/[^\/]*$/, "", d)
                if (d == "" || d == path) return "."
                return d
            }
            keep() {
                d = dirname($2)
                bytes[d] += $1
                files[d] += 1
                if (kind == "") kind = $4
            }
            END {
                for (d in bytes) printf "%.0f%s%d%s%s%s%s\n", bytes[d], FS, files[d], FS, d, FS, kind
            }' "$records_file" \
        | LC_ALL=C sort -t "$field_sep" -k1,1nr \
        | awk -F"$field_sep" -v target="$target" -v label="$label" '
            function human(n,    u, units) {
                split("B KiB MiB GiB TiB PiB", units, " ")
                u = 1
                while (n >= 1024 && u < 6) { n /= 1024; u++ }
                if (u == 1) return sprintf("%.0f %s", n, units[u])
                return sprintf("%.2f %s", n, units[u])
            }
            function middle(s, w,    keep, left, right) {
                if (length(s) <= w) return s
                keep = w - 3; left = int(keep * 0.42); right = keep - left
                return substr(s, 1, left) "..." substr(s, length(s) - right + 1)
            }
            BEGIN { title = target == "TOTAL" ? "Top directories overall" : "Top directories for " label }
            NR == 1 { print title; print "" }
            NR <= 30 { seen = 1; printf "%11s  %8d  %s\n", human($1), $2, middle($3, 96) }
            END { if (!seen) { print title; print ""; print "No matching directories." } }'
        ;;
    files)
        awk -F"$field_sep" -v target="$target" -v target_type="$target_type" "$filter_awk"'
            keep() { print $0 }
        ' "$records_file" \
        | LC_ALL=C sort -t "$field_sep" -k1,1nr \
        | awk -F"$field_sep" -v target="$target" -v label="$label" '
            function human(n,    u, units) {
                split("B KiB MiB GiB TiB PiB", units, " ")
                u = 1
                while (n >= 1024 && u < 6) { n /= 1024; u++ }
                if (u == 1) return sprintf("%.0f %s", n, units[u])
                return sprintf("%.2f %s", n, units[u])
            }
            function middle(s, w,    keep, left, right) {
                if (length(s) <= w) return s
                keep = w - 3; left = int(keep * 0.42); right = keep - left
                return substr(s, 1, left) "..." substr(s, length(s) - right + 1)
            }
            BEGIN { title = target == "TOTAL" ? "Top files overall" : "Top files for " label }
            NR == 1 { if (target != "TOTAL" && $4 != "") title = title " (" $4 ")"; print title; print "" }
            NR <= 30 { seen = 1; printf "%11s  %s\n", human($1), middle($2, 104) }
            END { if (!seen) { print title; print ""; print "No matching files." } }'
        ;;
    *)
        printf '%s\n' "$label"
        printf '%s\n\n' '────────────────────────'
        awk -F"$field_sep" -v target="$target" -v target_type="$target_type" "$filter_awk"'
            function human(n,    u, units) {
                split("B KiB MiB GiB TiB PiB", units, " ")
                u = 1
                while (n >= 1024 && u < 6) { n /= 1024; u++ }
                if (u == 1) return sprintf("%.0f %s", n, units[u])
                return sprintf("%.2f %s", n, units[u])
            }
            { grand += $1 }
            keep() { bytes += $1; files += 1; if (kind == "") kind = $4 }
            END {
                share = grand ? bytes * 100 / grand : 0
                if (target == "TOTAL" && grand > 0) share = 100
                printf "%-10s %s\n", "Type:", (target_type != "" ? target_type : kind)
                printf "%-10s %s\n", "Size:", human(bytes)
                printf "%-10s %d\n", "Files:", files
                printf "%-10s %.2f%%\n", "Share:", share
            }' "$records_file"
        printf '\n%s\n' 'Top directories'
        printf '%s\n' '───────────────'
        "$0" "$records_file" "$target" dirs 2>/dev/null | sed -n '3,10p'
        printf '\n%s\n' 'Top files'
        printf '%s\n' '─────────'
        "$0" "$records_file" "$target" files 2>/dev/null | sed -n '3,12p'
        printf '\n%s\n' 'Keys: Enter/Ctrl-F files · Ctrl-D dirs · ? help · Esc back'
        ;;
esac
PREVIEW
    chmod +x "$preview_script"
}

run_interactive_scan() {
    summary_file=$1
    records_file=$2

    if [ "$progress" -eq 1 ]; then
        progress_count_file=$(mktemp "${TMPDIR:-/tmp}/sizes-progress.XXXXXX") || exit 1
        progress_err=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-stderr.XXXXXX") || exit 1

        generate_interactive_data "$records_file" >"$summary_file" 2>"$progress_err" &
        progress_pid=$!
        progress_i=0

        while kill -0 "$progress_pid" 2>/dev/null; do
            progress_i=$((progress_i + 1))
            case $((progress_i % 4)) in
                0) progress_ch='-' ;;
                1) progress_ch="\\" ;;
                2) progress_ch='|' ;;
                *) progress_ch='/' ;;
            esac
            progress_count=""
            if [ -s "$progress_count_file" ]; then
                progress_count=$(tail -n 1 "$progress_count_file" 2>/dev/null | tr -cd '0-9' || printf '')
            fi
            case "$progress_count" in
                ''|*[!0-9]*) printf '\rsizes: scanning %s (%s) %s' "$dir" "$mode" "$progress_ch" >&2 ;;
                *) printf '\rsizes: scanning %s (%s) %s %s files' "$dir" "$mode" "$progress_ch" "$progress_count" >&2 ;;
            esac
            sleep 0.1
        done

        wait "$progress_pid"
        progress_status=$?
        printf '\r%120s\r' ' ' >&2
        cat "$progress_err" >&2
        rm -f "$progress_err" "$progress_count_file"
        return "$progress_status"
    fi

    printf '%s
' "sizes: scanning $dir ($mode)..." >&2
    generate_interactive_data "$records_file" >"$summary_file"
}

interactive_select_parts() {
    fzf_output=$1
    first=$(printf '%s\n' "$fzf_output" | sed -n '1p')
    second=$(printf '%s\n' "$fzf_output" | sed -n '2p')

    case "$first" in
        enter|ctrl-f|ctrl-d|ctrl-o|ctrl-p|ctrl-y|ctrl-l|ctrl-a|ctrl-b|ctrl-t|ctrl-r)
            printf '%s\n%s\n' "$first" "$second"
            ;;
        '')
            printf '%s\n%s\n' '' ''
            ;;
        *)
            printf '%s\n%s\n' 'enter' "$first"
            ;;
    esac
}

write_interactive_item_preview_script() {
    item_preview_script=$1
    cat >"$item_preview_script" <<'ITEMPREVIEW'
#!/usr/bin/env sh
set -eu

mode=${1:-file}
path=${2:-}
size=${3:-}
kind=${4:-}
ext=${5:-}
files=${6:-}

human_path=$path
if [ "$human_path" = "" ] || [ "$human_path" = "{}" ]; then
    cat <<'EMPTY'
No selection
────────────

Use ↑/↓ to choose an item.
Press ? for contextual help.
EMPTY
    exit 0
fi

is_image_ext() {
    case "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" in
        JPG|JPEG|PNG|WEBP|GIF|AVIF|JXL|BMP|PSD|TIFF|TIF|HEIC|SVG|XCF|KRA|ICO) return 0 ;;
        *) return 1 ;;
    esac
}

preview_image() {
    [ "${SIZES_IMAGE_PREVIEW:-}" != "" ] || return 0
    [ -f "$human_path" ] || return 0
    is_image_ext "$ext" || return 0

    printf '\n%s\n' 'Image preview'
    printf '%s\n' '─────────────'

    # fzf preview panes are not a safe place for terminal graphics protocols
    # such as kitty/wezterm/imgcat/viu: they can draw outside the preview pane
    # and leave stale images behind after scrolling or leaving the browser.
    # Use chafa in symbol mode only so previews stay text/ANSI-bound.
    if command -v chafa >/dev/null 2>&1; then
        preview_size=${SIZES_IMAGE_PREVIEW_SIZE:-56x16}
        chafa --format=symbols --size="$preview_size" "$human_path" 2>/dev/null || \
            printf '%s\n' 'Image preview failed. Try a newer chafa or unset SIZES_IMAGE_PREVIEW.'
    else
        printf '%s\n' 'Set SIZES_IMAGE_PREVIEW=1 and install chafa for safe text image previews.'
    fi
}
case "$mode" in
    help)
        cat <<'HELP'
sizes › files / directories
──────────────────────────

Enter    action menu
Tab      select multiple files
Ctrl-O   open selected item
Ctrl-P   open containing folder for files
Ctrl-Y   copy selected path
Esc      back
Ctrl-Q   quit

Preview scrolling
  Alt-J/K  down/up
  Alt-D/U  page down/up
  Alt-T/B  top/bottom
HELP
        ;;
    dir)
        printf '%s\n' 'Directory'
        printf '%s\n\n' '─────────'
        printf '%-9s %s\n' 'Path:' "$human_path"
        printf '%-9s %s\n' 'Size:' "${size:-'-'}"
        printf '%-9s %s\n' 'Files:' "${files:-'-'}"
        printf '%-9s %s\n' 'Ext:' "${ext:-'-'}"
        printf '%-9s %s\n' 'Type:' "${kind:-'-'}"
        printf '\n%s\n' 'Actions'
        printf '%s\n' '───────'
        printf '%-9s %s\n' 'Enter' 'action menu'
        printf '%-9s %s\n' 'Ctrl-O' 'open directory'
        printf '%-9s %s\n' 'Ctrl-Y' 'copy path'
        printf '%-9s %s\n' 'Esc' 'go back / quit'
        ;;
    *)
        printf '%s\n' 'File'
        printf '%s\n\n' '────'
        printf '%-9s %s\n' 'Path:' "$human_path"
        printf '%-9s %s\n' 'Size:' "${size:-'-'}"
        printf '%-9s %s\n' 'Ext:' "${ext:-'-'}"
        printf '%-9s %s\n' 'Type:' "${kind:-'-'}"
        printf '\n%s\n' 'Actions'
        printf '%s\n' '───────'
        printf '%-9s %s\n' 'Tab' 'multi-select'
        printf '%-9s %s\n' 'Enter' 'action menu / print selected files'
        printf '%-9s %s\n' 'Ctrl-O' 'open selected file'
        printf '%-9s %s\n' 'Ctrl-P' 'open containing folder'
        printf '%-9s %s\n' 'Ctrl-Y' 'copy selected path'
        printf '%-9s %s\n' 'Esc' 'go back / quit'
        preview_image
        ;;
esac
ITEMPREVIEW
    chmod +x "$item_preview_script"
}

write_interactive_open_script() {
    open_script=$1
    cat >"$open_script" <<'OPENSCRIPT'
#!/usr/bin/env sh
set -eu

path=${1:-}
action=${2:-open}
[ "$path" = "" ] && exit 0

open_path() {
    target=$1
    if command -v xdg-open >/dev/null 2>&1; then
        (xdg-open "$target" >/dev/null 2>&1 &) || true
    elif command -v gio >/dev/null 2>&1; then
        (gio open "$target" >/dev/null 2>&1 &) || true
    elif command -v open >/dev/null 2>&1; then
        (open "$target" >/dev/null 2>&1 &) || true
    else
        printf '%s\n' 'sizes: no opener found (tried xdg-open, gio, open)' >&2
        exit 1
    fi
}

quote_path() {
    printf "'%s'" "$(printf '%s' "$path" | sed "s/'/'\\\\''/g")"
}

copy_text() {
    text=$1
    if command -v wl-copy >/dev/null 2>&1; then
        printf '%s' "$text" | wl-copy
    elif command -v xclip >/dev/null 2>&1; then
        printf '%s' "$text" | xclip -selection clipboard
    elif command -v xsel >/dev/null 2>&1; then
        printf '%s' "$text" | xsel --clipboard --input
    elif command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$text" | pbcopy
    elif command -v clip.exe >/dev/null 2>&1; then
        printf '%s' "$text" | clip.exe
    else
        printf '%s\n' "$text"
        exit 2
    fi
}

case "$action" in
    parent)
        open_path "$(dirname -- "$path")"
        ;;
    copy)
        copy_text "$path"
        ;;
    copy-quoted)
        copy_text "$(quote_path)"
        ;;
    open-dir|dir)
        open_path "$path"
        ;;
    *)
        open_path "$path"
        ;;
esac
OPENSCRIPT
    chmod +x "$open_script"
}

make_interactive_file_list() {
    records_file=$1
    ext=$2
    out_file=$3

    target_type=
    case "$ext" in TYPE:*) target_type=${ext#TYPE:} ;; esac

    awk -F"$field_sep" -v target="$ext" -v target_type="$target_type" -v OFS="$field_sep" '
        function keep() {
            if (target == "TOTAL") return 1
            if (target_type != "") return $4 == target_type
            return toupper($3) == toupper(target)
        }
        keep() { print $1, $2, $3, $4 }
    ' "$records_file" \
    | LC_ALL=C sort -t "$field_sep" -k1,1nr \
    | awk -F"$field_sep" -v OFS="$field_sep" '
        function human(n,    u, units) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            u = 1
            while (n >= 1024 && u < 6) { n /= 1024; u++ }
            if (u == 1) return sprintf("%.0f %s", n, units[u])
            return sprintf("%.2f %s", n, units[u])
        }
        function middle(s, w,    keep, left, right) {
            if (length(s) <= w) return s
            keep = w - 3; left = int(keep * 0.42); right = keep - left
            return substr(s, 1, left) "..." substr(s, length(s) - right + 1)
        }
        {
            size_h = human($1)
            display = sprintf("%11s  %-8s  %s", size_h, $3, middle($2, 128))
            print $2, display, $3, $4, $1, size_h
        }
    ' >"$out_file"
}

make_interactive_dir_list() {
    records_file=$1
    ext=$2
    out_file=$3

    target_type=
    case "$ext" in TYPE:*) target_type=${ext#TYPE:} ;; esac

    awk -F"$field_sep" -v target="$ext" -v target_type="$target_type" -v OFS="$field_sep" '
        function dirname(path,    d) {
            d = path
            sub(/\/[^\/]*$/, "", d)
            if (d == "" || d == path) return "."
            return d
        }
        function keep() {
            if (target == "TOTAL") return 1
            if (target_type != "") return $4 == target_type
            return toupper($3) == toupper(target)
        }
        keep() {
            d = dirname($2)
            bytes[d] += $1
            files[d] += 1
            ext_for[d] = target
            type_for[d] = target_type != "" ? target_type : $4
        }
        END { for (d in bytes) print bytes[d], d, files[d], ext_for[d], type_for[d] }
    ' "$records_file" \
    | LC_ALL=C sort -t "$field_sep" -k1,1nr \
    | awk -F"$field_sep" -v OFS="$field_sep" '
        function human(n,    u, units) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            u = 1
            while (n >= 1024 && u < 6) { n /= 1024; u++ }
            if (u == 1) return sprintf("%.0f %s", n, units[u])
            return sprintf("%.2f %s", n, units[u])
        }
        function commas(n,    s, out) {
            s = sprintf("%d", n); out = ""
            while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) }
            return s out
        }
        function middle(s, w,    keep, left, right) {
            if (length(s) <= w) return s
            keep = w - 3; left = int(keep * 0.42); right = keep - left
            return substr(s, 1, left) "..." substr(s, length(s) - right + 1)
        }
        {
            size_h = human($1)
            display = sprintf("%11s  %8s  %s", size_h, commas($3), middle($2, 130))
            print $2, display, $4, $5, $1, size_h, $3
        }
    ' >"$out_file"
}

make_interactive_type_list() {
    records_file=$1
    out_file=$2

    awk -F"$field_sep" -v OFS="$field_sep" '
        { bytes[$4] += $1; files[$4] += 1; total += $1 }
        END { for (t in bytes) print bytes[t], t, files[t], total }
    ' "$records_file" \
    | LC_ALL=C sort -t "$field_sep" -k1,1nr \
    | awk -F"$field_sep" -v OFS="$field_sep" -v color="$color" '
        function human(n,    u, units) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            u = 1
            while (n >= 1024 && u < 6) { n /= 1024; u++ }
            if (u == 1) return sprintf("%.0f %s", n, units[u])
            return sprintf("%.2f %s", n, units[u])
        }
        function commas(n,    ss, out) {
            ss = sprintf("%d", n); out = ""
            while (length(ss) > 3) { out = "," substr(ss, length(ss) - 2) out; ss = substr(ss, 1, length(ss) - 3) }
            return ss out
        }
        function kind_color(k) {
            if (!color) return ""
            if (k == "video") return red
            if (k == "image") return magenta
            if (k == "audio") return blue
            if (k == "archive") return yellow
            if (k == "doc") return green
            if (k == "data" || k == "database" || k == "code") return cyan
            if (k == "model" || k == "game") return yellow
            if (k == "font") return magenta
            if (k == "3d" || k == "subs") return green
            if (k == "binary") return red
            if (k == "meta" || k == "none") return gray
            if (k == "mixed" || k == "all") return white
            return cyan
        }
        function heat_color(bytes, p) {
            if (!color) return ""
            if (bytes >= 10 * 1024 * 1024 * 1024 || p >= 20) return red
            if (bytes >= 1024 * 1024 * 1024 || p >= 5) return yellow
            if (bytes >= 100 * 1024 * 1024 || p >= 1) return green
            if (bytes > 0) return gray
            return gray
        }
        function row_display(t, bytes, files, total,    share, tc, sc, h, c) {
            share = total ? bytes * 100 / total : 0
            tc = kind_color(t)
            sc = heat_color(bytes, share)
            h = human(bytes)
            c = commas(files)
            return sprintf("%s%-12s%s  %s%11s%s  %8s  %7.2f%%", tc, t, reset, sc, h, reset, c, share)
        }
        BEGIN {
            if (color) {
                reset = "\033[0m"; red = "\033[31m"; green = "\033[32m"; yellow = "\033[33m"; blue = "\033[34m"; magenta = "\033[35m"; cyan = "\033[36m"; white = "\033[97m"; gray = "\033[90m"
            } else {
                reset = red = green = yellow = blue = magenta = cyan = white = gray = ""
            }
        }
        {
            share = $4 ? $1 * 100 / $4 : 0
            print "TYPE:" $2, row_display($2, $1, $3, $4), $2, $1, human($1), $3, sprintf("%.2f", share)
        }
    ' >"$out_file"
}

make_interactive_extension_type_list() {
    records_file=$1
    type_filter=$2
    out_file=$3

    awk -F"$field_sep" -v t="$type_filter" -v sort_by="$sort_by" -v OFS="$field_sep" '
        $4 == t {
            bytes[$3] += $1
            files[$3] += 1
            total += $1
            total_files += 1
        }
        END {
            for (e in bytes) {
                share = total ? bytes[e] * 100 / total : 0
                if (sort_by == "files") sortkey = files[e]
                else if (sort_by == "ext") sortkey = e
                else if (sort_by == "type") sortkey = t " " e
                else if (sort_by == "share") sortkey = share
                else sortkey = bytes[e]
                print sortkey, bytes[e], files[e], e, t, total, total_files
            }
        }
    ' "$records_file" \
    | sort_records \
    | awk -F"$field_sep" -v OFS="$field_sep" -v color="$color" -v limit="$limit" -v min_size="$min_size" -v min_share="$min_share" -v type_filter="$type_filter" '
        function human(n,    u, units) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            u = 1
            while (n >= 1024 && u < 6) { n /= 1024; u++ }
            if (u == 1) return sprintf("%.0f %s", n, units[u])
            return sprintf("%.2f %s", n, units[u])
        }
        function commas(n,    ss, out) {
            ss = sprintf("%d", n); out = ""
            while (length(ss) > 3) { out = "," substr(ss, length(ss) - 2) out; ss = substr(ss, 1, length(ss) - 3) }
            return ss out
        }
        function kind_color(k) {
            if (!color) return ""
            if (k == "video") return red
            if (k == "image") return magenta
            if (k == "audio") return blue
            if (k == "archive") return yellow
            if (k == "doc") return green
            if (k == "data" || k == "database" || k == "code") return cyan
            if (k == "model" || k == "game") return yellow
            if (k == "font") return magenta
            if (k == "3d" || k == "subs") return green
            if (k == "binary") return red
            if (k == "meta" || k == "none") return gray
            if (k == "mixed" || k == "all") return white
            return cyan
        }
        function heat_color(bytes, p) {
            if (!color) return ""
            if (bytes >= 10 * 1024 * 1024 * 1024 || p >= 20) return red
            if (bytes >= 1024 * 1024 * 1024 || p >= 5) return yellow
            if (bytes >= 100 * 1024 * 1024 || p >= 1) return green
            if (bytes > 0) return gray
            return gray
        }
        function row_display(name, k, bytes, files, total, is_total,    share, lc, sc, h, c) {
            share = total ? bytes * 100 / total : 0
            if (is_total && total > 0) share = 100
            lc = is_total ? white : kind_color(k)
            sc = is_total ? white : heat_color(bytes, share)
            h = human(bytes)
            c = commas(files)
            return sprintf("%s%-12s%s  %s%-10s%s  %s%11s%s  %8s  %7.2f%%", lc, name, reset, kind_color(k), k, reset, sc, h, reset, c, share)
        }
        BEGIN {
            limited = limit + 0 > 0
            if (color) {
                reset = "\033[0m"; red = "\033[31m"; green = "\033[32m"; yellow = "\033[33m"; blue = "\033[34m"; magenta = "\033[35m"; cyan = "\033[36m"; white = "\033[97m"; gray = "\033[90m"
            } else {
                reset = red = green = yellow = blue = magenta = cyan = white = gray = ""
            }
        }
        {
            seen = 1
            bytes = $2 + 0
            files = $3 + 0
            ext = $4
            k = $5
            total_bytes = $6 + 0
            total_count = $7 + 0
            share = total_bytes ? bytes * 100 / total_bytes : 0
            filtered = ((min_size + 0 > 0 && bytes < min_size) || (min_share + 0 >= 0 && share < min_share))
            if (!filtered && (!limited || shown < limit)) {
                print ext, row_display(ext, k, bytes, files, total_bytes, 0), k, bytes, human(bytes), files, sprintf("%.2f", share)
                shown++
            } else {
                other_bytes += bytes
                other_count += files
                other_types++
            }
        }
        END {
            if (other_types > 0) {
                share = total_bytes ? other_bytes * 100 / total_bytes : 0
                print "OTHER", row_display("OTHER", "mixed", other_bytes, other_count, total_bytes, 0), "mixed", other_bytes, human(other_bytes), other_count, sprintf("%.2f", share)
            }
            if (seen) print "TYPE:" type_filter, row_display("TOTAL", type_filter, total_bytes, total_count, total_bytes, 1), type_filter, total_bytes, human(total_bytes), total_count, "100.00"
        }
    ' >"$out_file"
}

interactive_shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

interactive_open_with() {
    path=$1
    opener=${SIZES_OPEN_WITH:-}
    if [ "$opener" = "" ] && [ -r /dev/tty ]; then
        printf '%s' 'sizes: open with command: ' >/dev/tty
        IFS= read -r opener </dev/tty || opener=
    fi
    [ "$opener" != "" ] || return 2
    if command -v "$opener" >/dev/null 2>&1; then
        ("$opener" "$path" >/dev/null 2>&1 &) || true
        return 0
    fi
    printf '%s\n' "sizes: opener not found: $opener" >&2
    return 1
}

print_selected_file() {
    selected_file=$1
    printf '%s\n' "$selected_file" | awk -F"$field_sep" '
        {
            print "sizes — selected file"
            print ""
            print "File"
            print "────"
            printf "Path: %s\n", $1
            printf "Size: %s\n", $6
            printf "Ext:  %s\n", $3
            printf "Type: %s\n", $4
        }'
}

print_selected_dir() {
    selected_dir=$1
    printf '%s\n' "$selected_dir" | awk -F"$field_sep" '
        {
            print "sizes — selected directory"
            print ""
            print "Directory"
            print "─────────"
            printf "Path:  %s\n", $1
            printf "Size:  %s\n", $6
            printf "Files: %d\n", $7
            printf "Ext:   %s\n", $3
            printf "Type:  %s\n", $4
        }'
}

interactive_preview_window() {
    if [ "$interactive_preview" -eq 0 ]; then
        printf '%s\n' 'hidden'
        return 0
    fi

    cols=$(tput cols 2>/dev/null || printf '120')
    case "$cols" in ''|*[!0-9]*) cols=120 ;; esac
    if [ "$cols" -lt 100 ]; then
        printf '%s\n' 'down:45%:wrap'
    elif [ "$cols" -lt 140 ]; then
        printf '%s\n' 'right:45%:wrap'
    else
        printf '%s\n' 'right:55%:wrap'
    fi
}

interactive_quit_requested() {
    [ "${interactive_quit_file:-}" != "" ] && [ -f "$interactive_quit_file" ]
}

interactive_common_bindings() {
    printf '%s' "ctrl-b:abort,ctrl-q:execute-silent(touch $interactive_quit_file)+abort,alt-j:preview-down,alt-k:preview-up,alt-d:preview-page-down,alt-u:preview-page-up,alt-t:preview-top,alt-b:preview-bottom,ctrl-/:toggle-preview"
}

interactive_screen_header() {
    title=$1
    hint=$2
    columns=${3:-}
    if [ "$columns" != "" ]; then
        printf '%s
%s
%s' "$title" "$hint" "$columns"
    else
        printf '%s
%s' "$title" "$hint"
    fi
}

run_interactive_notice() {
    fzf_cmd=$1
    title=$2
    message=$3

    notice_file=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-notice.XXXXXX") || exit 1
    printf '%s
' "$message" >"$notice_file"
    "$fzf_cmd"         --ansi         --no-sort         --header="$title"         --prompt='back> '         --layout=reverse         --info=inline-right         --bind="ctrl-b:abort,ctrl-q:execute-silent(touch $interactive_quit_file)+abort"         --height='50%'         --border         <"$notice_file" >/dev/null 2>&1 || true
    rm -f "$notice_file"
}

run_interactive_empty_state() {
    fzf_cmd=$1
    title=$2
    message=$3

    empty_file=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-empty.XXXXXX") || exit 1
    printf '%s\n' "$message" >"$empty_file"
    "$fzf_cmd" \
        --ansi \
        --no-sort \
        --header="$title" \
        --prompt='back> ' \
        --layout=reverse \
        --info=inline-right \
        --bind="ctrl-b:abort,ctrl-q:execute-silent(touch $interactive_quit_file)+abort" \
        --height='50%' \
        --border \
        <"$empty_file" >/dev/null 2>&1 || true
    rm -f "$empty_file"
}


interactive_allow_delete() {
    [ "$allow_delete" -eq 1 ] || [ "${SIZES_ALLOW_DELETE:-0}" = "1" ]
}

interactive_trash_path() {
    target=$1

    if [ "${SIZES_TRASH_CMD:-}" != "" ]; then
        "$SIZES_TRASH_CMD" "$target"
        return $?
    fi

    if command -v gio >/dev/null 2>&1; then
        gio trash "$target"
    elif command -v trash-put >/dev/null 2>&1; then
        trash-put "$target"
    elif command -v kioclient5 >/dev/null 2>&1; then
        kioclient5 move "$target" trash:/
    elif command -v kioclient >/dev/null 2>&1; then
        kioclient move "$target" trash:/
    elif command -v gvfs-trash >/dev/null 2>&1; then
        gvfs-trash "$target"
    else
        return 127
    fi
}

interactive_confirm_permanent_delete() {
    kind=$1
    target=$2
    phrase=$3

    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        return 2
    fi

    {
        printf '\n%s\n' 'sizes: permanent delete requested'
        printf '%s\n' 'This cannot be undone.'
        printf '%s: %s\n' "$kind" "$target"
        printf 'Type %s to continue: ' "$phrase"
    } >/dev/tty

    IFS= read -r answer </dev/tty || return 1
    [ "$answer" = "$phrase" ]
}

interactive_permanent_delete_path() {
    kind=$1
    target=$2

    interactive_allow_delete || return 3

    case "$kind" in
        dir) phrase='DELETE DIR' ;;
        *) phrase='DELETE' ;;
    esac

    interactive_confirm_permanent_delete "$kind" "$target" "$phrase" || return $?

    case "$kind" in
        dir) rm -rf -- "$target" ;;
        *) rm -f -- "$target" ;;
    esac
}

run_file_action_menu() {
    fzf_cmd=$1
    selected_file=$2
    open_script=$3

    path=$(printf '%s\n' "$selected_file" | awk -F"$field_sep" '{print $1}')
    ext=$(printf '%s\n' "$selected_file" | awk -F"$field_sep" '{print $3}')
    kind=$(printf '%s\n' "$selected_file" | awk -F"$field_sep" '{print $4}')
    size_h=$(printf '%s\n' "$selected_file" | awk -F"$field_sep" '{print $6}')
    short_path=$(printf '%s\n' "$path" | awk '
        function middle(s, w,    keep, left, right) {
            if (length(s) <= w) return s
            keep = w - 3
            left = int(keep * 0.38)
            right = keep - left
            return substr(s, 1, left) "..." substr(s, length(s) - right + 1)
        }
        { print middle($0, 86) }
    ')

    action_file=$(mktemp "${TMPDIR:-/tmp}/sizes-file-actions.XXXXXX") || exit 1
    item_file=$(mktemp "${TMPDIR:-/tmp}/sizes-file-action-item.XXXXXX") || exit 1

    cat >"$action_file" <<EOF
open${field_sep}Open file
folder${field_sep}Open containing folder
open-with${field_sep}Open with…
copy${field_sep}Copy path
copy-quoted${field_sep}Copy quoted path
path${field_sep}Show full path
quoted-path${field_sep}Print quoted path
details${field_sep}Print details
trash${field_sep}Trash file
delete${field_sep}Delete permanently
back${field_sep}Back
quit${field_sep}Quit
EOF

    {
        printf '%s\n' 'Selected file'
        printf '%s\n\n' '─────────────'
        printf '%s\n' 'Path'
        printf '  %s\n\n' "$path"
        printf '%-10s %s\n' 'Size' "${size_h:-'-'}"
        printf '%-10s %s\n' 'Ext' "${ext:-'-'}"
        printf '%-10s %s\n\n' 'Type' "${kind:-'-'}"
        printf '%s\n' 'Actions'
        printf '%s\n' '───────'
        printf '%-10s %s\n' 'Enter' 'run selected action'
        printf '%-10s %s\n' 'Ctrl-O' 'open file'
        printf '%-10s %s\n' 'Ctrl-P' 'open containing folder'
        printf '%-10s %s\n' 'Ctrl-Y' 'copy path'
        printf '%-10s %s\n' 'Ctrl-L' 'reveal full path'
        printf '%-10s %s\n' 'Open with' 'uses SIZES_OPEN_WITH or prompts'
        printf '%-10s %s\n' 'Trash' 'moves to system trash; never falls back to rm'
        printf '%-10s %s\n' 'Delete' 'requires --allow-delete and typed confirmation'
        printf '%-10s %s\n' 'Back/Quit' 'return or exit interactive mode'
    } >"$item_file"

    preview_window=$(interactive_preview_window)
    header=$(interactive_screen_header 'sizes › file › action' "Selected: $short_path" 'ACTION')
    choice=$("$fzf_cmd" \
        --ansi \
        --no-sort \
        --expect=enter,ctrl-o,ctrl-p,ctrl-y,ctrl-l \
        --delimiter="$field_sep" \
        --with-nth=2 \
        --header="$header" \
        --prompt='sizes › file › action> ' \
        --layout=reverse \
        --info=inline-right \
        --height='70%' \
        --border \
        --preview="cat \"$item_file\"" \
        --preview-window="$preview_window" \
        --bind="ctrl-b:abort,ctrl-q:execute-silent(touch $interactive_quit_file)+abort,ctrl-/:toggle-preview" \
        <"$action_file" || true)
    rm -f "$action_file" "$item_file"

    interactive_quit_requested && return 0

    parsed=$(interactive_select_parts "$choice")
    key=$(printf '%s\n' "$parsed" | sed -n '1p')
    selected_action=$(printf '%s\n' "$parsed" | sed -n '2p')
    action=$(printf '%s\n' "$selected_action" | awk -F"$field_sep" '{print $1}')

    case "$key" in
        ctrl-o) action=open ;;
        ctrl-p) action=folder ;;
        ctrl-y) action=copy ;;
        ctrl-l) action=full-path ;;
    esac

    case "$action" in
        open)
            if "$open_script" "$path" open; then
                run_interactive_notice "$fzf_cmd" 'sizes › opened file' "Opened file:
$path"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › open failed' "Could not open file:
$path"
            fi
            ;;
        folder)
            if "$open_script" "$path" parent; then
                parent=$(dirname -- "$path")
                run_interactive_notice "$fzf_cmd" 'sizes › opened folder' "Opened containing folder:
$parent"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › open failed' "Could not open containing folder for:
$path"
            fi
            ;;
        open-with)
            if interactive_open_with "$path"; then
                run_interactive_notice "$fzf_cmd" 'sizes › opened with command' "Opened with ${SIZES_OPEN_WITH:-selected command}:
$path"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › open with failed' "Could not open with another command:
$path"
            fi
            ;;
        copy)
            if "$open_script" "$path" copy; then
                run_interactive_notice "$fzf_cmd" 'sizes › copied path' "Copied path:
$path"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › copy unavailable' "No clipboard tool found. Path:
$path"
            fi
            ;;
        copy-quoted)
            if "$open_script" "$path" copy-quoted; then
                run_interactive_notice "$fzf_cmd" 'sizes › copied quoted path' "Copied quoted path:
$(interactive_shell_quote "$path")"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › copy unavailable' "No clipboard tool found. Quoted path:
$(interactive_shell_quote "$path")"
            fi
            ;;
        trash)
            if interactive_trash_path "$path"; then
                run_interactive_notice "$fzf_cmd" 'sizes › trashed file' "Moved file to trash:
$path"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › trash unavailable' "Could not move file to trash. Install gio/trash-cli/KDE trash support or set SIZES_TRASH_CMD.

Path:
$path"
            fi
            ;;
        delete)
            if interactive_permanent_delete_path file "$path"; then
                run_interactive_notice "$fzf_cmd" 'sizes › deleted file' "Deleted file permanently:
$path"
            else
                status=$?
                case "$status" in
                    3) run_interactive_notice "$fzf_cmd" 'sizes › delete disabled' "Permanent delete is disabled.

Run with --allow-delete or set SIZES_ALLOW_DELETE=1 to enable it." ;;
                    2) run_interactive_notice "$fzf_cmd" 'sizes › cannot confirm delete' "Permanent delete needs a controlling terminal for typed confirmation." ;;
                    *) run_interactive_notice "$fzf_cmd" 'sizes › delete cancelled' "Permanent delete cancelled or failed:
$path" ;;
                esac
            fi
            ;;
        path|full-path) run_interactive_notice "$fzf_cmd" 'sizes › full path' "$path" ;;
        quoted-path) printf '%s\n' "$(interactive_shell_quote "$path")" ;;
        details) print_selected_file "$selected_file" ;;
        quit) : >"$interactive_quit_file" ;;
        back|'') : ;;
        *) : ;;
    esac
}

run_dir_action_menu() {
    fzf_cmd=$1
    selected_dir=$2
    open_script=$3
    records_file=$4
    item_preview_script=$5

    path=$(printf '%s\n' "$selected_dir" | awk -F"$field_sep" '{print $1}')
    ext=$(printf '%s\n' "$selected_dir" | awk -F"$field_sep" '{print $3}')
    kind=$(printf '%s\n' "$selected_dir" | awk -F"$field_sep" '{print $4}')
    size_h=$(printf '%s\n' "$selected_dir" | awk -F"$field_sep" '{print $6}')
    files=$(printf '%s\n' "$selected_dir" | awk -F"$field_sep" '{print $7}')
    short_path=$(printf '%s\n' "$path" | awk '
        function middle(s, w,    keep, left, right) {
            if (length(s) <= w) return s
            keep = w - 3
            left = int(keep * 0.38)
            right = keep - left
            return substr(s, 1, left) "..." substr(s, length(s) - right + 1)
        }
        { print middle($0, 86) }
    ')

    action_file=$(mktemp "${TMPDIR:-/tmp}/sizes-dir-actions.XXXXXX") || exit 1
    item_file=$(mktemp "${TMPDIR:-/tmp}/sizes-dir-action-item.XXXXXX") || exit 1

    cat >"$action_file" <<EOF
open${field_sep}Open directory
browse${field_sep}Browse files in directory
open-with${field_sep}Open with…
copy${field_sep}Copy path
copy-quoted${field_sep}Copy quoted path
path${field_sep}Show full path
quoted-path${field_sep}Print quoted path
details${field_sep}Print details
trash${field_sep}Trash directory
delete${field_sep}Delete permanently
back${field_sep}Back
quit${field_sep}Quit
EOF

    {
        printf '%s\n' 'Selected directory'
        printf '%s\n\n' '──────────────────'
        printf '%s\n' 'Path'
        printf '  %s\n\n' "$path"
        printf '%-10s %s\n' 'Size' "${size_h:-'-'}"
        printf '%-10s %s\n' 'Files' "${files:-'-'}"
        printf '%-10s %s\n' 'Ext' "${ext:-'-'}"
        printf '%-10s %s\n\n' 'Type' "${kind:-'-'}"
        printf '%s\n' 'Actions'
        printf '%s\n' '───────'
        printf '%-10s %s\n' 'Enter' 'run selected action'
        printf '%-10s %s\n' 'Ctrl-O' 'open directory'
        printf '%-10s %s\n' 'Ctrl-Y' 'copy path'
        printf '%-10s %s\n' 'Ctrl-L' 'reveal full path'
        printf '%-10s %s\n' 'Open with' 'uses SIZES_OPEN_WITH or prompts'
        printf '%-10s %s\n' 'Trash' 'moves to system trash; never falls back to rm'
        printf '%-10s %s\n' 'Delete' 'requires --allow-delete and typed confirmation'
        printf '%-10s %s\n' 'Back/Quit' 'return or exit interactive mode'
    } >"$item_file"

    preview_window=$(interactive_preview_window)
    header=$(interactive_screen_header 'sizes › dir › action' "Selected: $short_path" 'ACTION')
    choice=$("$fzf_cmd" \
        --ansi \
        --no-sort \
        --expect=enter,ctrl-o,ctrl-y,ctrl-l \
        --delimiter="$field_sep" \
        --with-nth=2 \
        --header="$header" \
        --prompt='sizes › dir › action> ' \
        --layout=reverse \
        --info=inline-right \
        --height='70%' \
        --border \
        --preview="cat \"$item_file\"" \
        --preview-window="$preview_window" \
        --bind="ctrl-b:abort,ctrl-q:execute-silent(touch $interactive_quit_file)+abort,ctrl-/:toggle-preview" \
        <"$action_file" || true)
    rm -f "$action_file" "$item_file"

    interactive_quit_requested && return 0

    parsed=$(interactive_select_parts "$choice")
    key=$(printf '%s\n' "$parsed" | sed -n '1p')
    selected_action=$(printf '%s\n' "$parsed" | sed -n '2p')
    action=$(printf '%s\n' "$selected_action" | awk -F"$field_sep" '{print $1}')

    case "$key" in
        ctrl-o) action=open ;;
        ctrl-y) action=copy ;;
        ctrl-l) action=full-path ;;
    esac

    case "$action" in
        open)
            if "$open_script" "$path" open-dir; then
                run_interactive_notice "$fzf_cmd" 'sizes › opened directory' "Opened directory:
$path"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › open failed' "Could not open directory:
$path"
            fi
            ;;
        browse)
            tmp_records=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-dir-records.XXXXXX") || exit 1
            awk -F"$field_sep" -v p="$path" '($2 == p || index($2, p "/") == 1) { print }' "$records_file" >"$tmp_records"
            run_interactive_file_browser "$fzf_cmd" "$tmp_records" TOTAL "$item_preview_script" "$open_script"
            rm -f "$tmp_records"
            ;;
        open-with)
            if interactive_open_with "$path"; then
                run_interactive_notice "$fzf_cmd" 'sizes › opened with command' "Opened with ${SIZES_OPEN_WITH:-selected command}:
$path"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › open with failed' "Could not open with another command:
$path"
            fi
            ;;
        copy)
            if "$open_script" "$path" copy; then
                run_interactive_notice "$fzf_cmd" 'sizes › copied path' "Copied path:
$path"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › copy unavailable' "No clipboard tool found. Path:
$path"
            fi
            ;;
        copy-quoted)
            if "$open_script" "$path" copy-quoted; then
                run_interactive_notice "$fzf_cmd" 'sizes › copied quoted path' "Copied quoted path:
$(interactive_shell_quote "$path")"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › copy unavailable' "No clipboard tool found. Quoted path:
$(interactive_shell_quote "$path")"
            fi
            ;;
        trash)
            if interactive_trash_path "$path"; then
                run_interactive_notice "$fzf_cmd" 'sizes › trashed directory' "Moved directory to trash:
$path"
            else
                run_interactive_notice "$fzf_cmd" 'sizes › trash unavailable' "Could not move directory to trash. Install gio/trash-cli/KDE trash support or set SIZES_TRASH_CMD.

Path:
$path"
            fi
            ;;
        delete)
            if interactive_permanent_delete_path dir "$path"; then
                run_interactive_notice "$fzf_cmd" 'sizes › deleted directory' "Deleted directory permanently:
$path"
            else
                status=$?
                case "$status" in
                    3) run_interactive_notice "$fzf_cmd" 'sizes › delete disabled' "Permanent delete is disabled.

Run with --allow-delete or set SIZES_ALLOW_DELETE=1 to enable it." ;;
                    2) run_interactive_notice "$fzf_cmd" 'sizes › cannot confirm delete' "Permanent delete needs a controlling terminal for typed confirmation." ;;
                    *) run_interactive_notice "$fzf_cmd" 'sizes › delete cancelled' "Permanent delete cancelled or failed:
$path" ;;
                esac
            fi
            ;;
        path|full-path) run_interactive_notice "$fzf_cmd" 'sizes › full path' "$path" ;;
        quoted-path) printf '%s\n' "$(interactive_shell_quote "$path")" ;;
        details) print_selected_dir "$selected_dir" ;;
        quit) : >"$interactive_quit_file" ;;
        back|'') : ;;
        *) : ;;
    esac
}

run_interactive_file_browser() {
    fzf_cmd=$1
    records_file=$2
    ext=$3
    item_preview_script=$4
    open_script=$5

    if [ "$ext" = "OTHER" ]; then
        run_interactive_empty_state "$fzf_cmd" 'sizes › files' 'OTHER is a folded summary row. Increase --limit or remove filters to inspect files.'
        return 0
    fi

    label=$ext
    case "$ext" in TYPE:*) label=${ext#TYPE:} ;; esac
    query=
    cursor_pos=1

    while ! interactive_quit_requested; do
        file_list=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-files.XXXXXX") || exit 1
        make_interactive_file_list "$records_file" "$ext" "$file_list"

        if [ ! -s "$file_list" ]; then
            rm -f "$file_list"
            run_interactive_empty_state "$fzf_cmd" "sizes › files › $label" "No matching files for $label. Esc/Ctrl-B: back · Ctrl-Q: quit."
            return 0
        fi

        preview_window=$(interactive_preview_window)
        title=$(interactive_screen_header "sizes › files › $label" 'Context: selected row preview shows full details · Enter actions · Ctrl-L full path · Ctrl-/ preview · Esc back · Ctrl-Q quit' 'SIZE         EXT       PATH')
        common_bindings=$(interactive_common_bindings)
        fzf_out=$("$fzf_cmd" \
            --ansi \
            --no-sort \
            --multi \
            --cycle \
            --expect=enter,ctrl-o,ctrl-p,ctrl-y,ctrl-l \
            --delimiter="$field_sep" \
            --with-nth=2 \
            --header="$title" \
            --prompt="sizes › files › $label> " \
            --query="$query" \
            --layout=reverse \
            --info=inline-right \
            --preview="$item_preview_script file {1} {6} {4} {3}" \
            --bind="load:pos($cursor_pos),ctrl-o:execute-silent($open_script {1} open),ctrl-p:execute-silent($open_script {1} parent),ctrl-y:execute-silent($open_script {1} copy),$common_bindings" \
            --preview-window="$preview_window" \
            --height='95%' \
            --border \
            <"$file_list" || true)

        interactive_quit_requested && { rm -f "$file_list"; return 0; }
        [ "$fzf_out" = "" ] && { rm -f "$file_list"; return 0; }

        parsed=$(interactive_select_parts "$fzf_out")
        key=$(printf '%s\n' "$parsed" | sed -n '1p')
        selected=$(printf '%s\n' "$parsed" | sed -n '2,$p' | sed '/^$/d')
        first_selected=$(printf '%s\n' "$selected" | sed -n '1p')
        first_path=$(printf '%s\n' "$first_selected" | awk -F"$field_sep" '{ print $1 }')
        if [ "$first_selected" != "" ]; then
            cursor_pos=$(awk -v s="$first_selected" '$0 == s { print NR; found = 1; exit } END { if (!found) print 1 }' "$file_list")
        fi
        rm -f "$file_list"
        # Preserve cursor position, not query text. This keeps the selected file
        # highlighted after returning from an action without hiding other rows.

        case "$key" in
            ctrl-o) [ "$first_path" != "" ] && "$open_script" "$first_path" open ;;
            ctrl-p) [ "$first_path" != "" ] && "$open_script" "$first_path" parent ;;
            ctrl-y) [ "$first_path" != "" ] && "$open_script" "$first_path" copy ;;
            ctrl-l) [ "$first_path" != "" ] && run_interactive_notice "$fzf_cmd" 'sizes › full path' "$first_path" ;;
            *)
                if [ "$(printf '%s\n' "$selected" | sed '/^$/d' | wc -l | tr -d ' ')" -gt 1 ]; then
                    printf '%s\n' "$selected" | awk -F"$field_sep" '{print $1}'
                elif [ "$first_selected" != "" ]; then
                    run_file_action_menu "$fzf_cmd" "$first_selected" "$open_script"
                fi
                ;;
        esac
    done
}

run_interactive_dir_browser() {
    fzf_cmd=$1
    records_file=$2
    ext=$3
    item_preview_script=$4
    open_script=$5

    if [ "$ext" = "OTHER" ]; then
        run_interactive_empty_state "$fzf_cmd" 'sizes › dirs' 'OTHER is a folded summary row. Increase --limit or remove filters to inspect directories.'
        return 0
    fi

    label=$ext
    case "$ext" in TYPE:*) label=${ext#TYPE:} ;; esac
    query=
    cursor_pos=1

    while ! interactive_quit_requested; do
        dir_list=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-dirs.XXXXXX") || exit 1
        make_interactive_dir_list "$records_file" "$ext" "$dir_list"

        if [ ! -s "$dir_list" ]; then
            rm -f "$dir_list"
            run_interactive_empty_state "$fzf_cmd" "sizes › dirs › $label" "No matching directories for $label. Esc/Ctrl-B: back · Ctrl-Q: quit."
            return 0
        fi

        preview_window=$(interactive_preview_window)
        title=$(interactive_screen_header "sizes › dirs › $label" 'Context: selected row preview shows full details · Enter actions · Ctrl-L full path · Ctrl-/ preview · Esc back · Ctrl-Q quit' 'SIZE         FILES     PATH')
        common_bindings=$(interactive_common_bindings)
        fzf_out=$("$fzf_cmd" \
            --ansi \
            --no-sort \
            --cycle \
            --expect=enter,ctrl-o,ctrl-y,ctrl-l \
            --delimiter="$field_sep" \
            --with-nth=2 \
            --header="$title" \
            --prompt="sizes › dirs › $label> " \
            --query="$query" \
            --layout=reverse \
            --info=inline-right \
            --preview="$item_preview_script dir {1} {6} {4} {3} {7}" \
            --bind="load:pos($cursor_pos),ctrl-o:execute-silent($open_script {1} open-dir),ctrl-y:execute-silent($open_script {1} copy),$common_bindings" \
            --preview-window="$preview_window" \
            --height='95%' \
            --border \
            <"$dir_list" || true)

        interactive_quit_requested && { rm -f "$dir_list"; return 0; }
        [ "$fzf_out" = "" ] && { rm -f "$dir_list"; return 0; }

        parsed=$(interactive_select_parts "$fzf_out")
        key=$(printf '%s\n' "$parsed" | sed -n '1p')
        selected=$(printf '%s\n' "$parsed" | sed -n '2p')
        path=$(printf '%s\n' "$selected" | awk -F"$field_sep" '{ print $1 }')
        if [ "$selected" != "" ]; then
            cursor_pos=$(awk -v s="$selected" '$0 == s { print NR; found = 1; exit } END { if (!found) print 1 }' "$dir_list")
        fi
        rm -f "$dir_list"
        # Preserve cursor position, not query text. This keeps the selected dir
        # highlighted after returning from an action without hiding other rows.
        case "$key" in
            ctrl-o) [ "$path" != "" ] && "$open_script" "$path" open-dir ;;
            ctrl-y) [ "$path" != "" ] && "$open_script" "$path" copy ;;
            ctrl-l) [ "$path" != "" ] && run_interactive_notice "$fzf_cmd" 'sizes › full path' "$path" ;;
            *) [ "$selected" != "" ] && run_dir_action_menu "$fzf_cmd" "$selected" "$open_script" "$records_file" "$item_preview_script" ;;
        esac
    done
}

run_interactive_extension_browser() {
    fzf_cmd=$1
    summary_file=$2
    records_file=$3
    preview_script=$4
    item_preview_script=$5
    open_script=$6
    type_filter=${7:-}

    query=

    while ! interactive_quit_requested; do
        ext_input=$summary_file
        tmp_filtered=
        if [ "$type_filter" != "" ]; then
            tmp_filtered=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-ext.XXXXXX") || exit 1
            make_interactive_extension_type_list "$records_file" "$type_filter" "$tmp_filtered"
            ext_input=$tmp_filtered
        fi

        preview_window=$(interactive_preview_window)
        if [ "$type_filter" = "" ]; then
            title=$(interactive_screen_header 'sizes › extensions' 'Enter/Ctrl-F files · Ctrl-D dirs · ? help · Esc back · Ctrl-Q quit' 'EXT           TYPE          SIZE       FILES      SHARE')
            prompt='sizes › extensions> '
        else
            title=$(interactive_screen_header "sizes › types › $type_filter › extensions" 'Enter/Ctrl-F files · Ctrl-D dirs · ? help · Esc back · Ctrl-Q quit' 'EXT           TYPE          SIZE       FILES      SHARE')
            prompt=$(printf 'sizes › types › %s › extensions> ' "$type_filter")
        fi

        common_bindings=$(interactive_common_bindings)
        fzf_out=$("$fzf_cmd" \
            --ansi \
            --no-sort \
            --cycle \
            --expect=enter,ctrl-f,ctrl-d \
            --delimiter="$field_sep" \
            --with-nth=2 \
            --header="$title" \
            --prompt="$prompt" \
            --query="$query" \
            --layout=reverse \
            --info=inline-right \
            --preview="$preview_script '$records_file' {1} summary" \
            --bind="?:change-preview($preview_script '$records_file' HELP ext-help),$common_bindings" \
            --preview-window="$preview_window" \
            --height='95%' \
            --border \
            <"$ext_input" || true)

        [ "$tmp_filtered" != "" ] && rm -f "$tmp_filtered"
        interactive_quit_requested && return 0
        [ "$fzf_out" = "" ] && return 0

        parsed=$(interactive_select_parts "$fzf_out")
        key=$(printf '%s\n' "$parsed" | sed -n '1p')
        selected=$(printf '%s\n' "$parsed" | sed -n '2p')
        if [ "$selected" != "" ]; then
            selected_ext=$(printf '%s\n' "$selected" | awk -F"$field_sep" '{ print $1 }')
            query=$selected_ext
            case "$key" in
                ctrl-d) run_interactive_dir_browser "$fzf_cmd" "$records_file" "$selected_ext" "$item_preview_script" "$open_script" ;;
                *) run_interactive_file_browser "$fzf_cmd" "$records_file" "$selected_ext" "$item_preview_script" "$open_script" ;;
            esac
        fi
    done
}

run_interactive_type_browser() {
    fzf_cmd=$1
    summary_file=$2
    records_file=$3
    preview_script=$4
    item_preview_script=$5
    open_script=$6

    query=

    while ! interactive_quit_requested; do
        type_list=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-types.XXXXXX") || exit 1
        make_interactive_type_list "$records_file" "$type_list"

        if [ ! -s "$type_list" ]; then
            rm -f "$type_list"
            run_interactive_empty_state "$fzf_cmd" 'sizes › types' 'No matching types. Esc/Ctrl-B: back · Ctrl-Q: quit.'
            return 0
        fi

        preview_window=$(interactive_preview_window)
        common_bindings=$(interactive_common_bindings)
        fzf_out=$("$fzf_cmd" \
            --ansi \
            --no-sort \
            --cycle \
            --expect=enter,ctrl-f,ctrl-d \
            --delimiter="$field_sep" \
            --with-nth=2 \
            --header="$(interactive_screen_header 'sizes › types' 'Enter extensions · Ctrl-F files · Ctrl-D dirs · ? help · Esc back · Ctrl-Q quit' 'TYPE             SIZE      FILES     SHARE')" \
            --prompt='sizes › types> ' \
            --query="$query" \
            --layout=reverse \
            --info=inline-right \
            --preview="$preview_script '$records_file' {1} summary" \
            --bind="?:change-preview($preview_script '$records_file' HELP type-help),$common_bindings" \
            --preview-window="$preview_window" \
            --height='95%' \
            --border \
            <"$type_list" || true)

        rm -f "$type_list"
        interactive_quit_requested && return 0
        [ "$fzf_out" = "" ] && return 0

        parsed=$(interactive_select_parts "$fzf_out")
        key=$(printf '%s\n' "$parsed" | sed -n '1p')
        selected=$(printf '%s\n' "$parsed" | sed -n '2p')
        selected_type=$(printf '%s\n' "$selected" | awk -F"$field_sep" '{ print $3 }')
        [ "$selected_type" = "" ] && continue
        query=$selected_type
        target="TYPE:$selected_type"
        case "$key" in
            ctrl-f) run_interactive_file_browser "$fzf_cmd" "$records_file" "$target" "$item_preview_script" "$open_script" ;;
            ctrl-d) run_interactive_dir_browser "$fzf_cmd" "$records_file" "$target" "$item_preview_script" "$open_script" ;;
            *) run_interactive_extension_browser "$fzf_cmd" "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script" "$selected_type" ;;
        esac
    done
}

run_interactive_start_menu() {
    fzf_cmd=$1
    summary_file=$2
    records_file=$3
    preview_script=$4
    item_preview_script=$5
    open_script=$6

    query=

    while ! interactive_quit_requested; do
        menu_file=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-menu.XXXXXX") || exit 1
        cat >"$menu_file" <<EOF
extensions${field_sep}Extensions       Browse extension totals and drill into files/directories
types${field_sep}Types            Browse categories like image, video, archive, model
top-files${field_sep}Top files        Browse largest files in this scan
top-dirs${field_sep}Top directories  Browse largest directories in this scan
by-dir${field_sep}By directory     Browse directory summaries
refresh${field_sep}Refresh scan     Rescan current path with the same options
help${field_sep}Help             Show contextual shortcuts
quit${field_sep}Quit             Exit interactive mode
EOF

        preview_window=$(interactive_preview_window)
        fzf_out=$("$fzf_cmd" \
            --ansi \
            --no-sort \
            --cycle \
            --expect=enter,ctrl-r \
            --delimiter="$field_sep" \
            --with-nth=2 \
            --header="$(interactive_screen_header 'sizes › main' 'Enter open · Ctrl-R refresh · Esc quit · Ctrl-Q quit' 'MODE             DESCRIPTION')" \
            --prompt='sizes › main> ' \
            --query="$query" \
            --layout=reverse \
            --info=inline-right \
            --preview="$preview_script '$records_file' HELP main-help" \
            --preview-window="$preview_window" \
            --height='95%' \
            --border \
            --bind="ctrl-q:execute-silent(touch $interactive_quit_file)+abort" \
            <"$menu_file" || true)

        rm -f "$menu_file"
        interactive_quit_requested && return 0
        [ "$fzf_out" = "" ] && return 0

        parsed=$(interactive_select_parts "$fzf_out")
        key=$(printf '%s\n' "$parsed" | sed -n '1p')
        selected=$(printf '%s\n' "$parsed" | sed -n '2p')
        action=$(printf '%s\n' "$selected" | awk -F"$field_sep" '{ print $1 }')
        [ "$key" = "ctrl-r" ] && action=refresh
        [ "$action" != "" ] && query=$action

        case "$action" in
            refresh)
                : >"$summary_file"
                : >"$records_file"
                if ! run_interactive_scan "$summary_file" "$records_file"; then
                    return 1
                fi
                print_interactive_scan_summary "$records_file"
                ;;
            types) run_interactive_type_browser "$fzf_cmd" "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script" ;;
            top-files) run_interactive_file_browser "$fzf_cmd" "$records_file" TOTAL "$item_preview_script" "$open_script" ;;
            top-dirs|by-dir) run_interactive_dir_browser "$fzf_cmd" "$records_file" TOTAL "$item_preview_script" "$open_script" ;;
            help) "$preview_script" "$records_file" HELP main-help ;;
            quit) return 0 ;;
            extensions|'') run_interactive_extension_browser "$fzf_cmd" "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script" "" ;;
            *) : ;;
        esac
    done
}

print_interactive_scan_summary() {
    records_file=$1
    awk -F"$field_sep" '
        function human(n,    u, units) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            u = 1
            while (n >= 1024 && u < 6) { n /= 1024; u++ }
            if (u == 1) return sprintf("%.0f %s", n, units[u])
            return sprintf("%.2f %s", n, units[u])
        }
        { bytes += $1; files += 1 }
        END { printf "sizes: scanned %d files · %s · interactive ready\n", files, human(bytes) }
    ' "$records_file" >&2
}

run_interactive() {
    fzf_cmd=${SIZES_FZF:-fzf}
    if ! command -v "$fzf_cmd" >/dev/null 2>&1; then
        printf '%s\n' 'sizes: --interactive requires fzf. Install fzf or set SIZES_FZF=/path/to/fzf.' >&2
        exit 1
    fi

    summary_file=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-summary.XXXXXX") || exit 1
    records_file=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-records.XXXXXX") || exit 1
    preview_script=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-preview.XXXXXX") || exit 1
    item_preview_script=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-item-preview.XXXXXX") || exit 1
    open_script=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-open.XXXXXX") || exit 1
    interactive_quit_file=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-quit.XXXXXX") || exit 1
    rm -f "$interactive_quit_file"

    write_interactive_preview_script "$preview_script"
    write_interactive_item_preview_script "$item_preview_script"
    write_interactive_open_script "$open_script"

    if ! run_interactive_scan "$summary_file" "$records_file"; then
        rm -f "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script" "$interactive_quit_file"
        exit 1
    fi

    if [ ! -s "$summary_file" ]; then
        printf '%s\n' 'sizes: no files found'
        print_errors
        rm -f "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script" "$interactive_quit_file"
        return 0
    fi

    print_interactive_scan_summary "$records_file"
    run_interactive_start_menu "$fzf_cmd" "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script"
    printf '%s\n' 'sizes: interactive session closed' >&2

    print_errors
    rm -f "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script" "$interactive_quit_file"
}

run_with_progress() {
    progress_out=$(mktemp "${TMPDIR:-/tmp}/sizes-output.XXXXXX") || exit 1
    progress_err=$(mktemp "${TMPDIR:-/tmp}/sizes-stderr.XXXXXX") || exit 1
    progress_count_file=$(mktemp "${TMPDIR:-/tmp}/sizes-progress.XXXXXX") || exit 1

    generate >"$progress_out" 2>"$progress_err" &
    progress_pid=$!
    progress_i=0

    while kill -0 "$progress_pid" 2>/dev/null; do
        progress_i=$((progress_i + 1))
        case $((progress_i % 4)) in
            0) progress_ch='-' ;;
            1) progress_ch="\\" ;;
            2) progress_ch='|' ;;
            *) progress_ch='/' ;;
        esac
        progress_count=""
        if [ -s "$progress_count_file" ]; then
            progress_count=$(tail -n 1 "$progress_count_file" 2>/dev/null | tr -cd '0-9' || printf '')
        fi
        case "$progress_count" in
            ''|*[!0-9]*) printf '\rsizes: scanning %s (%s) %s' "$dir" "$mode" "$progress_ch" >&2 ;;
            *) printf '\rsizes: scanning %s (%s) %s %s files' "$dir" "$mode" "$progress_ch" "$progress_count" >&2 ;;
        esac
        sleep 0.1
    done

    wait "$progress_pid"
    progress_status=$?

    printf '\r%120s\r' ' ' >&2
    cat "$progress_out"
    cat "$progress_err" >&2
    rm -f "$progress_out" "$progress_err" "$progress_count_file"
    progress_count_file=""
    return "$progress_status"
}

if [ "$save_path" != "" ]; then
    generate >"$save_path"
elif [ "$interactive" -eq 1 ]; then
    run_interactive
elif [ "$progress" -eq 1 ]; then
    run_with_progress
else
    generate
fi
