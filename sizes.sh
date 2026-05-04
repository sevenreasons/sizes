#!/usr/bin/env sh
# sizes - show total file size by extension in a pretty terminal table.
# Requires GNU find-compatible find for -printf. Uses gfind automatically when available.

set -u

VERSION="0.5.4"

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
  -i, --interactive        Browse extension summary interactively with fzf.
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

records_file=$1
ext=$2
preview_mode=${3:-files}
field_sep=$(printf '\037')

if [ "$ext" = "" ]; then
    printf '%s\n' 'Select an extension to preview details.'
    exit 0
fi

if [ "$ext" = "OTHER" ]; then
    printf '%s\n' 'OTHER is a folded summary row.'
    printf '%s\n' 'Use a higher --limit or remove min filters to inspect specific extensions.'
    exit 0
fi

case "$preview_mode" in
    dirs)
        awk -F"$field_sep" -v target="$ext" '
            function keep() { return target == "TOTAL" || toupper($3) == toupper(target) }
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
        | awk -F"$field_sep" -v target="$ext" '
            function human(n,    u, units) {
                split("B KiB MiB GiB TiB PiB", units, " ")
                u = 1
                while (n >= 1024 && u < 6) { n /= 1024; u++ }
                if (u == 1) return sprintf("%9.0f %s", n, units[u])
                return sprintf("%9.2f %s", n, units[u])
            }
            BEGIN {
                title = target == "TOTAL" ? "Top directories overall" : "Top directories for " target
            }
            NR == 1 {
                if (target != "TOTAL" && $4 != "") title = title " (" $4 ")"
                print title
                print ""
                printf "%-14s  %8s  %s\n", "SIZE", "FILES", "DIR"
                printf "%-14s  %8s  %s\n", "────────────", "─────", "────────────────────────────────────────"
            }
            NR <= 30 {
                seen = 1
                printf "%14s  %8d  %s\n", human($1), $2, $3
            }
            END {
                if (!seen) {
                    print title
                    print ""
                    print "No matching directories."
                }
            }'
        ;;
    *)
        awk -F"$field_sep" -v target="$ext" '
            target == "TOTAL" || toupper($3) == toupper(target) { print $0 }
        ' "$records_file" \
        | LC_ALL=C sort -t "$field_sep" -k1,1nr \
        | awk -F"$field_sep" -v target="$ext" '
            function human(n,    u, units) {
                split("B KiB MiB GiB TiB PiB", units, " ")
                u = 1
                while (n >= 1024 && u < 6) { n /= 1024; u++ }
                if (u == 1) return sprintf("%9.0f %s", n, units[u])
                return sprintf("%9.2f %s", n, units[u])
            }
            BEGIN {
                title = target == "TOTAL" ? "Top files overall" : "Top files for " target
            }
            NR == 1 {
                if (target != "TOTAL" && $4 != "") title = title " (" $4 ")"
                print title
                print ""
                printf "%-14s  %s\n", "SIZE", "PATH"
                printf "%-14s  %s\n", "────────────", "────────────────────────────────────────"
            }
            NR <= 30 {
                seen = 1
                printf "%14s  %s\n", human($1), $2
            }
            END {
                if (!seen) {
                    print title
                    print ""
                    print "No matching files."
                }
            }'
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

    generate_interactive_data "$records_file" >"$summary_file"
}

interactive_select_parts() {
    # Prints key on line 1 and selected row on line 2.
    # Supports both real fzf --expect output and minimal fake-fzf test output.
    fzf_output=$1
    first=$(printf '%s\n' "$fzf_output" | sed -n '1p')
    second=$(printf '%s\n' "$fzf_output" | sed -n '2p')

    case "$first" in
        enter|ctrl-f|ctrl-d)
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
[ "$human_path" = "" ] && human_path="-"

