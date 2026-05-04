# Release notes

## v0.5.1

- Improve `--interactive` with aligned colored rows that match the main table style.
- Keep the extension list sorted and searchable in `fzf`.
- Add `Ctrl-F` preview for top files and `Ctrl-D` preview for top directories.
- Print both top files and top directories after accepting a selected extension.

## Release checklist

```sh
sh tests/run.sh
shellcheck sizes.sh sizes tests/run.sh
git add -A
git commit -m "Improve interactive browser for v0.5.1"
git tag -f v0.5.1
git push origin master --tags
```
