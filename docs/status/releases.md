**Releases ship from GitHub, and the game knows when it is stale**
(`D-20260830-releases-are-a-tag-and-a-nightly-channel`, 2026-08-30). Two
pipelines on one build path — every CI step calls the same `just export`
/ `just package` a checkout runs, so local and CI cannot drift.

```
git tag v0.2.0 && git push origin v0.2.0   # THE official release act
```

- **Official** (`.github/workflows/release.yml`): a `v*` tag builds all
  three targets and publishes a GitHub Release with sha256s. The
  workflow REFUSES a tag that does not equal `project.godot`'s
  `application/config/version` — the version has one writer
  (D-20260827), so bump it first, then tag `v<that>`.
- **Nightly** (`nightly-build` job in `nightly.yml`): a rolling
  `nightly` PRERELEASE — windows-client + linux-server — published only
  when that night's `test-load` gate is green. A red gate leaves
  yesterday's build standing. Deleted and recreated nightly so the tag
  moves with the release; the asset URL stays stable.
- **The binary's version never carries a sha or date**, nightly
  included: D-081 requires two clean clones of one commit to export
  identical bytes (`build_version.gd`). Nightly identity is the release
  title and notes; mixed builds meeting each other is #179's handshake's
  job, and it already refuses with a sentence naming both.
- **The main menu checks for updates** (`update_check.gd`, all-static
  and pure; the one `HTTPRequest` lives in `client.gd`). Once per
  process, menu only — autoconnected launches never show the menu, so
  no headless harness in the estate talks to GitHub. `releases/latest`
  excludes prereleases, so the check tracks OFFICIAL tags and the
  nightly stays opt-in. Every failure path is silence, and the button
  opens the URL constructed from `UpdateCheck.REPO`, never one off the
  wire (`game_browser.gd`'s rule). `testers.md` discloses the check
  beside its no-telemetry promise.
- **Self-updating is phase 2 and deliberately absent** — the decision
  entry has the two candidate mechanisms (swap-on-restart helper, or an
  installer) and why notify-and-link is enough while the handshake stops
  a stale build from silently playing. Downloads are unsigned, so
  SmartScreen warns once per new build; the release notes say so.
- **itch.io is retired as the planned channel**; `just publish-itch`
  stays as the steamcmd rehearsal (#185), unused. When Steam arrives,
  the depot push is one more publish step beside the release upload.

**Owner actions still open:** flipping the repo public (a LICENSE
decision and a history secrets scan come first — the decision entry
names both), after which the update check lights up on its own; until
then the API 404s into designed silence and releases publish privately.