case "$mode" in
    dir)
        printf '%s\n' 'Directory'
        printf '%s\n\n' '─────────'
        printf '%-8s %s\n' 'Path:' "$human_path"
        printf '%-8s %s\n' 'Size:' "${size:-'-'}"
        printf '%-8s %s\n' 'Files:' "${files:-'-'}"
        printf '%-8s %s\n' 'Ext:' "${ext:-'-'}"
        printf '%-8s %s\n' 'Type:' "${kind:-'-'}"
        printf '\n%s\n' 'Actions'
        printf '%s\n' '───────'
        printf '%-8s %s\n' 'Enter' 'print selected directory'
        printf '%-8s %s\n' 'Esc' 'go back / quit'
        ;;
    *)
        printf '%s\n' 'File'
        printf '%s\n\n' '────'
        printf '%-8s %s\n' 'Path:' "$human_path"
        printf '%-8s %s\n' 'Size:' "${size:-'-'}"
        printf '%-8s %s\n' 'Ext:' "${ext:-'-'}"
        printf '%-8s %s\n' 'Type:' "${kind:-'-'}"
        printf '\n%s\n' 'Actions'
        printf '%s\n' '───────'
        printf '%-8s %s\n' 'Enter' 'print selected file'
        printf '%-8s %s\n' 'Ctrl-O' 'open selected file with default app'
        printf '%-8s %s\n' 'Esc' 'go back / quit'
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
[ "$path" = "" ] && exit 0

if command -v xdg-open >/dev/null 2>&1; then
    (xdg-open "$path" >/dev/null 2>&1 &) || true
elif command -v gio >/dev/null 2>&1; then
    (gio open "$path" >/dev/null 2>&1 &) || true
elif command -v open >/dev/null 2>&1; then
    (open "$path" >/dev/null 2>&1 &) || true
else
    printf '%s\n' 'sizes: no opener found (tried xdg-open, gio, open)' >&2
    exit 1
fi
OPENSCRIPT
    chmod +x "$open_script"
}

make_interactive_file_list() {
    records_file=$1
    ext=$2
    out_file=$3

    awk -F"$field_sep" -v target="$ext" -v OFS="$field_sep" '
        function human(n,    u, units) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            u = 1
            while (n >= 1024 && u < 6) { n /= 1024; u++ }
            if (u == 1) return sprintf("%9.0f %s", n, units[u])
            return sprintf("%9.2f %s", n, units[u])
        }
        function clip(s, w) { return length(s) > w ? substr(s, 1, w - 1) "~" : s }
        target == "TOTAL" || toupper($3) == toupper(target) {
            print $1, $2, $3, $4
        }
    ' "$records_file" \
    | LC_ALL=C sort -t "$field_sep" -k1,1nr \
    | awk -F"$field_sep" -v OFS="$field_sep" '
        function human(n,    u, units) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            u = 1
            while (n >= 1024 && u < 6) { n /= 1024; u++ }
            if (u == 1) return sprintf("%9.0f %s", n, units[u])
            return sprintf("%9.2f %s", n, units[u])
        }
        function clip(s, w) { return length(s) > w ? substr(s, 1, w - 1) "~" : s }
        {
            size_h = human($1)
            display = sprintf("%14s  %s", size_h, clip($2, 120))
            print $2, display, $3, $4, $1, size_h
        }
    ' >"$out_file"
}

