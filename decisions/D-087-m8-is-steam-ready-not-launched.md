### D-087 · 2026-08-14 · Accepted — M8 is Steam-ready, not launched; and "seamless" closed by inspection

**Decision:** M8's definition of done is **the game is a real Steam
build, proven by private playtests that reach a match entirely through
Steam** — install from a private depot branch, host, invite, play,
disconnect, rejoin. **Public launch is not M8.** Launch (store page,
pricing, marketing) waits on M9's content, because shipping a game whose
matches decide in three minutes (D-056) would earn exactly the reviews it
deserves. M8 and M9 can proceed in either order or in parallel; the
launch gate is both complete.

In scope, each with its own entry below: hosting model (D-088), what a
20-player design target obliges (D-089), reconnection (D-090), anti-cheat
posture (D-091), saves — out (D-092), the platform boundary (D-093), and
the export/upload pipeline plus exit criteria (D-094).

**Q14 is closed here, by inspection.** "Seamless" means one contiguous
wrapped map with no loading screens — and that has been true by
construction since D-008: the torus is a single simulated space, terrain
is one meshed domain drawn nine times (M3 slice 3), and nothing streams.
No streaming work exists in any milestone because none is needed. The
question only stayed open because the word was never pinned down;
recording the definition is the whole decision.

**Rejected alternatives:** *Early Access on current content* — faster
feedback, but the 3–4 minute match problem is structural (D-056 says so
explicitly) and first impressions on Steam are not revisable. *Making M8
the 1.0 launch* — that just reorders the ladder to M9-then-M8 and makes
M8 unplannable until M9's content questions settle; splitting
"Steam-ready" from "launched" keeps M8 executable now.

**Consequences:** M8 produces no public artifact — its output is a
private depot branch and a repeatable playtest loop. The discrete-GPU
bench trigger (Q15, sharpened in section 2) finally becomes reachable
through playtesters' hardware and is folded into D-094's criteria.

**Revisit trigger:** if M9 slips badly enough that an Early Access
launch on partial content starts looking better than silence, that is a
new decision against this one, not an amendment.

---
