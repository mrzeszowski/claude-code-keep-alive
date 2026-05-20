# README Hero Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hero layout to README.md — centred title + tagline, 4 shields.io badges, and a hand-crafted SVG terminal demo — while keeping all existing prose untouched.

**Architecture:** Two files change: `docs/demo.svg` (new hand-crafted SVG asset) and `README.md` (hero block inserted above `## Install`; all sections below unchanged). No logic changes; no script or test edits.

**Tech Stack:** GitHub Markdown, SVG 1.1, shields.io badge URLs.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `docs/demo.svg` | Create | Terminal screenshot SVG asset |
| `README.md` | Modify | Insert hero block above `## Install` |

---

### Task 1: Create the SVG terminal demo

**Files:**
- Create: `docs/demo.svg`

The SVG shows a 3-command session using the exact strings printed by `bin/keep-alive`:

| Command | Output |
|---|---|
| `/keep-alive:busy` | `💤 Busy mode — idle, waiting for next prompt.` |
| `/keep-alive:on 2h` | `☕ Keep-alive on (timed) — machine won't sleep.` |
| `/keep-alive:off` | `✔  Keep-alive off — machine can sleep normally.` |

(No automated tests — this is a static visual asset. Verification is visual, in Task 3.)

- [ ] **Step 1: Write `docs/demo.svg`**

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 620 220" width="620">
  <defs>
    <style>
      text { font-family: 'SF Mono', Menlo, 'Courier New', monospace; font-size: 13px; }
    </style>
  </defs>

  <!-- window background -->
  <rect width="620" height="220" rx="8" fill="#0d1117"/>

  <!-- chrome bar -->
  <rect width="620" height="36" rx="8" fill="#161b22"/>
  <rect y="20" width="620" height="16" fill="#161b22"/>

  <!-- traffic lights -->
  <circle cx="20" cy="18" r="6" fill="#ff5f57"/>
  <circle cx="40" cy="18" r="6" fill="#febc2e"/>
  <circle cx="60" cy="18" r="6" fill="#28c840"/>

  <!-- window title -->
  <text x="310" y="23" text-anchor="middle" font-size="12" fill="#8b949e">Claude Code</text>

  <!-- command 1 -->
  <text x="24" y="64" fill="#8b949e">❯</text>
  <text x="42" y="64" fill="#c9d1d9">/keep-alive:busy</text>
  <text x="24" y="84" fill="#d29922">💤 Busy mode — idle, waiting for next prompt.</text>

  <!-- command 2 -->
  <text x="24" y="112" fill="#8b949e">❯</text>
  <text x="42" y="112" fill="#c9d1d9">/keep-alive:on 2h</text>
  <text x="24" y="132" fill="#3fb950">☕ Keep-alive on (timed) — machine won't sleep.</text>

  <!-- command 3 -->
  <text x="24" y="160" fill="#8b949e">❯</text>
  <text x="42" y="160" fill="#c9d1d9">/keep-alive:off</text>
  <text x="24" y="180" fill="#8b949e">✔  Keep-alive off — machine can sleep normally.</text>

  <!-- cursor -->
  <rect x="24" y="196" width="8" height="14" fill="#c9d1d9" opacity="0.6"/>
</svg>
```

- [ ] **Step 2: Verify SVG is well-formed**

```bash
xmllint --noout docs/demo.svg && echo "OK"
```

Expected: `OK` (xmllint available on macOS via `brew install libxml2`; on Linux it's usually pre-installed).

If xmllint is unavailable, open `docs/demo.svg` directly in a browser — a broken SVG shows a blank or errored frame.

- [ ] **Step 3: Preview the SVG in a browser**

```bash
open docs/demo.svg        # macOS
# or: xdg-open docs/demo.svg  # Linux
```

Check: dark background, macOS traffic-light chrome, 3 command pairs visible, correct colours (amber for busy, green for on, grey for off).

- [ ] **Step 4: Commit**

```bash
git add docs/demo.svg
git commit -m "feat: add SVG terminal demo for README hero"
```

---

### Task 2: Rewrite README.md with hero layout

**Files:**
- Modify: `README.md`

Replace the entire file. Every section below `## Install` is kept verbatim; only the top changes.