make_interactive_dir_list() {
    records_file=$1
    ext=$2
    out_file=$3

    awk -F"$field_sep" -v target="$ext" -v OFS="$field_sep" '
        function dirname(path,    d) {
            d = path
            sub(/\/[^\/]*$/, "", d)
            if (d == "" || d == path) return "."
            return d
        }
        target == "TOTAL" || toupper($3) == toupper(target) {
            d = dirname($2)
            bytes[d] += $1
            files[d] += 1
            ext_for[d] = target
            type_for[d] = $4
        }
        END {
            for (d in bytes) print bytes[d], d, files[d], ext_for[d], type_for[d]
        }
    ' "$records_file" \
    | LC_ALL=C sort -t "$field_sep" -k1,1nr \
    | awk -F"$field_sep" -v OFS="$field_sep" '
        function human(n,    u, units) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            u = 1
            while (n >= 1024 && u < 6) { n /= 1024; u++ }
            if (u == 1) return sprintf("%9.0f %s", n, units[u])
            return sprintf("%9.2f %s", n, units[u])
        }
        function commas(n,    s, out) {
            s = sprintf("%d", n); out = ""
            while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) }
            return s out
        }
        function clip(s, w) { return length(s) > w ? substr(s, 1, w - 1) "~" : s }
        {
            size_h = human($1)
            display = sprintf("%14s  %9s  %s", size_h, commas($3), clip($2, 120))
            print $2, display, $4, $5, $1, size_h, $3
        }
    ' >"$out_file"
}

print_selected_file() {
    selected_file=$1
    printf '%s\n' "$selected_file" | awk -F"$field_sep" '
        BEGIN {
            top = "╭────────────────┬──────────┬────────────────────────────────────────────────────────────╮"
            mid = "├────────────────┼──────────┼────────────────────────────────────────────────────────────┤"
            bottom = "╰────────────────┴──────────┴────────────────────────────────────────────────────────────╯"
            print "sizes — selected file"
            print top
            printf "│ %14s │ %-8s │ %-58s │\n", "SIZE", "TYPE", "PATH"
            print mid
        }
        {
            printf "│ %14s │ %-8s │ %-58s │\n", $6, $4, substr($1, 1, 58)
        }
        END { print bottom }'
}

print_selected_dir() {
    selected_dir=$1
    printf '%s\n' "$selected_dir" | awk -F"$field_sep" '
        BEGIN {
            top = "╭────────────────┬───────────┬────────────────────────────────────────────────────────────╮"
            mid = "├────────────────┼───────────┼────────────────────────────────────────────────────────────┤"
            bottom = "╰────────────────┴───────────┴────────────────────────────────────────────────────────────╯"
            print "sizes — selected directory"
            print top
            printf "│ %14s │ %9s │ %-58s │\n", "SIZE", "FILES", "PATH"
            print mid
        }
        {
            printf "│ %14s │ %9d │ %-58s │\n", $6, $7, substr($1, 1, 58)
        }
        END { print bottom }'
}

run_interactive_file_browser() {
    fzf_cmd=$1
    records_file=$2
    ext=$3
    item_preview_script=$4
    open_script=$5

    if [ "$ext" = "OTHER" ]; then
        printf '%s\n' 'sizes: OTHER is a folded summary row. Increase --limit or remove filters to inspect files.' >&2
        return 0
    fi

    file_list=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-files.XXXXXX") || exit 1
    make_interactive_file_list "$records_file" "$ext" "$file_list"

    if [ ! -s "$file_list" ]; then
        rm -f "$file_list"
        printf '%s\n' 'sizes: no matching files'
        return 0
    fi

    title=$(printf 'sizes files — %s · / search · ↑↓ files · Ctrl-O open · Enter print · Esc back' "$ext")
    selected_file=$("$fzf_cmd" \
        --ansi \
        --no-sort \
        --cycle \
        --delimiter="$field_sep" \
        --with-nth=2 \
        --header="$title" \
        --prompt='files> ' \
        --layout=reverse \
        --info=inline-right \
        --preview="$item_preview_script file {1} {6} {4} {3}" \
        --bind="ctrl-o:execute-silent($open_script {1}),alt-j:preview-down,alt-k:preview-up,alt-d:preview-page-down,alt-u:preview-page-up,alt-t:preview-top,alt-b:preview-bottom" \
        --preview-window='right:50%:wrap' \
        --height='95%' \
        --border \
        <"$file_list" || true)

    rm -f "$file_list"

    if [ "$selected_file" != "" ]; then
        print_selected_file "$selected_file"
    fi
}

