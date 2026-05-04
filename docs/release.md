# Release notes

## v0.5.3

- Make `--interactive` a real drilldown flow.
- Extension rows are still searchable, colored, aligned, and size-sorted.
- `Enter` / `Ctrl-F` opens a selectable file browser for the chosen extension.
- `Ctrl-D` opens a selectable directory browser for the chosen extension.
- File and directory browsers include preview panes and selected-item output.

## Release checklist

```sh
sh tests/run.sh
shellcheck sizes.sh sizes tests/run.sh
git add -A
git commit -m "Add interactive file and directory drilldown for v0.5.3"
git tag -f v0.5.3
git push origin master --tags
```
