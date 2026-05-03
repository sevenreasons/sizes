#!/usr/bin/env sh
# sizes - show total file size by extension in a pretty terminal table.
# Requires GNU find-compatible find for -printf. Uses gfind automatically when available.

set -u

VERSION="0.1.0"

usage() {
    cat <<'USAGE'
Usage: sizes [OPTIONS] [DIR]

Pretty terminal table for total file size by extension.

Options:
  -r, --recursive   Scan recursively. Default: current directory only.
  -n, --limit N     Show top N extensions and fold the rest into OTHER.
                    Default: show all extensions.
  -e, --exact       Do not merge aliases like JPEG -> JPG.
  -E, --errors      Print unreadable-path errors after the table.
      --no-color    Disable ANSI colors.
      --version     Print version.
  -h, --help        Show this help.

Examples:
  sizes
  sizes -r
  sizes ~/Downloads -r
  sizes -r -n 40
  sizes -e
  sizes --no-color
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
dir="."
dir_seen=0

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

if [ ! -d "$dir" ]; then
    printf '%s\n' "sizes: not a directory: $dir" >&2
    exit 1
fi

find_cmd=${SIZES_FIND:-find}

if ! "$find_cmd" "$dir" -maxdepth 0 -printf '' >/dev/null 2>&1; then
    if [ "$find_cmd" = "find" ] && command -v gfind >/dev/null 2>&1 && gfind "$dir" -maxdepth 0 -printf '' >/dev/null 2>&1; then
        find_cmd=gfind
    else
        printf '%s\n' "sizes: GNU find is required because this tool uses find -printf" >&2
        printf '%s\n' "sizes: install GNU findutils, or set SIZES_FIND=/path/to/gfind" >&2
        exit 1
    fi
fi

mode="top-level"
if [ "$recursive" -eq 1 ]; then
    mode="recursive"
fi

errfile=$(mktemp "${TMPDIR:-/tmp}/sizes-errors.XXXXXX") || exit 1
trap 'rm -f "$errfile"' EXIT HUP INT TERM

run_find() {
    if [ "$recursive" -eq 1 ]; then
        "$find_cmd" "$dir" -type f -printf '%s\t%f\0' 2>"$errfile"
    else
        "$find_cmd" "$dir" -maxdepth 1 -type f -printf '%s\t%f\0' 2>"$errfile"
    fi
}

run_find \
| awk -v RS='\0' -F'\t' -v merge="$merge" '
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

    NF >= 2 {
        ext = extname($2)
        bytes[ext] += $1
        count[ext] += 1
        total += $1
        total_count += 1
    }

    END {
        for (e in bytes)
            printf "%.0f\t%d\t%s\t%.0f\t%d\n", bytes[e], count[e], e, total, total_count
    }
' \
| sort -nr \
| awk -F'\t' -v limit="$limit" -v dir="$dir" -v mode="$mode" -v color="$color" '
    BEGIN {
        if (color) {
            reset = "\033[0m"
            bold = "\033[1m"
            dim = "\033[2m"
            red = "\033[31m"
            green = "\033[32m"
            yellow = "\033[33m"
            blue = "\033[34m"
            magenta = "\033[35m"
            cyan = "\033[36m"
            white = "\033[97m"
            gray = "\033[90m"
        } else {
            reset = bold = dim = red = green = yellow = blue = magenta = cyan = white = gray = ""
        }

        barw = 18
        limited = limit + 0 > 0

        top =    "╭──────────────┬──────────┬────────────────┬───────────┬──────────┬────────────────────╮"
        mid =    "├──────────────┼──────────┼────────────────┼───────────┼──────────┼────────────────────┤"
        bottom = "╰──────────────┴──────────┴────────────────┴───────────┴──────────┴────────────────────╯"

        printf "%s%s%s %s%s — %s%s\n", bold, "sizes", reset, dim, dir, mode, reset
        print gray top reset
        printf "%s│%s %s%-12s%s %s│%s %s%-8s%s %s│%s %s%14s%s %s│%s %s%9s%s %s│%s %s%8s%s %s│%s %s%-18s%s %s│%s\n",
            gray, reset, bold cyan, "EXT", reset,
            gray, reset, bold cyan, "TYPE", reset,
            gray, reset, bold cyan, "SIZE", reset,
            gray, reset, bold cyan, "FILES", reset,
            gray, reset, bold cyan, "SHARE", reset,
            gray, reset, bold cyan, "BAR", reset,
            gray, reset
        print gray mid reset
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

    function pctfmt(p) {
        if (p > 0 && p < 0.01)
            return sprintf("%8s", "<0.01%")
        return sprintf("%7.2f%%", p)
    }

    function kind(ext) {
        if (ext == "NO_EXT") return "none"
        if (ext == "OTHER") return "mixed"
        if (ext == "TOTAL") return "all"

        if (ext ~ /^(MP4|M4V|MOV|MKV|WEBM|AVI|WMV|MTS|FLV|MPG|MPEG|3GP|3GPP|TS|Y4M)$/) return "video"
        if (ext ~ /^(JPG|JPEG|JPE|PNG|WEBP|GIF|AVIF|JXL|BMP|PSD|TIFF|TIF|HEIC|SVG|XCF|KRA|ICO)$/) return "image"
        if (ext ~ /^(MP3|M4A|FLAC|WAV|OGG|OPUS|AAC|WEM|XWB|BNK|BANK)$/) return "audio"
        if (ext ~ /^(ZIP|RAR|7Z|TAR|GZ|XZ|ZST|BZ2|LZMA|CAB|RPM|APK|Z[0-9][0-9])$/) return "archive"
        if (ext ~ /^(TXT|MD|PDF|DOC|DOCX|ODT|RTF|XLS|XLSX)$/) return "doc"
        if (ext ~ /^(JSON|JSONL|CSV|TSV|PARQUET|XML|YAML|YML|SQL|DB|DUCKDB|SQLITE|SQLITE3|WAL|LDB)$/) return "data"
        if (ext ~ /^(GGUF|SAFETENSORS|ONNX|PTH|PT|PB|TFLITE|H5|ORT|MODEL)$/) return "model"
        if (ext ~ /^(PY|PYI|PYC|PYD|PYX|JS|MJS|CJS|HTML|CSS|SCSS|RS|GO|CPP|CC|C|H|JAVA|SH|FISH|LUA|WASM|IPYNB)$/) return "code"
        if (ext ~ /^(TTF|OTF|TTC|WOFF|WOFF2|FON)$/) return "font"
        if (ext ~ /^(OBJ|FBX|GLB|BLEND|BLEND[0-9]+|MESH)$/) return "3d"
        if (ext ~ /^(EXE|DLL|SO|DYLIB|LIB|BIN|SYS|OCX|DRV|TLB)$/) return "binary"
        if (ext ~ /^(SRT|VTT|ASS|SSA)$/) return "subs"
        if (ext ~ /^(LOG|MAP|LOCK|BAK|BACKUP|OLD|TMP|CACHE|PART)$/) return "meta"
        if (ext ~ /^(PAK|RESS|RESOURCE|ASSETS|BUNDLE|LOTPACK|LOTHEADER|UNITY3D|DAT)$/) return "game"

        return "other"
    }

    function kind_color(k) {
        if (k == "video") return red
        if (k == "image") return magenta
        if (k == "audio") return blue
        if (k == "archive") return yellow
        if (k == "doc") return green
        if (k == "data") return cyan
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

    function makebar(p, c,    filled, i, full, empty) {
        filled = int((p * barw / 100) + 0.5)
        if (filled > barw)
            filled = barw

        full = ""
        empty = ""
        for (i = 1; i <= filled; i++)
            full = full "█"
        for (i = filled + 1; i <= barw; i++)
            empty = empty "░"
        return c full reset gray empty reset
    }

    function row(ext, k, bytes, files, total, is_total,    share, barpct, sc, kc, e, h, c, pct, b) {
        share = total ? bytes * 100 / total : 0
        if (is_total && total > 0) {
            share = 100
            barpct = 100
        } else {
            barpct = max_bytes ? bytes * 100 / max_bytes : 0
        }

        sc = is_total ? bold white : heat_color(bytes, share)
        kc = is_total ? bold white : kind_color(k)
        e = clip(ext, 12)
        h = human(bytes)
        c = commas(files)
        pct = pctfmt(share)
        b = makebar(barpct, sc)

        printf "%s│%s %s%-12s%s %s│%s %s%-8s%s %s│%s %s%14s%s %s│%s %9s %s│%s %8s %s│%s %s %s│%s\n",
            gray, reset, kc, e, reset,
            gray, reset, kc, k, reset,
            gray, reset, sc, h, reset,
            gray, reset, c,
            gray, reset, pct,
            gray, reset, b,
            gray, reset
    }

    {
        seen = 1
        bytes = $1 + 0
        files = $2 + 0
        ext = $3
        total_bytes = $4 + 0
        total_count = $5 + 0

        if (NR == 1)
            max_bytes = bytes

        if (!limited || shown < limit) {
            row(ext, kind(ext), bytes, files, total_bytes, 0)
            shown++
        } else {
            other_bytes += bytes
            other_count += files
            other_types++
        }
    }

    END {
        if (!seen) {
            printf "%s│%s %-12s %s│%s %-8s %s│%s %14s %s│%s %9s %s│%s %8s %s│%s %-18s %s│%s\n",
                gray, reset, "NO_FILES",
                gray, reset, "-",
                gray, reset, "-",
                gray, reset, "-",
                gray, reset, "-",
                gray, reset, "No files found",
                gray, reset
            total_bytes = 0
            total_count = 0
        } else if (limited && other_types > 0) {
            print gray mid reset
            row("OTHER", "mixed", other_bytes, other_count, total_bytes, 0)
        }

        print gray mid reset
        row("TOTAL", "all", total_bytes, total_count, total_bytes, 1)
        print gray bottom reset
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
