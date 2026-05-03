# Release checklist

```sh
sh tests/run.sh
shellcheck sizes.sh sizes tests/run.sh
git tag v0.2.0
git push origin master --tags
```
