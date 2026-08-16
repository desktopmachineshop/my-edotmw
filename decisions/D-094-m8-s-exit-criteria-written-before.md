### D-094 · 2026-08-14 · Accepted — M8's exit criteria, written before the code

**Decision:** M8 is complete when all of the following hold. Written
before any M8 code exists, per the standing rule (D-022, D-026, D-046,
D-074 — and D-085's reconstruction is the cautionary tale for skipping
it). Every new check below is subject to the observed-to-fail rule.

1. **Export:** `just export` produces a runnable Windows client build
   and a Linux headless server build from a clean clone (the latter is
   what docker already proves possible, and is the dedicated-later
   seed). Build version is stamped from one source of truth.
2. **Upload:** a `just` recipe pushes a build to a Steam depot via
   steamcmd, to a **private** branch; a fresh machine installs and runs
   it from Steam. (No store page, no public visibility — D-087.)
3. **Version handshake:** the join flow carries a protocol version and
   the SteamID seat identity (D-090); a mismatched client is refused
   loudly at join with a message a player can act on. Verified by
   connecting a deliberately version-bumped client and watching the
   refusal — this criterion exists because Steam's rolling updates make
   mixed versions routine, and today's protocol has no version field
   at all.
4. **Host flow:** a host starts a match from inside the game (server
   in-process per D-088), a second machine joins via Steam invite and
   via the lobby browser, and no participant touches an IP address or
   a router. LAN/direct-IP still works with Steam absent (D-093).
5. **Transport contract:** a real match runs over Steam sockets with
   reliable-ordered delivery, the state-hash machinery reports zero
   desyncs on it, and D-042's ordering test is extended to cover the
   Steam peer wrapper. The bots/test estate continue to run entirely
   over ENet/loopback, Steam-less.
6. **Reconnection (D-090), each leg observed to fail first:** kill a
   client mid-match → its AI takes over within a tick and plays on;
   the same human rejoins → repossesses the seat, and post-rejoin
   state hashes are clean (including the ever-revealed building-fog
   set — the known trap); a second human takes over a different
   AI-held seat mid-match (D-089's drop-in). A scripted takeover
   scenario covers the part `ai-ladder` structurally cannot (an AI
   inheriting a mid-match position it didn't build).
7. **Platform boundary (D-093):** the no-script-names-Steam test
   exists and has been observed to fail; the full unit suite passes in
   docker with no Steam present (automatic, but assert it — that is
   the fallback rule proven, not assumed).
8. **The 20-seat match (D-089):** one match, 20 seats filled — at
   least 3 remote humans over the real internet (not loopback, not
   LAN), the rest AI — through Steam networking, completing with a
   decided result or a clean cap. Bandwidth, worst tick and µs/squad
   quoted **with their counts**, per the standing rule, against
   D-020's budget and D-042's measured baseline.
9. **The discrete-GPU number (Q15's armed trigger):** `just
   bench-render` run on at least one discrete GPU — playtesters'
   machines finally make this reachable — at ship map size and squad
   count, adapter name in the output. This settles D-085 criterion
   11's caveat as a side effect.
10. **A human plays a full match end-to-end through the Steam-installed
    build** — install, lobby, match, disconnect/rejoin, finish. The
    criterion-14 lesson (D-085), applied from day one this time: this
    is the criterion nothing automated substitutes for, and M8 is
    "landed, not complete" until it is checked.

**Consequences:** criteria 3, 5 and 6 are wire-protocol work and should
land early — they are the part every other criterion sits on.
Criterion 8 is the milestone's headline and its long pole: it needs
real humans on real networks, which means the private-branch loop
(criteria 1–2) is the first thing to build, not the last.

**Revisit trigger:** any criterion found unverifiable as written gets
amended here in the open, not quietly reinterpreted — the D-043
retroactive-audit lesson.

---

> **Editorial note on D-081 through D-085, added 2026-08-11.** M7's art
> work landed under decision IDs D-063 through D-067 — but by the time it
> shipped, those IDs had already been taken by real, unrelated entries
> (D-063 is the HUD/camera-yaw decision below; D-065 is formation shape;
> D-066 is building damage scale; D-067 is squad shoving). `CLAUDE.md`
> cites the art work at the collided IDs anyway, and the only trace of
> the actual art decisions in this file was a two-line Q12 closure
> pointing at a `D-064` that was never written. A grep for style keywords
> (`vertex animation texture`, `VAT`, `gdshader`, `silhouette`, `low-poly`,
> `toon`, `atlas`) across the whole file before this note returned exactly
> two hits, both in that closure.
>
> D-081 through D-085 below reconstruct those decisions from the shipped
> code and from `CLAUDE.md`'s own M7 narrative, at fresh unused IDs, so
> this file has something to check before the next art decision is made.
> They are dated to when the work is understood to have landed (D-081's
> 2026-08-09 matches the Q12 closure's own date), not to today — but they
> were **written today**, after the fact, which is the opposite of this
> project's own rule that exit criteria (D-022, D-026) are written down
> *before* the code. D-085 in particular is reconstructed without ever
> having seen an original numbered list; where `CLAUDE.md` cites a
> specific criterion number (4, 11, 14) that number is preserved, and
> everything else is inferred from what the same section of `CLAUDE.md`
> says landed. Treat D-085 as lower-confidence than the others for that
> reason.
>
> **Renumbered again on merge, same day.** This block was first drafted
> as D-075 through D-080. Before it merged, `main` independently gained
> its own real D-075 — "leaving a match returns to the lobby, and no
> humans means no server" (below) — landing the same day this block was
> written. Rather than let a second, unrelated decision collide onto an
> ID this block had already claimed, everything here was shifted up by
> six (D-075→D-081 … D-080→D-086) at merge time. The lesson is the same
> one the rest of this note describes at one remove: picking a fresh ID
> only prevents a collision with what exists at the moment you pick it,
> not with a decision landing on `main` from a different branch in
> parallel. Check `main` immediately before merging, not only before
> writing.
