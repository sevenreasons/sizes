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
make_file "$SAMPLE/tab$(printf '\t')song.mp3" 333

OUT="$TEST_ROOT/out.txt"
ERR="$TEST_ROOT/err.txt"

"$SIZES" --version >"$OUT"
assert_contains "$OUT" '^sizes 0\.7\.5$' '--version prints current version'
ok '--version'

"$SIZES_WRAPPER" --version >"$OUT"
assert_contains "$OUT" '^sizes 0\.7\.5$' 'root wrapper prints current version'
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
sed 's/VERSION="0.7.5"/VERSION="9.9.9"/' "$SIZES" >"$UPGRADE_SOURCE"
chmod +x "$UPGRADE_TARGET" "$UPGRADE_SOURCE"
env SIZES_UPGRADE_URL="$UPGRADE_SOURCE" SIZES_UPGRADE_TARGET="$UPGRADE_TARGET" "$UPGRADE_TARGET" --upgrade >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'sizes: upgraded .+ from 0\.7\.5 to 9\.9\.9' '--upgrade reports old and new version'
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
assert_contains "$OUT" '^\{' 'json format starts object'
assert_contains "$OUT" '"rows": \[' 'json format includes rows array'
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


env NO_COLOR=1 "$SIZES" -r --min-size 3K "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ MP4[[:space:]]+│ video' 'min-size keeps large MP4 row'
assert_contains "$OUT" '│ OTHER[[:space:]]+│ mixed' 'min-size folds small rows into OTHER'
ok '--min-size'

env NO_COLOR=1 "$SIZES" -r --min-share 20 "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ OTHER[[:space:]]+│ mixed' 'min-share folds small-share rows into OTHER'
ok '--min-share'

env NO_COLOR=1 "$SIZES" -r --include '*.mp4' "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ MP4[[:space:]]+│ video' 'include keeps matching MP4 rows'
assert_not_contains "$OUT" '│ JPG[[:space:]]+│ image' 'include hides non-matching JPG rows'
ok '--include'

env NO_COLOR=1 "$SIZES" -r --type video "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ MP4[[:space:]]+│ video' 'type filter keeps video rows'
assert_not_contains "$OUT" '│ JPG[[:space:]]+│ image' 'type filter hides image rows'
ok '--type'

env NO_COLOR=1 "$SIZES" -r --top-files mp4 -n 1 "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'top mp4 files' 'top-files prints top-files heading'
assert_contains "$OUT" 'junk\.mp4|video\.mp4' 'top-files includes MP4 path'
ok '--top-files'

env NO_COLOR=1 "$SIZES" --depth 1 "$SAMPLE" >"$OUT" 2>"$ERR"
assert_not_contains "$OUT" '│ PNG[[:space:]]+│ image' 'depth 1 excludes nested PNG'
env NO_COLOR=1 "$SIZES" --depth 2 "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ PNG[[:space:]]+│ image' 'depth 2 includes nested PNG'
ok '--depth'

ln -s "$SAMPLE/sub" "$SAMPLE/linksub"
env NO_COLOR=1 "$SIZES" -r --follow "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ PNG[[:space:]]+│ image' 'follow keeps normal recursive results'
ok '--follow'

env SIZES_UPGRADE_URL="$UPGRADE_SOURCE" "$SIZES" --upgrade --check >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'current 0\.7\.5, available 9\.9\.9' 'upgrade check reports available version'
ok '--upgrade --check'

UPGRADE_TARGET_VERSIONED="$TEST_ROOT/upgradable-versioned-sizes"
cp "$SIZES" "$UPGRADE_TARGET_VERSIONED"
chmod +x "$UPGRADE_TARGET_VERSIONED"
env SIZES_UPGRADE_URL="$UPGRADE_SOURCE" SIZES_UPGRADE_TARGET="$UPGRADE_TARGET_VERSIONED" "$UPGRADE_TARGET_VERSIONED" --upgrade --version v9.9.9 >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'from 0\.7\.5 to 9\.9\.9' 'upgrade version installs requested source when override URL is used'
ok '--upgrade --version'



env NO_COLOR=1 "$SIZES" -r "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" '│ MP3[[:space:]]+│ audio' 'tab-containing filename is parsed without breaking internal fields'
ok 'tab filename robustness'

env NO_COLOR=1 "$SIZES" -r --max-files 1 "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'partial' 'max-files marks output as partial'
ok '--max-files'

env NO_COLOR=1 "$SIZES" -r -x "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'one filesystem' 'one-file-system mode is shown in heading'
ok '--one-file-system'

SIZES_DEBUG_TIMING=1 "$SIZES" -r --format tsv "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$ERR" 'sizes: timing total=[0-9]+s' 'debug timing writes total timing to stderr'
ok 'SIZES_DEBUG_TIMING'



env NO_COLOR=1 "$SIZES" -r --top-dirs "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'top directories' 'top-dirs prints heading'
assert_contains "$OUT" '\./sub' 'top-dirs includes nested parent directory'
ok '--top-dirs'

env NO_COLOR=1 "$SIZES" -r --top-dirs mp4 "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'top directories for mp4' 'top-dirs extension filter prints heading'
assert_contains "$OUT" 'MP4' 'top-dirs extension filter keeps MP4 files'
ok '--top-dirs EXT'