- [ ] **Step 1: Write the new README.md**

Replace the full contents of `README.md` with:

````markdown
<div align="center">

# ☕ claude-code-keep-alive

> Keep your machine awake while Claude works.

[![CI](https://img.shields.io/github/actions/workflow/status/mrzeszowski/claude-code-keep-alive/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/mrzeszowski/claude-code-keep-alive/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/mrzeszowski/claude-code-keep-alive?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mrzeszowski/claude-code-keep-alive?style=flat-square)](https://github.com/mrzeszowski/claude-code-keep-alive/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Linux-6e40c9?style=flat-square)](#how-it-works)

<img src="docs/demo.svg" alt="demo" width="600">

</div>

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin that prevents your machine from sleeping during long Claude Code sessions. Inspired by GitHub Copilot CLI's `/keep-alive` command.

## Install

Inside a Claude Code session:

```text
/plugin marketplace add mrzeszowski/claude-code-keep-alive
/plugin install keep-alive@claude-code-keep-alive
/reload-plugins
```

That's it. The plugin's four slash commands are now available under the `/keep-alive:` namespace.

## Usage

| Command | What it does |
| --- | --- |
| `/keep-alive:status` | Show current state. |
| `/keep-alive:on` | Inhibit sleep until you turn it off. |
| `/keep-alive:on 30m` | Inhibit sleep for 30 minutes. (`m`, `h`, `d` suffixes; bare number = minutes.) |
| `/keep-alive:off` | Release the inhibitor. |
| `/keep-alive:busy` | Inhibit sleep only while Claude is actively processing. Idle time is allowed to sleep. |

The `keep-alive:` prefix is the plugin namespace — every Claude Code plugin's commands are prefixed by the plugin's name to avoid collisions across plugins.

## How it works

- **macOS:** spawns a detached `caffeinate -dis` process.
- **Linux (systemd):** spawns a detached `systemd-inhibit --what=idle:sleep ... sleep` process.
- **Windows:** not yet supported in v0.1; contributions welcome.

State lives in `${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-keep-alive/state` — a single global file shared across all your Claude Code sessions on this machine. `flock` (or a `mkdir`-based fallback on macOS) serializes concurrent invocations.

`busy` mode is driven by two hooks shipped with the plugin: `UserPromptSubmit` starts the inhibitor, `Stop` tears it down. Both are no-ops unless you've explicitly opted in with `/keep-alive:busy`.

## Updating

```text
/plugin update keep-alive@claude-code-keep-alive
```

You only receive updates when the plugin's `version` field is bumped (not on every commit).

## Uninstall

```text
/plugin uninstall keep-alive@claude-code-keep-alive
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "feat: README hero — badges, SVG demo, centred title"
```

---

### Task 3: Visual verification

No code changes — this task confirms the README renders correctly on GitHub.

- [ ] **Step 1: Push the branch and open the GitHub preview**

```bash
git push -u origin feat/cool-output-messages
```

Then open `https://github.com/mrzeszowski/claude-code-keep-alive/blob/feat/cool-output-messages/README.md` in a browser.

Check in **both light and dark mode** (GitHub profile → Appearance):

- [ ] Title `☕ claude-code-keep-alive` is centred
- [ ] Tagline blockquote is centred
- [ ] All 4 badges render and link correctly
- [ ] SVG demo loads (not a broken image icon)
- [ ] SVG text is legible in both themes
- [ ] `## Install` through `## License` sections are intact and unchanged

- [ ] **Step 2: Fix any rendering issues**

Common issues and fixes:

| Symptom | Likely cause | Fix |
|---|---|---|
| Badges show "invalid" | Wrong repo slug in URL | Check `mrzeszowski/claude-code-keep-alive` in badge URLs |
| Release badge shows "no releases" | No published GitHub release yet | Expected — badge will populate after first release |
| SVG not loading | Path wrong or file not committed | Confirm `docs/demo.svg` is tracked: `git ls-files docs/demo.svg` |
| Text garbled in SVG | Font fallback issue | Acceptable — system fonts vary; the fallback chain covers most OSes |
