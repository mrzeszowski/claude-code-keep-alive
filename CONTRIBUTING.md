# Contributing

Thanks for considering a contribution. The plugin is small (~200 lines of POSIX sh plus four 5-line slash commands) and intentionally low-magic.

## Local development

```bash
git clone git@github.com:mrzeszowski/claude-code-keep-alive.git
cd claude-code-keep-alive
claude --plugin-dir .
```

Then, inside the Claude Code session:

```text
/reload-plugins
/keep-alive:status
```

After making changes, run `/reload-plugins` again — no need to restart Claude Code.

## Running tests

Install [bats-core](https://bats-core.readthedocs.io/) and [shellcheck](https://www.shellcheck.net/):

- macOS: `brew install bats-core shellcheck`
- Ubuntu: `sudo apt install bats shellcheck`

Then:

```bash
shellcheck -s sh bin/keep-alive
bats tests/
```

Tests use mock inhibitors under `tests/mocks/` so they're safe to run repeatedly. CI runs the same suite on `ubuntu-latest` and `macos-latest`.

## Release process

1. Update `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
2. Add a `CHANGELOG.md` entry.
3. Open a PR titled `release: vX.Y.Z`; merge after CI passes.
4. Tag the merged commit: `git tag vX.Y.Z && git push origin vX.Y.Z`.
5. The `release.yml` workflow creates a GitHub release with auto-generated notes, after verifying the tag matches `plugin.json`'s version.

Users on the marketplace receive the update when they run `/plugin update keep-alive@claude-code-keep-alive`.