env NO_COLOR=1 "$SIZES" -r --by-dir "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'by directory' 'by-dir prints heading'
assert_contains "$OUT" '\./sub' 'by-dir includes immediate child directory'
ok '--by-dir'

SAVE_JSON="$TEST_ROOT/report.json"
"$SIZES" -r --save "$SAVE_JSON" "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$SAVE_JSON" '^\{' 'save infers json format from extension'
assert_contains "$SAVE_JSON" '"rows": \[' 'saved json includes rows'
ok '--save'

FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/fzf" <<'FAKEFZF'
#!/usr/bin/env sh
if [ "${FZF_ARGS_LOG:-}" != "" ]; then
    printf '%s\n' "$*" >>"$FZF_ARGS_LOG"
fi
state=${FZF_STATE_FILE:-/tmp/sizes-fake-fzf-state}
n=0
[ -f "$state" ] && n=$(cat "$state")
n=$((n + 1))
printf '%s\n' "$n" >"$state"
case "$n" in
    1|2|3) sed -n '1p' ;;
    4) sed -n '8p' ;;
    *) exit 130 ;;
esac
FAKEFZF
chmod +x "$FAKE_BIN/fzf"

FZF_ARGS_LOG="$TEST_ROOT/fzf-args.log"
FZF_STATE_FILE="$TEST_ROOT/fzf-state"
env NO_COLOR=1 FZF_ARGS_LOG="$FZF_ARGS_LOG" FZF_STATE_FILE="$FZF_STATE_FILE" PATH="$FAKE_BIN:$PATH" "$SIZES" -r --interactive --no-progress "$SAMPLE" >"$OUT" 2>"$ERR"
assert_contains "$OUT" 'sizes — selected file' 'interactive mode lets users select an individual file'
assert_contains "$OUT" 'junk\.mp4|video\.mp4' 'interactive file browser prints selected file path'
assert_contains "$FZF_ARGS_LOG" '--layout=reverse' 'interactive mode keeps headers at the top'
assert_not_contains "$FZF_ARGS_LOG" '--layout=reverse-list' 'interactive mode should not put headers at the bottom'
assert_contains "$FZF_ARGS_LOG" 'preview-down' 'interactive mode binds preview scrolling'
assert_contains "$FZF_ARGS_LOG" 'sizes › main' 'interactive mode starts with a breadcrumbed mode menu'
assert_contains "$FZF_ARGS_LOG" 'sizes › extensions' 'interactive mode opens the extension browser'
assert_contains "$FZF_ARGS_LOG" 'sizes › files' 'interactive mode opens a selectable file browser'
assert_contains "$FZF_ARGS_LOG" 'ctrl-o:execute-silent' 'interactive file browser can open selected files'
assert_contains "$FZF_ARGS_LOG" 'ctrl-p:execute-silent' 'interactive file browser can open parent folders'
assert_contains "$FZF_ARGS_LOG" 'ctrl-y:execute-silent' 'interactive file browser can copy paths'
assert_contains "$FZF_ARGS_LOG" '--multi' 'interactive file browser supports multi-select'
assert_contains "$FZF_ARGS_LOG" 'ctrl-b:abort' 'interactive mode supports back navigation'
assert_contains "$FZF_ARGS_LOG" 'ctrl-q:execute-silent' 'interactive mode supports global quit'
assert_contains "$FZF_ARGS_LOG" 'Ctrl-R refresh' 'interactive mode exposes refresh/rescan'
assert_contains "$FZF_ARGS_LOG" 'sizes › file › action' 'interactive file browser opens an action menu'
assert_contains "$FZF_ARGS_LOG" 'Selected:' 'interactive action menu displays the selected item'
assert_contains "$FZF_ARGS_LOG" 'cat .*/sizes-file-action-item' 'interactive action menu previews selected item details'
assert_contains "$FZF_ARGS_LOG" 'right:(45|55)%:wrap|down:45%:wrap' 'interactive preview is terminal-size aware'
assert_contains "$FZF_ARGS_LOG" 'ctrl-/:toggle-preview' 'interactive mode can toggle previews'
assert_contains "$FZF_ARGS_LOG" 'ctrl-l' 'interactive mode exposes full-path reveal'
grep -q 'Copy quoted path' "$SIZES" || fail 'interactive action menu can copy quoted paths'
grep -q 'Open with' "$SIZES" || fail 'interactive action menu exposes Open with'
ok '--interactive'

FZF_ARGS_LOG="$TEST_ROOT/fzf-args-no-preview.log"
FZF_STATE_FILE="$TEST_ROOT/fzf-state-no-preview"
env NO_COLOR=1 FZF_ARGS_LOG="$FZF_ARGS_LOG" FZF_STATE_FILE="$FZF_STATE_FILE" PATH="$FAKE_BIN:$PATH" "$SIZES" -r --interactive --interactive-no-preview --no-progress "$SAMPLE" >"$OUT" 2>"$ERR" || true
assert_contains "$FZF_ARGS_LOG" 'hidden' 'interactive-no-preview starts preview hidden'
ok '--interactive-no-preview'

printf '\n%d tests passed\n' "$pass"
