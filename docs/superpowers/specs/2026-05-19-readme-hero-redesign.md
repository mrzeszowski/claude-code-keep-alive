# README Hero Redesign — Design Spec

**Date:** 2026-05-19
**Branch:** feat/cool-output-messages (or new branch)
**Scope:** README.md only — content unchanged, layout and visual elements added

---

## Goal

Modernise the README with a hero layout, badges, and an SVG terminal demo. All existing prose is preserved; we're adding structure and visual elements on top.

---

## Design Decisions

### Style: Showcase / Hero

Centred header with tagline, badge row, and SVG demo above the Install section. Communicates project personality before the user reads a word of prose.

### Header

```markdown
# ☕ claude-code-keep-alive

> Keep your machine awake while Claude works.
```

Emoji in the H1 title. Tagline as a blockquote (`>`). Both centred via an HTML `<div align="center">` wrapper — the only way to centre content in GitHub Markdown.

### Badge row

Four badges, centred, `flat-square` style from shields.io:

| Badge | Source |
|---|---|
| CI | `github/actions/workflow/status` — workflow `ci.yml`, branch `main` |
| License | `github/license` |
| Release | `github/v/release` with `include_prereleases` off |
| Platform | Static label badge: `platform-macOS · Linux` |

All four live inside the same `<div align="center">` as the title and tagline.

### SVG terminal demo

A terminal screenshot saved as `docs/demo.svg`, embedded with:

```markdown
<div align="center">
  <img src="docs/demo.svg" alt="demo" width="600">
</div>
```

**Content of the demo** — a 3-command session showing the three most useful modes:

```
❯ /keep-alive:on 2h
☕ Sleep inhibited for 2 h (until 21:45)

❯ /keep-alive:status
☕ on · 1 h 47 m left

❯ /keep-alive:off
💤 Sleep restored
```

**Generation:** Hand-crafted SVG — the output is stable and short enough to write directly. Committed to `docs/demo.svg`. No external tooling or hosting required.

Style: dark background (`#0d1117`), monospace font (`'SF Mono', Menlo, monospace`), macOS-style window chrome (traffic-light dots), `#3fb950` for success output, `#8b949e` for the prompt symbol.

### Section order (action-first)

1. Hero (title + tagline + badges + demo) — above any `##` heading
2. `## Install`
3. `## Usage`
4. `## How it works`
5. `## Updating`
6. `## Uninstall`
7. `## Contributing`
8. `## License`

Section order is unchanged from the current README — Install, Usage, How it works, Updating, Uninstall, Contributing, License. The only structural addition is the hero block inserted above `## Install`.

---

## Files Changed

| File | Change |
|---|---|
| `README.md` | Full rewrite of structure; prose content preserved |
| `docs/demo.svg` | New file — SVG terminal screenshot |
| `.gitignore` | Add `.superpowers/` (already done) |

---

## Out of Scope

- Animated GIF / asciinema — SVG is sufficient and zero-maintenance
- Table of Contents — section count is small enough to not need one
- Windows platform badge — not supported in v0.1
- Any changes to `bin/keep-alive`, commands, hooks, or tests
