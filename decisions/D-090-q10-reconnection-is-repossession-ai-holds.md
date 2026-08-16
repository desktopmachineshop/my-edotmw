### D-090 · 2026-08-14 · Accepted — Q10: reconnection is repossession; AI holds the seat; rejoin is also the desync repair

**Decision:** a human's mid-match disconnect no longer wipes their army
(superseding D-033's wipe-on-disconnect for humans; explicit leave via
D-075 also hands off rather than wiping). Instead:

1. **The seat passes to an AI immediately.** D-051 built exactly the
   right object: an AI player is a client without a socket, held to
   every rule a human is. Takeover is seating one on the abandoned
   army's curves — no grace-period limbo where 19 players fight a
   statue.
2. **Reconnection is repossession.** A returning player (identified by
   **SteamID, not connection** — the per-connection ownership cache was
   already this project's bug once, D-038's amendment) reclaims the
   seat from the AI at any point while the match runs. There is no
   timeout after which return is refused: the AI holding the seat IS
   the grace mechanism, indefinitely.
3. **Rejoin is architecturally cheap, and that is not luck.** A
   rejoining client is a fresh join: D-025's reveal semantics already
   define how any client learns current state — horizon-clipped curves,
   sent fresh, no synthetic catch-up. The one non-obvious obligation:
   persistent-explored building fog must be replayed as the
   **ever-revealed set** on rejoin, exactly the distinction its hash
   rule already warns about.
4. **Desync recovery is the same door.** Q10's second half gets the
   same answer: the client already computes state hashes continuously;
   on mismatch, the recovery policy is **drop and rejoin through the
   repossession path** — fresh curves rebuild the world from truth.
   No incremental repair protocol; rejoin *is* the repair, and it is
   cheap for the same D-025 reasons. (Server-side, a desync report is
   logged with the replay per D-016 — forensics first, the M1 lesson.)

**Rationale:** every alternative builds new machinery; this composes
three things that exist (AI clients, reveal semantics, state hashes)
and one thing M8 needs anyway (SteamID identity). For D-056's eventual
1–2 hour matches, wipe-on-disconnect would be brutal to the
disconnected player's *team* (D-050 shared vision makes armies
interdependent) — the AI holding the line is what keeps one dropped
connection from deciding a team match.

**Rejected alternatives:** *grace-period pause* (PA-style — freezes 19
players for one); *wipe after a timeout* (punishes the team, and the
timeout constant has no defensible value); *incremental desync repair*
(a diff protocol against curve state — large, and rejoin already
achieves the same end).

**Consequences:** the join handshake carries SteamID → seat binding
(wire change, D-094 criterion 3's version handshake is the natural
place); `match_state.gd`'s elimination definition needs one amendment —
a seat is abandoned only if its AI is also dead; D-051's AI must cope
with inheriting any mid-match position, which `ai-ladder` cannot fully
exercise (it never inherits) — a scripted takeover scenario is D-094
criterion 6's job.

**Revisit trigger:** if AI-holds-indefinitely is abused in practice
(a losing player "AFKs behind a competent AI"), add a forfeit vote or
an idle-seat rule — a social-rules patch, not a rewrite of this shape.

---
