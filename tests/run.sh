#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SIZES="$ROOT/sizes.sh"
SIZES_WRAPPER="$ROOT/sizes"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sizes-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

pass=0

ok() {
    pass=$((pass + 1))
    printf 'ok %d - %s\n' "$pass" "$1"
}

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    file=$1
    pattern=$2
    message=$3
    if ! grep -Eq -- "$pattern" "$file"; then
        printf '\n--- output ---\n' >&2
        cat "$file" >&2
        printf '\n-------------\n' >&2
        fail "$message"
    fi
}

assert_not_contains() {
    file=$1
    pattern=$2
    message=$3
    if grep -Eq -- "$pattern" "$file"; then
        printf '\n--- output ---\n' >&2
        cat "$file" >&2
        printf '\n-------------\n' >&2
        fail "$message"
    fi
}

make_file() {
    path=$1
    bytes=$2
    dd if=/dev/zero of="$path" bs=1 count="$bytes" status=none
}

SAMPLE="$TEST_ROOT/sample"
EMPTY="$TEST_ROOT/empty"
mkdir -p "$SAMPLE/sub" "$SAMPLE/node_modules" "$SAMPLE/.git" "$EMPTY"
make_file "$SAMPLE/video.mp4" 4096
make_file "$SAMPLE/photo.jpg" 100
make_file "$SAMPLE/photo.jpeg" 200
make_file "$SAMPLE/readme.txt" 50
make_file "$SAMPLE/LICENSE" 10
make_file "$SAMPLE/.env" 5
make_file "$SAMPLE/model.gguf" 3000
make_file "$SAMPLE/data.duckdb" 2500
make_file "$SAMPLE/archive.zip" 2048
make_file "$SAMPLE/sub/deep.png" 1024
make_file "$SAMPLE/node_modules/junk.mp4" 8192
make_file "$SAMPLE/.git/object.bin" 512

OUT="$TEST_ROOT/out.txt"
ERR="$TEST_ROOT/err.txt"

"$SIZES" --version >"$OUT"
assert_contains "$OUT" '^sizes 0\.2\.1$' '--version prints current version'
ok '--version'

"$SIZES_WRAPPER" --version >"$OUT"
assert_contains "$OUT" '^sizes 0\.2\.1$' 'root wrapper prints current version'
ok 'root wrapper'

env NO_COLOR=1 "$SIZES" "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ MP4[[:space:]]+│ video' 'top-level scan includes root MP4'
assert_contains "$OUT" '│ JPG[[:space:]]+│ image' 'top-level scan merges JPEG into JPG by default'
assert_contains "$OUT" '│ TXT[[:space:]]+│ doc' 'top-level scan includes TXT'
assert_contains "$OUT" '│ NO_EXT[[:space:]]+│ none' 'top-level scan includes no-extension files'
assert_not_contains "$OUT" '│ PNG[[:space:]]+│ image' 'top-level scan must not include nested PNG'
ok 'non-recursive default'

env NO_COLOR=1 "$SIZES" -r "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ PNG[[:space:]]+│ image' 'recursive scan includes nested PNG'
ok 'recursive scan'

env NO_COLOR=1 "$SIZES" -e "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ JPEG[[:space:]]+│ image' 'exact mode keeps JPEG separate'
assert_contains "$OUT" '│ JPG[[:space:]]+│ image' 'exact mode keeps JPG separate'
ok 'exact mode'

env NO_COLOR=1 "$SIZES" -r -n 1 "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ OTHER[[:space:]]+│ mixed' 'limit mode creates OTHER row'
assert_contains "$OUT" '│ TOTAL[[:space:]]+│ all' 'limit mode keeps TOTAL row'
ok 'limit mode'

env NO_COLOR=1 "$SIZES" "$EMPTY" >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'NO_FILES' 'empty directory reports NO_FILES'
assert_contains "$OUT" '│ TOTAL[[:space:]]+│ all' 'empty directory still prints TOTAL'
ok 'empty directory'

"$SIZES" --no-color "$SAMPLE" >"$OUT" 2>"$ERR"
if LC_ALL=C grep "$(printf '\033')" "$OUT" >/dev/null 2>&1; then
    fail '--no-color output contains ANSI escapes'
