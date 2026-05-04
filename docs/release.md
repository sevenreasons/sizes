# Release notes

## v0.5.0

- Add `--interactive` / `-i` for an `fzf`-powered extension browser.
- Add a preview pane showing the largest files for the selected extension.
- Print a selected-extension detail table after pressing Enter.
- Respect existing filters such as `--include`, `--exclude`, `--type`, `--limit`, `--min-size`, and `--min-share` in interactive mode.
- Add `SIZES_FZF` for overriding the `fzf` command.

## Release checklist

```sh
sh tests/run.sh
shellcheck sizes.sh sizes tests/run.sh
git add -A
git commit -m "Add fzf interactive browser for v0.5.0"
git tag -f v0.5.0
git push origin master --tags
```
