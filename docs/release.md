# Release checklist

```sh
sh tests/run.sh
shellcheck sizes.sh sizes tests/run.sh
git tag v0.3.1
git push origin master --tags
```

## v0.3.1 notes

- Performance and robustness patch: include pushdown, streamed top-files, one-filesystem scans, max-files safety, unit-separator records, cached classification, and debug timing.
