### D-092 · 2026-08-14 · Accepted — Q13: no mid-match saves; reconnection and replays are what the need decomposes into

**Decision (the owner's call, 2026-08-14):** M8 ships no save/resume.
The realistic failure a long multiplayer match faces is *a player
dropping* — D-090 covers that with AI takeover and repossession. The
other thing "saves" usually means — reviewing a finished match — has
been free since M1: replays are the curve log (D-016). What remains is
genuinely "suspend a live multiplayer session and resurrect it later",
which requires state serialization with versioning plus a resume
ceremony every participant must attend, for an event (all N players
agree to stop and all N return later) that lobby-discovered matches
essentially never produce.

**Rejected alternatives:** server-side session snapshot (feasible —
packed arrays serialize cleanly — but the cost is the ceremony and the
versioning, not the bytes); client-side saves (meaningless in an
authoritative-server game).

**Revisit trigger:** two named. (1) M9's real 1–2 hour matches showing
abandonment pain that repossession doesn't cover — measured by
playtest, not assumed. (2) A single-player or skirmish-vs-AI mode
becoming a product surface — there the ceremony collapses (one human,
server in-process per D-088) and saves become cheap enough to justify
themselves.

---
