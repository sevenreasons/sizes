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
    haystack=$1
    needle=$2
    name=$3
    printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null || fail "$name"
}

assert_not_contains_ansi() {
    file=$1
    name=$2
    if grep -q "$(printf '\033')" "$file"; then
        fail "$name"
    fi
}

mkdir -p "$TEST_ROOT/sample/sub" "$TEST_ROOT/empty"
printf 'abc' > "$TEST_ROOT/sample/a.txt"
printf 'defgh' > "$TEST_ROOT/sample/b.jpg"
printf 'ijklmno' > "$TEST_ROOT/sample/c.jpeg"
printf 'nested' > "$TEST_ROOT/sample/sub/d.json"
printf 'hidden' > "$TEST_ROOT/sample/.hidden"

version=$("$SIZES" --version)
[ "$version" = "sizes 0.1.0" ] || fail "--version"
ok "--version"

wrapper_version=$("$SIZES_WRAPPER" --version)
[ "$wrapper_version" = "sizes 0.1.0" ] || fail "root wrapper --version"
ok "root wrapper"

out=$(env SIZES_FIND=find "$SIZES" --no-color "$TEST_ROOT/sample")
assert_contains "$out" "TXT" "non-recursive should include TXT"
assert_contains "$out" "JPG" "non-recursive should include JPG"
if printf '%s' "$out" | grep -F "JSON" >/dev/null; then
    fail "non-recursive default should not include nested JSON"
fi
ok "non-recursive default"

out=$("$SIZES" --no-color -r "$TEST_ROOT/sample")
assert_contains "$out" "JSON" "recursive should include nested JSON"
ok "recursive scan"

out=$("$SIZES" --no-color -e "$TEST_ROOT/sample")
assert_contains "$out" "JPEG" "exact mode should keep JPEG"
ok "exact mode"

out=$("$SIZES" --no-color -r -n 2 "$TEST_ROOT/sample")
assert_contains "$out" "OTHER" "limit mode should include OTHER"
ok "limit mode"

out=$("$SIZES" --no-color "$TEST_ROOT/empty")
assert_contains "$out" "NO_FILES" "empty directory should show NO_FILES"
ok "empty directory"

"$SIZES" --no-color "$TEST_ROOT/sample" > "$TEST_ROOT/no_color.txt"
assert_not_contains_ansi "$TEST_ROOT/no_color.txt" "--no-color should produce no ANSI"
ok "--no-color"

NO_COLOR=1 "$SIZES" "$TEST_ROOT/sample" > "$TEST_ROOT/no_color_env.txt"
assert_not_contains_ansi "$TEST_ROOT/no_color_env.txt" "NO_COLOR should produce no ANSI"
ok "NO_COLOR"

CLICOLOR=0 "$SIZES" "$TEST_ROOT/sample" > "$TEST_ROOT/clicolor_env.txt"
assert_not_contains_ansi "$TEST_ROOT/clicolor_env.txt" "CLICOLOR=0 should produce no ANSI"
ok "CLICOLOR=0"

printf '\n%d tests passed\n' "$pass"