fi
ok '--no-color'

env NO_COLOR=1 "$SIZES" "$SAMPLE" >"$OUT" 2>"$ERR"
if LC_ALL=C grep "$(printf '\033')" "$OUT" >/dev/null 2>&1; then
    fail 'NO_COLOR output contains ANSI escapes'
fi
ok 'NO_COLOR'

env CLICOLOR=0 "$SIZES" "$SAMPLE" >"$OUT" 2>"$ERR"
if LC_ALL=C grep "$(printf '\033')" "$OUT" >/dev/null 2>&1; then
    fail 'CLICOLOR=0 output contains ANSI escapes'
fi
ok 'CLICOLOR=0'

UPGRADE_TARGET="$TEST_ROOT/upgradable-sizes"
UPGRADE_SOURCE="$TEST_ROOT/remote-sizes"
cp "$SIZES" "$UPGRADE_TARGET"
sed 's/VERSION="0.2.1"/VERSION="9.9.9"/' "$SIZES" >"$UPGRADE_SOURCE"
chmod +x "$UPGRADE_TARGET" "$UPGRADE_SOURCE"
env SIZES_UPGRADE_URL="$UPGRADE_SOURCE" SIZES_UPGRADE_TARGET="$UPGRADE_TARGET" "$UPGRADE_TARGET" --upgrade >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'sizes: upgraded .+ from 0\.2\.1 to 9\.9\.9' '--upgrade reports old and new version'
"$UPGRADE_TARGET" --version >"$OUT"
assert_contains "$OUT" '^sizes 9\.9\.9$' '--upgrade replaces target script'
ok '--upgrade'


env NO_COLOR=1 "$SIZES" -r --exclude node_modules --exclude .git "$SAMPLE" >"$OUT" 2>"$ERR"
assert_not_contains "$OUT" '8192' 'exclude should skip node_modules files'
assert_not_contains "$OUT" '512 B' 'exclude should skip .git files'
assert_contains "$OUT" '│ MP4[[:space:]]+│ video' 'exclude should keep non-excluded MP4'
ok '--exclude'

"$SIZES" -r --format tsv "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '^ext[[:space:]]+type[[:space:]]+bytes[[:space:]]+size[[:space:]]+files[[:space:]]+share_pct$' 'tsv format prints header'
assert_contains "$OUT" '^MP4[[:space:]]+video[[:space:]]+[0-9]+' 'tsv format prints rows'
ok '--format tsv'

"$SIZES" -r --format csv "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '^ext,type,bytes,size,files,share_pct$' 'csv format prints header'
assert_contains "$OUT" '^"MP4","video",[0-9]+' 'csv format prints rows'
ok '--format csv'

"$SIZES" -r --format json "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '^\[$' 'json format starts array'
assert_contains "$OUT" '"ext":"MP4"' 'json format includes MP4 row'
assert_contains "$OUT" '"ext":"TOTAL"' 'json format includes TOTAL row'
ok '--format json'

env NO_COLOR=1 "$SIZES" -r --group-by type "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ TYPE[[:space:]]+│[[:space:]]+SIZE' 'group-by type changes table header'
assert_contains "$OUT" '│ video[[:space:]]+│' 'group-by type includes video'
assert_contains "$OUT" '│ model[[:space:]]+│' 'group-by type includes model'
assert_contains "$OUT" '│ database[[:space:]]+│' 'group-by type includes database'
ok '--group-by type'

"$SIZES" -r --plain "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '^EXT[[:space:]]+TYPE[[:space:]]+SIZE[[:space:]]+FILES[[:space:]]+SHARE[[:space:]]+BAR$' 'plain format prints ASCII header'
assert_not_contains "$OUT" '╭|│|╰' 'plain format should not print box drawing characters'
ok '--plain'

"$SIZES" -r --sort files --format tsv "$SAMPLE" >"$OUT" 2>"$ERR"
first_row=$(sed -n '2p' "$OUT" | cut -f1)
if [ "$first_row" != "JPG" ] && [ "$first_row" != "MP4" ]; then
    fail '--sort files did not put a high-count extension first'
fi
ok '--sort files'

printf '\n%d tests passed\n' "$pass"
