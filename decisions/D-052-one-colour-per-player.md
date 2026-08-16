### D-052 · 2026-08-02 · Accepted — one colour per player
**Decision:** Every player gets a colour from a twenty-entry palette,
keyed by SEAT INDEX, and their units and buildings wear it. `PlayerColours`
owns the palette; `ClientState.colour_of` maps a player to it.

**Rationale:** colour used to come from `UnitDef.mesh_color`, which
describes the unit TYPE — every spearman on the map was the same grey
whoever owned him. That is fine in a screenshot and useless in a battle.
The first thing a player needs to read off the screen is whose units
those are; which kind they are is second, and shape still carries it. The
unit colour survives as a 25% tint over the owner colour, so two unit
types stay distinguishable within one army without muddying whose army it
is.

**Twenty entries, and no wrap.** D-018 targets 20 concurrent players, so
the palette is exactly that long and out-of-range CLAMPS rather than
wrapping — wrapping would hand a twenty-first player an existing
player's colour in precisely the largest, most confusing match. A test
asserts the count, that every entry is distinct, and that no two are
within a small distance of each other, because "distinct" and
"distinguishable" are not the same claim.

**Keyed by seat, not player id.** Ids are not contiguous: AI seats are
numbered from 1000 (D-051), so any modulo of a player id would give
AI 1000 the same entry as player 1. There is a test for exactly that
collision.

**Derived, not sent.** The client already holds the seat list, so colour
needs no message of its own and every client agrees by construction.

**Consequences, and both were caught by looking at a picture rather than
by a check:** sending the seat list to every client made
`ClientState.in_lobby()` true forever, because it inferred "in a lobby"
from HAVING seats — the client drew the lobby over a live match while the
verdict reported terrain built, 96 soldiers and zero desyncs. The lobby
packet now carries the match phase. Separately, the same commit that
surfaced this had already been shipping a frame with no terrain at all
for three commits (D-046's audit).

---
