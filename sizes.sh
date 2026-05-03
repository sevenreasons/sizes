#!/usr/bin/env sh
# sizes - show total file size by extension in a pretty terminal table.
# Requires GNU find-compatible find for -printf. Uses gfind automatically when available.

set -u

VERSION="0.2.0"

usage() {
    cat <<'USAGE'
Usage: sizes [OPTIONS] [DIR]

Pretty terminal table for total file size by extension.

Options:
  -r, --recursive          Scan recursively. Default: current directory only.
  -n, --limit N            Show top N rows and fold the rest into OTHER.
                           Default: show all rows.
  -e, --exact              Do not merge aliases like JPEG -> JPG.
  -E, --errors             Print unreadable-path errors after the table.
      --exclude PATTERN    Exclude matching paths. Can be used multiple times.
      --sort FIELD         Sort by size, files, share, ext, or type. Default: size.
      --format FORMAT      Output table, tsv, csv, or json. Default: table.
      --group-by FIELD     Group by ext or type. Default: ext.
      --plain              Use a simple ASCII table.
      --no-color           Disable ANSI colors.
      --version            Print version.
  -h, --help               Show this help.

Environment:
  NO_COLOR=1               Disable ANSI colors.
  CLICOLOR=0               Disable ANSI colors.
  SIZES_EXCLUDE="..."      Space-separated default exclude patterns.
  SIZES_FIND=/path/to/find Override find command.

Examples:
  sizes
  sizes -r
  sizes ~/Downloads -r
  sizes -r -n 40
  sizes -r --exclude .git --exclude node_modules
  sizes -r --sort files
  sizes -r --group-by type
  sizes -r --format json
  sizes --plain
USAGE
}

fail() {
    printf '%s\n' "sizes: $*" >&2
    exit 2
}

recursive=0
merge=1
limit=0
show_errors=0
color=1
plain=0
sort_by="size"
format="table"
group_by="ext"
dir="."
dir_seen=0
exclude_data=""
exclude_count=0
sep=$(printf '\034')

add_exclude() {
    [ "$1" != "" ] || return 0
    if [ "$exclude_data" = "" ]; then
        exclude_data=$1
    else
        exclude_data=$exclude_data$sep$1
    fi
    exclude_count=$((exclude_count + 1))
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
        -e|--exact)
            merge=0
            shift
            ;;
        -E|--errors)
            show_errors=1
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
            shift 2
            ;;
        --format=*)
            format=${1#*=}
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
        --no-color)
            color=0
            shift
            ;;
        --version)
            printf 'sizes %s\n' "$VERSION"
            exit 0
            ;;
        -n|--limit)
            [ "$#" -ge 2 ] || fail "missing value for $1"
            limit=$2
            case "$limit" in
                ''|*[!0-9]*) fail "--limit must be a non-negative integer" ;;
            esac
            shift 2
            ;;
        --limit=*)
            limit=${1#*=}
            case "$limit" in
                ''|*[!0-9]*) fail "--limit must be a non-negative integer" ;;
            esac
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

if [ "$format" != "table" ]; then
    color=0
    plain=0
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

errfile=$(mktemp "${TMPDIR:-/tmp}/sizes-errors.XXXXXX") || exit 1
exclude_file=$(mktemp "${TMPDIR:-/tmp}/sizes-exclude.XXXXXX") || exit 1
trap 'rm -f "$errfile" "$exclude_file"' EXIT HUP INT TERM

if [ "$exclude_data" != "" ]; then
    awk -v excludes="$exclude_data" 'BEGIN { n = split(excludes, ex, "\034"); for (i = 1; i <= n; i++) if (ex[i] != "") print ex[i] }' >"$exclude_file"
fi

