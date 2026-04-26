---
name: changelog
description: Generate a markdown changelog from git commits between two refs. Groups commits by conventional-commit prefix (Features / Fixes / Internal). Use as `/changelog <range>` (e.g. `/changelog v1.4.0..HEAD`, or `/changelog v1.3.0..v1.4.0`). Output is ready to paste into a GitHub Release body.
disable-model-invocation: true
---

# changelog

Produce a markdown changelog from git history. Mechanical grouping by conventional-commit prefix — for a more curated, user-facing version use the `changelog-writer` subagent instead.

## Argument

A git revision range. Common forms:
- `v1.4.0..HEAD` — everything since the last tag
- `v1.3.0..v1.4.0` — what shipped in 1.4.0
- `HEAD~10..HEAD` — last 10 commits

If no argument is given:
1. Run `git describe --tags --abbrev=0` to find the latest tag.
2. Default the range to `<latest-tag>..HEAD`.
3. If no tags exist, ask the user for an explicit range.

## Steps

1. **Verify clean tree.** If `git status --porcelain` is non-empty, warn — uncommitted changes won't appear.

2. **Collect commits.**
   `git log <range> --pretty=format:'%h%x09%s' --no-merges`

3. **Bucket by prefix.** Match each subject against:
   - `Features` ← `feat:` / `feat(*):`
   - `Fixes` ← `fix:` / `fix(*):`
   - `Internal` ← `chore:`, `refactor:`, `ci:`, `docs:`, `test:`, `style:`, `build:`, `perf:` (with or without scope)
   - `Other` ← anything else (legacy commits without conventional prefix)

   Within each bucket, preserve commit order (oldest first).

4. **Format output:**

   ```markdown
   ## What's changed in <version-or-range>

   ### Features
   - <subject without prefix> (<short-sha>)

   ### Fixes
   - <subject without prefix> (<short-sha>)

   ### Internal
   - <subject without prefix> (<short-sha>)
   ```

   Skip empty sections entirely. If `Other` is non-empty, surface it after `Internal` so the user can hand-classify.

5. **Compare URL.** If the range looks like `<tag>..<tag-or-HEAD>`, append:

   `**Full diff:** https://github.com/giraybatiturk/Force-Quit-X/compare/<from>...<to>`

6. **Print to stdout.** Don't write to a file — the user pipes it where needed (often `gh release create --notes "$(...)"` or pasted into the release UI).

## Example output

```markdown
## What's changed in v1.4.0

### Fixes
- harden AppDelegate (Carbon teardown, error surfacing, timeouts) (089fa02)

### Internal
- fix invalid macOS deployment target (26.4 → 15.0) (50bef28)
- add Claude Code config, swift-format style, and gitignore (85fd656)
- add GitHub Actions workflow (build + swift-format lint) (3c5ab04)

**Full diff:** https://github.com/giraybatiturk/Force-Quit-X/compare/v1.3.0...v1.4.0
```
