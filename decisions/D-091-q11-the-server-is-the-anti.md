### D-091 · 2026-08-14 · Accepted — Q11: the server IS the anti-cheat, and the host is trusted, stated plainly

**Decision:** no kernel anti-cheat, no third-party client-side
anti-cheat, VAC at Steam's defaults only. The posture is the
architecture, which was built for this from D-002 on:

- **A client cannot assert state** — it sends orders; the server
  validates every one through the shared helper (M3), and refuses what
  the player doesn't own.
- **A client cannot know what its player shouldn't** — fog is curve
  *gating* (D-003/D-004/D-025): concealed state never reaches the wire.
  A maphack reads memory that isn't there.
- **A modified client changes only its own picture** — soldier
  positions are client-derived cosmetics (D-006, one-way by
  construction).

The two residual surfaces, named so nobody rediscovers them: what a
horizon-clipped curve still leaks (D-003's own note — intent within the
horizon), and **the host under D-088** — whoever hosts holds the whole
truth and the authority, so a modified host is omniscient and
unaccountable. **Accepted for unranked/friends play and documented as
such; ranked or competitive play requires official dedicated servers
and is explicitly gated on D-088's later rung.** Replays (D-016) are
the accountability tool that exists today: byte-identical to the wire,
they make an accusation checkable after the fact.

**Rejected alternatives:** kernel/client anti-cheat (an arms race this
project cannot staff, aimed at the one surface — the client — the
architecture already made low-value to cheat); trusting no host and
shipping dedicated-only (rejected by D-088's owner call, and unranked
friends-lobby play doesn't warrant it).

**Consequences:** none in code for M8 beyond what D-088/D-090 already
require. The word "ranked" appearing anywhere in a future milestone is
this entry's tripwire.

**Revisit trigger:** ranked play; or evidence of host cheating being a
practical problem in unranked lobbies rather than a theoretical one.

---