run_find() {
    set -- "$dir"

    if [ "$recursive" -eq 0 ]; then
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
                */*)
                    set -- "$@" -path "$pattern" -o -path "*/$pattern"
                    ;;
                *)
                    set -- "$@" -name "$pattern"
                    ;;
            esac

            first=0
        done <"$exclude_file"
        set -- "$@" ")" -prune -o -type f -printf '%s\t%p\t%f\0'
    else
        set -- "$@" -type f -printf '%s\t%p\t%f\0'
    fi

    command "$find_cmd" "$@" 2>"$errfile"
}

tab=$(printf '\t')

sort_records() {
    case "$sort_by" in
        size|share)
            sort -t "$tab" -k1,1nr
            ;;
        files)
            sort -t "$tab" -k1,1nr
            ;;
        ext|type)
            sort -t "$tab" -k1,1f
            ;;
    esac
}

run_find \
| awk -v RS='\0' -F'\t' \
    -v merge="$merge" \
    -v group_by="$group_by" \
    -v sort_by="$sort_by" \
    -v dir="$dir" \
    -v excludes="$exclude_data" '
    function regex_escape(s,    out, i, ch) {
        out = ""
        for (i = 1; i <= length(s); i++) {
            ch = substr(s, i, 1)
            if (ch ~ /[][\\.^$()+{}|]/)
                out = out "\\" ch
            else
                out = out ch
        }
        return out
    }

    function glob_to_regex(s,    out, i, ch) {
        out = ""
        for (i = 1; i <= length(s); i++) {
            ch = substr(s, i, 1)
            if (ch == "*")
                out = out ".*"
            else if (ch == "?")
                out = out "."
            else if (ch ~ /[][\\.^$()+{}|]/)
                out = out "\\" ch
            else
                out = out ch
        }
        return out
    }

    function has_glob(s) {
        return s ~ /[*?]/
    }

    function relpath(path) {
        if (substr(path, 1, length(dir) + 1) == dir "/")
            return substr(path, length(dir) + 2)
        if (substr(path, 1, 2) == "./")
            return substr(path, 3)
        return path
    }

    function excluded(path, base,    rel, i, p, rx) {
        rel = relpath(path)
        for (i = 1; i <= nex; i++) {
            p = ex[i]
            if (p == "")
                continue

            if (has_glob(p)) {
                rx = "^" glob_to_regex(p) "$"
                if (rel ~ rx || path ~ rx || base ~ rx)
                    return 1
                rx = "/" glob_to_regex(p) "(/|$)"
                if (path ~ rx || rel ~ rx)
                    return 1
            } else if (p ~ /\//) {
                if (rel == p || substr(rel, 1, length(p) + 1) == p "/" || path == p || substr(path, 1, length(p) + 1) == p "/")
                    return 1
            } else {
                rx = "(^|/)" regex_escape(p) "(/|$)"
                if (base == p || rel ~ rx || path ~ rx)
                    return 1
            }
        }
        return 0
    }

    function extname(name,    n, a, e) {
        if (name ~ /^\.[^.]+$/)
            return "NO_EXT"

        n = split(name, a, ".")
        e = (n > 1 && a[n] != "") ? toupper(a[n]) : "NO_EXT"

        if (merge) {
            if (e == "JPEG" || e == "JPE") e = "JPG"
            else if (e == "MPEG") e = "MPG"
            else if (e == "3GPP") e = "3GP"
            else if (e == "TIF") e = "TIFF"
            else if (e == "HTM") e = "HTML"
            else if (e == "YML") e = "YAML"
            else if (e == "SQLITE3") e = "SQLITE"
        }

        return e
    }

    function kind(ext) {
        if (ext == "NO_EXT") return "none"
        if (ext == "OTHER") return "mixed"
        if (ext == "TOTAL") return "all"

        if (ext ~ /^(MP4|M4V|MOV|MKV|WEBM|AVI|WMV|MTS|M2TS|FLV|MPG|MPEG|3GP|3GPP|TS|Y4M|VOB|OGV)$/) return "video"
        if (ext ~ /^(JPG|JPEG|JPE|PNG|WEBP|GIF|AVIF|JXL|BMP|PSD|TIFF|TIF|HEIC|HEIF|SVG|XCF|KRA|ICO|RAW|CR2|NEF|ARW|DNG)$/) return "image"
        if (ext ~ /^(MP3|M4A|FLAC|WAV|OGG|OPUS|AAC|AIF|AIFF|WMA|MID|MIDI|WEM|XWB|BNK|BANK)$/) return "audio"
        if (ext ~ /^(ZIP|RAR|7Z|TAR|TGZ|GZ|XZ|ZST|BZ2|LZMA|CAB|RPM|DEB|APK|APPIMAGE|ISO|DMG|Z[0-9][0-9])$/) return "archive"
        if (ext ~ /^(TXT|MD|RST|PDF|DOC|DOCX|ODT|RTF|XLS|XLSX|PPT|PPTX|EPUB)$/) return "doc"
        if (ext ~ /^(JSON|JSONL|CSV|TSV|PARQUET|ARROW|FEATHER|XML|YAML|YML|TOML|INI|CONF)$/) return "data"
        if (ext ~ /^(SQL|DB|DUCKDB|SQLITE|SQLITE3|MDB|WAL|LDB|SST)$/) return "database"
        if (ext ~ /^(GGUF|GGML|SAFETENSORS|ONNX|PTH|PT|CKPT|PB|TFLITE|H5|ORT|MODEL|BIN)$/) return "model"
        if (ext ~ /^(PY|PYI|PYC|PYD|PYX|JS|MJS|CJS|TS|TSX|JSX|HTML|CSS|SCSS|SASS|RS|GO|CPP|CXX|CC|C|H|HPP|JAVA|KT|KTS|SH|BASH|ZSH|FISH|LUA|R|RB|PHP|PL|PM|SWIFT|WASM|IPYNB)$/) return "code"
        if (ext ~ /^(TTF|OTF|TTC|WOFF|WOFF2|FON)$/) return "font"
        if (ext ~ /^(OBJ|FBX|GLB|GLTF|BLEND|BLEND[0-9]+|MESH|STL|PLY|DAE|3DS)$/) return "3d"
        if (ext ~ /^(EXE|DLL|SO|DYLIB|LIB|SYS|OCX|DRV|TLB|A|O|OBJ)$/) return "binary"
        if (ext ~ /^(SRT|VTT|ASS|SSA|SUB)$/) return "subs"
        if (ext ~ /^(LOG|MAP|LOCK|BAK|BACKUP|OLD|TMP|CACHE|PART|CRDOWNLOAD)$/) return "meta"
        if (ext ~ /^(PAK|RESS|RESOURCE|ASSETS|BUNDLE|LOTPACK|LOTHEADER|UNITY3D|DAT|ARC|WAD|PK3|PK4)$/) return "game"

        return "other"
    }

    BEGIN {
        nex = split(excludes, ex, "\034")
    }

    NF >= 3 {
        size = $1 + 0
        path = $2
        base = $3

        if (excluded(path, base))
            next

        ext = extname(base)
        k = kind(ext)
        key = (group_by == "type") ? k : ext

        bytes[key] += size
        count[key] += 1
        total += size
        total_count += 1

        if (!(key in row_kind))
            row_kind[key] = (group_by == "type") ? key : k
    }

    END {
        for (key in bytes) {
            k = row_kind[key]
            if (sort_by == "files") sortkey = count[key]
            else if (sort_by == "ext") sortkey = key
            else if (sort_by == "type") sortkey = k " " key
            else sortkey = bytes[key]

            printf "%s\t%.0f\t%d\t%s\t%s\t%.0f\t%d\n", sortkey, bytes[key], count[key], key, k, total, total_count
        }
    }
