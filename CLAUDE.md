# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status: v0.1.0 ready

Everything from §5 of the design spec is built and CI is green. Working branch is `feat/v0.1.0` (merges to `main` for release). Design spec: `docs/superpowers/specs/2026-05-17-claude-code-keep-alive-design.md`.

Lint and test commands:
- **Lint:** `shellcheck -s sh bin/keep-alive` (must be clean)
- **Tests:** `bats tests/` — 28 tests, pass on macOS and Ubuntu

## What the plugin does

A Claude Code plugin that prevents the user's machine from sleeping during a session. It ports the user-facing surface of GitHub Copilot CLI's `/keep-alive` (subcommands `on`, `off`, `busy`, duration), namespaced as `/keep-alive:on`, `/keep-alive:off`, `/keep-alive:busy`, `/keep-alive:status`. Spec §1–3.

## Architecture (the non-obvious parts)

Three pieces, and the interactions between them matter:

1. **Slash command files** are intentionally minimal — frontmatter + one line telling Claude to run `keep-alive <verb> $ARGUMENTS` via the Bash tool and print stdout/stderr verbatim. `allowed-tools` is locked to `["Bash"]` to prevent the LLM from interpreting the command. Don't add logic here.
2. **`bin/keep-alive`** is a POSIX-sh script (target ~150 lines). All real work — argument parsing, platform detection, state, inhibitor lifecycle — lives here. Added to the Bash tool's `PATH` while the plugin is enabled.
3. **`hooks/hooks.json`** registers `UserPromptSubmit` and `Stop` hooks that invoke `keep-alive --busy-event=start|stop` in the background. They fire in **every** Claude Code session whenever the plugin is enabled, not only when the user invoked `/keep-alive`. They are no-ops unless the state file says `mode=busy`. This is what makes `busy` mode work without polling.

Concretely, "no-op unless mode=busy" is a load-bearing invariant: if you ever change the hooks to do work unconditionally, you'll add a `flock` + JSON write to every prompt across every session for every user.

### State and process lifecycle

- Single global state file at `${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-keep-alive/state`. Plain `key="value"` shell-sourceable format (not JSON). No per-session isolation (matches Copilot CLI).
- All reads/writes serialized via `flock` on a sibling `state.lock`. When `flock` is absent the fallback is a `mkdir`-based lock at `state.lock.d`.
- The inhibitor is spawned **detached** (`nohup <cmd> </dev/null >/dev/null 2>&1 &`) so it survives the shell that started it *and* survives across Claude Code sessions. Do not foreground it.
- Saved PIDs are verified with `kill -0` before being trusted; stale PIDs are cleaned silently. Don't assume `pid` in state means the process is alive.
- Duration mode uses the inhibitor binary's own timer: macOS runs `caffeinate -t $SECONDS -dis`; Linux runs `systemd-inhibit ... sleep $SECONDS`. The inhibit lock is held for as long as the child process runs — no wrapper or watchdog needed.
- Killing the process cleanly releases `systemd-inhibit`'s lock; tearing down by PID works for both platforms. Spec §6.4.

### Platform support (v0.1)

- macOS → `caffeinate -dis` (duration: `caffeinate -t $SECONDS -dis`)
- Linux → `systemd-inhibit --what=idle:sleep --who=claude-code-keep-alive --why="..." sleep $SECONDS` (`sleep 99999999` for indefinite — `sleep infinity` is GNU-only and was dropped for POSIX portability)
- Windows / other → print "not yet supported" to stderr, exit 2. Windows support is explicitly out of v0.1 (spec §14).

Exit codes: `0` success, `1` invalid args, `2` unsupported platform, `3` missing inhibitor binary, `4` state corruption. Slash commands surface these to the user verbatim.

## Distribution model

The repo doubles as a single-plugin marketplace. Both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` live in the same repo, with the marketplace's plugin entry using `"source": "./"`. The marketplace `name` field is `"claude-code-keep-alive"` — install command is `/plugin install keep-alive@claude-code-keep-alive`. The plugin author email in manifests is `mrzeszowski@outlook.com`. Spec §6.1–6.2 and §8.

Plugin updates are gated by the `version` field, not by git tags. The release workflow (§11.2) exists to enforce that tag `vX.Y.Z` matches `plugin.json` `version` `X.Y.Z` so the two never drift.

## Tests + CI

- `bats tests/` — 28 tests, pass on macOS and Ubuntu.
- `shellcheck -s sh bin/keep-alive` — must be clean.
- `KEEP_ALIVE_STATE_DIR` overrides the state-dir location; tests use this to avoid touching `$HOME/.cache`.
- `KEEP_ALIVE_PLATFORM` overrides `detect_platform`'s output. Use this as a test escape hatch when a missing-binary test must run on macOS where `systemd-inhibit` cannot be removed from `PATH`.

## Local development workflow

Iterate with `claude --plugin-dir .` from this repo, then `/reload-plugins` after edits. A `--plugin-dir` plugin shadows an installed marketplace copy with the same name for that session, so you can hack without uninstalling.
