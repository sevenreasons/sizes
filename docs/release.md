# Release notes

## v0.4.0

- Add `--top-dirs [EXT]` for directory drilldown.
- Add `--by-dir` for immediate directory summaries.
- Improve JSON output with metadata and structured rows.
- Add `--save PATH` with extension-based format inference.
- Expand extension/type detection.

## Release checklist

```sh
sh tests/run.sh
shellcheck sizes.sh sizes tests/run.sh
git add -A
git commit -m "Add directory drilldown and JSON reports for v0.4.0"
git tag -f v0.4.0
git push origin master --tags
```