' \
| sort_records \
| awk -F'\t' \
    -v limit="$limit" \
    -v dir="$dir" \
    -v mode="$mode" \
    -v color="$color" \
    -v plain="$plain" \
    -v format="$format" \
    -v group_by="$group_by" '
    BEGIN {
        if (color) {
            reset = "\033[0m"
            bold  = "\033[1m"
            dim   = "\033[2m"
            red     = "\033[31m"
            green   = "\033[32m"
            yellow  = "\033[33m"
            blue    = "\033[34m"
            magenta = "\033[35m"
            cyan    = "\033[36m"
            white   = "\033[97m"
            gray    = "\033[90m"
        } else {
            reset = bold = dim = red = green = yellow = blue = magenta = cyan = white = gray = ""
        }

        barw = plain ? 16 : 18
        limited = limit + 0 > 0

        if (format == "json") {
            print "["
        } else if (format == "tsv") {
            if (group_by == "type")
                print "type\tbytes\tsize\tfiles\tshare_pct"
            else
                print "ext\ttype\tbytes\tsize\tfiles\tshare_pct"
        } else if (format == "csv") {
            if (group_by == "type")
                print "type,bytes,size,files,share_pct"
            else
                print "ext,type,bytes,size,files,share_pct"
        } else if (plain) {
            printf "sizes %s - %s\n", dir, mode
            if (group_by == "type")
                printf "%-12s %14s %9s %8s %s\n", "TYPE", "SIZE", "FILES", "SHARE", "BAR"
            else
                printf "%-12s %-10s %14s %9s %8s %s\n", "EXT", "TYPE", "SIZE", "FILES", "SHARE", "BAR"
        } else {
            if (group_by == "type") {
                top =    "╭──────────────┬────────────────┬───────────┬──────────┬────────────────────╮"
                mid =    "├──────────────┼────────────────┼───────────┼──────────┼────────────────────┤"
                bottom = "╰──────────────┴────────────────┴───────────┴──────────┴────────────────────╯"
            } else {
                top =    "╭──────────────┬──────────┬────────────────┬───────────┬──────────┬────────────────────╮"
                mid =    "├──────────────┼──────────┼────────────────┼───────────┼──────────┼────────────────────┤"
                bottom = "╰──────────────┴──────────┴────────────────┴───────────┴──────────┴────────────────────╯"
            }

            printf "%s%s%s %s%s — %s%s\n", bold, "sizes", reset, dim, dir, mode, reset
            print gray top reset

            if (group_by == "type") {
                printf "%s│%s %s%-12s%s %s│%s %s%14s%s %s│%s %s%9s%s %s│%s %s%8s%s %s│%s %s%-18s%s %s│%s\n",
                    gray, reset, bold cyan, "TYPE", reset,
                    gray, reset, bold cyan, "SIZE", reset,
                    gray, reset, bold cyan, "FILES", reset,
                    gray, reset, bold cyan, "SHARE", reset,
                    gray, reset, bold cyan, "BAR", reset,
                    gray, reset
            } else {
                printf "%s│%s %s%-12s%s %s│%s %s%-8s%s %s│%s %s%14s%s %s│%s %s%9s%s %s│%s %s%8s%s %s│%s %s%-18s%s %s│%s\n",
                    gray, reset, bold cyan, "EXT", reset,
                    gray, reset, bold cyan, "TYPE", reset,
                    gray, reset, bold cyan, "SIZE", reset,
                    gray, reset, bold cyan, "FILES", reset,
                    gray, reset, bold cyan, "SHARE", reset,
                    gray, reset, bold cyan, "BAR", reset,
                    gray, reset
            }

            print gray mid reset
        }
    }

    function clip(s, w) {
        return length(s) > w ? substr(s, 1, w - 1) "~" : s
    }

    function commas(n,    s, out) {
        s = sprintf("%d", n)
        out = ""
        while (length(s) > 3) {
            out = "," substr(s, length(s) - 2) out
            s = substr(s, 1, length(s) - 3)
        }
        return s out
    }

    function human(n,    u, units) {
        split("B KiB MiB GiB TiB PiB", units, " ")
        u = 1
        while (n >= 1024 && u < 6) {
            n /= 1024
            u++
        }
        if (u == 1)
            return sprintf("%9.0f %s", n, units[u])
        return sprintf("%9.2f %s", n, units[u])
    }

    function trimhuman(s) {
        sub(/^ +/, "", s)
        return s
    }

    function pctnum(bytes, total) {
        return total ? bytes * 100 / total : 0
    }

    function pctfmt(p) {
        if (p > 0 && p < 0.01)
            return sprintf("%8s", "<0.01%")
        return sprintf("%7.2f%%", p)
    }

    function csvq(s,    t) {
        t = s
        gsub(/"/, "\"\"", t)
        return "\"" t "\""
    }

    function jsonq(s,    t) {
        t = s
        gsub(/\\/, "\\\\", t)
        gsub(/"/, "\\\"", t)
        gsub(/\t/, "\\t", t)
        gsub(/\r/, "\\r", t)
        gsub(/\n/, "\\n", t)
        return "\"" t "\""
    }

    function kind_color(k) {
        if (k == "video") return red
        if (k == "image") return magenta
        if (k == "audio") return blue
        if (k == "archive") return yellow
        if (k == "doc") return green
        if (k == "data") return cyan
        if (k == "database") return cyan
        if (k == "model") return yellow
        if (k == "code") return cyan
        if (k == "font") return magenta
        if (k == "3d") return green
        if (k == "binary") return red
        if (k == "subs") return green
        if (k == "meta") return gray
        if (k == "game") return yellow
        if (k == "none") return gray
        if (k == "mixed") return white
        if (k == "all") return white
        return cyan
    }

    function heat_color(bytes, p) {
        if (bytes >= 10 * 1024 * 1024 * 1024 || p >= 20) return red
        if (bytes >= 1024 * 1024 * 1024 || p >= 5) return yellow
        if (bytes >= 100 * 1024 * 1024 || p >= 1) return green
        if (bytes > 0) return gray
        return gray
    }

    function makebar(p, c,    filled, i, full, empty, fullc, emptyc) {
        filled = int((p * barw / 100) + 0.5)
        if (filled > barw)
            filled = barw

        full = ""
        empty = ""
        fullc = plain ? "#" : "█"
        emptyc = plain ? "." : "░"

        for (i = 1; i <= filled; i++)
            full = full fullc
        for (i = filled + 1; i <= barw; i++)
            empty = empty emptyc

        return c full reset gray empty reset
    }

    function emit_machine(name, k, bytes, files, total, is_total,    share, h, prefix) {
        share = total ? bytes * 100 / total : 0
        if (is_total && total > 0)
            share = 100
        h = trimhuman(human(bytes))

        if (format == "tsv") {
            if (group_by == "type")
                printf "%s\t%.0f\t%s\t%d\t%.2f\n", name, bytes, h, files, share
            else
                printf "%s\t%s\t%.0f\t%s\t%d\t%.2f\n", name, k, bytes, h, files, share
        } else if (format == "csv") {
            if (group_by == "type")
                printf "%s,%.0f,%s,%d,%.2f\n", csvq(name), bytes, csvq(h), files, share
            else
                printf "%s,%s,%.0f,%s,%d,%.2f\n", csvq(name), csvq(k), bytes, csvq(h), files, share
        } else if (format == "json") {
            prefix = json_count ? "," : ""
            if (group_by == "type")
                printf "%s  {\"type\":%s,\"bytes\":%.0f,\"size\":%s,\"files\":%d,\"share_pct\":%.2f}\n", prefix, jsonq(name), bytes, jsonq(h), files, share
            else
                printf "%s  {\"ext\":%s,\"type\":%s,\"bytes\":%.0f,\"size\":%s,\"files\":%d,\"share_pct\":%.2f}\n", prefix, jsonq(name), jsonq(k), bytes, jsonq(h), files, share
            json_count++
        }
    }

    function emit_row(name, k, bytes, files, total, is_total,    share, barpct, sc, kc, label, h, c, pct, b) {
        if (format != "table") {
            emit_machine(name, k, bytes, files, total, is_total)
            return
        }

        share = total ? bytes * 100 / total : 0
        if (is_total && total > 0) {
            share = 100
            barpct = 100
        } else {
            barpct = max_bytes ? bytes * 100 / max_bytes : 0
        }

        sc = is_total ? bold white : heat_color(bytes, share)
        kc = is_total ? bold white : kind_color(k)
        label = clip(name, 12)
        h = human(bytes)
        c = commas(files)
        pct = pctfmt(share)
        b = makebar(barpct, sc)

        if (plain) {
            if (group_by == "type")
                printf "%-12s %14s %9s %8s %s\n", label, h, c, pct, b
            else
                printf "%-12s %-10s %14s %9s %8s %s\n", label, k, h, c, pct, b
        } else if (group_by == "type") {
            printf "%s│%s %s%-12s%s %s│%s %s%14s%s %s│%s %9s %s│%s %8s %s│%s %s %s│%s\n",
                gray, reset, kc, label, reset,
                gray, reset, sc, h, reset,
                gray, reset, c,
                gray, reset, pct,
                gray, reset, b,
                gray, reset
        } else {
            printf "%s│%s %s%-12s%s %s│%s %s%-8s%s %s│%s %s%14s%s %s│%s %9s %s│%s %8s %s│%s %s %s│%s\n",
                gray, reset, kc, label, reset,
                gray, reset, kc, k, reset,
                gray, reset, sc, h, reset,
                gray, reset, c,
                gray, reset, pct,
                gray, reset, b,
                gray, reset
        }
    }

    {
        seen = 1
        bytes = $2 + 0
        files = $3 + 0
        name = $4
        k = $5
        total_bytes = $6 + 0
        total_count = $7 + 0

        if (shown == 0)
            max_bytes = bytes

        if (!limited || shown < limit) {
            emit_row(name, k, bytes, files, total_bytes, 0)
            shown++
        } else {
            other_bytes += bytes
            other_count += files
            other_types++
        }
    }

    END {
        if (!seen) {
            total_bytes = 0
            total_count = 0
            if (format == "table") {
                if (plain) {
                    if (group_by == "type")
                        printf "%-12s %14s %9s %8s %s\n", "NO_FILES", "-", "-", "-", "No files found"
                    else
                        printf "%-12s %-10s %14s %9s %8s %s\n", "NO_FILES", "-", "-", "-", "-", "No files found"
                } else if (group_by == "type") {
                    printf "%s│%s %-12s %s│%s %14s %s│%s %9s %s│%s %8s %s│%s %-18s %s│%s\n",
                        gray, reset, "NO_FILES",
                        gray, reset, "-",
                        gray, reset, "-",
                        gray, reset, "-",
                        gray, reset, "No files found",
                        gray, reset
                } else {
                    printf "%s│%s %-12s %s│%s %-8s %s│%s %14s %s│%s %9s %s│%s %8s %s│%s %-18s %s│%s\n",
                        gray, reset, "NO_FILES",
                        gray, reset, "-",
                        gray, reset, "-",
                        gray, reset, "-",
                        gray, reset, "-",
                        gray, reset, "No files found",
                        gray, reset
                }
            }
        } else if (limited && other_types > 0) {
            if (format == "table" && !plain)
                print gray mid reset
            emit_row("OTHER", "mixed", other_bytes, other_count, total_bytes, 0)
        }

        if (format == "table" && !plain)
            print gray mid reset
        emit_row("TOTAL", "all", total_bytes, total_count, total_bytes, 1)

        if (format == "table" && !plain)
            print gray bottom reset
        else if (format == "json")
            print "]"
    }
'

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