run_interactive_dir_browser() {
    fzf_cmd=$1
    records_file=$2
    ext=$3
    item_preview_script=$4

    if [ "$ext" = "OTHER" ]; then
        printf '%s\n' 'sizes: OTHER is a folded summary row. Increase --limit or remove filters to inspect directories.' >&2
        return 0
    fi

    dir_list=$(mktemp "${TMPDIR:-/tmp}/sizes-interactive-dirs.XXXXXX") || exit 1
    make_interactive_dir_list "$records_file" "$ext" "$dir_list"

    if [ ! -s "$dir_list" ]; then
        rm -f "$dir_list"
        printf '%s\n' 'sizes: no matching directories'
        return 0
    fi

    title=$(printf 'sizes directories — %s · / search · ↑↓ dirs · Enter print · Esc back' "$ext")
    selected_dir=$("$fzf_cmd" \
        --ansi \
        --no-sort \
        --cycle \
        --delimiter="$field_sep" \
        --with-nth=2 \
        --header="$title" \
        --prompt='dirs> ' \
        --layout=reverse \
        --info=inline-right \
        --preview="$item_preview_script dir {1} {6} {4} {3} {7}" \
        --bind='alt-j:preview-down,alt-k:preview-up,alt-d:preview-page-down,alt-u:preview-page-up,alt-t:preview-top,alt-b:preview-bottom' \
        --preview-window='right:50%:wrap' \
        --height='95%' \
        --border \
        <"$dir_list" || true)

    rm -f "$dir_list"

    if [ "$selected_dir" != "" ]; then
        print_selected_dir "$selected_dir"
    fi
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

    write_interactive_preview_script "$preview_script"
    write_interactive_item_preview_script "$item_preview_script"
    write_interactive_open_script "$open_script"

    if ! run_interactive_scan "$summary_file" "$records_file"; then
        rm -f "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script"
        exit 1
    fi

    if [ ! -s "$summary_file" ]; then
        printf '%s\n' 'sizes: no files found'
        print_errors
        rm -f "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script"
        return 0
    fi

    header=$(printf '%s\n%s\n%s' \
        'sizes interactive — / search · ↑↓ rows · Enter/Ctrl-F files · Ctrl-D dirs · Esc quit' \
        '────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────' \
        'EXT           TYPE              SIZE      FILES    SHARE')

    fzf_out=$("$fzf_cmd" \
        --ansi \
        --no-sort \
        --cycle \
        --expect=enter,ctrl-f,ctrl-d \
        --delimiter="$field_sep" \
        --with-nth=2 \
        --header="$header" \
        --prompt='sizes> ' \
        --layout=reverse \
        --info=inline-right \
        --preview="$preview_script '$records_file' {1} files" \
        --bind='alt-j:preview-down,alt-k:preview-up,alt-d:preview-page-down,alt-u:preview-page-up,alt-t:preview-top,alt-b:preview-bottom' \
        --preview-window='right:50%:wrap' \
        --height='95%' \
        --border \
        <"$summary_file" || true)

    if [ "$fzf_out" != "" ]; then
        parsed=$(interactive_select_parts "$fzf_out")
        key=$(printf '%s\n' "$parsed" | sed -n '1p')
        selected=$(printf '%s\n' "$parsed" | sed -n '2p')

        if [ "$selected" != "" ]; then
            selected_ext=$(printf '%s\n' "$selected" | awk -F"$field_sep" '{ print $1 }')
            case "$key" in
                ctrl-d)
                    run_interactive_dir_browser "$fzf_cmd" "$records_file" "$selected_ext" "$item_preview_script"
                    ;;
                *)
                    run_interactive_file_browser "$fzf_cmd" "$records_file" "$selected_ext" "$item_preview_script" "$open_script"
                    ;;
            esac
        fi
    fi

    print_errors
    rm -f "$summary_file" "$records_file" "$preview_script" "$item_preview_script" "$open_script"
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
