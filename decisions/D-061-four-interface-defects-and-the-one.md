### D-061 · 2026-08-04 · Accepted — four interface defects, and the one shape three of them share
**Decision:** Four faults reported from real play are fixed, and two of
them establish rules rather than just changing a number.

1. **The HUD is laid out against the window** (`hud_layout.gd`), by two
   separate mechanisms: a CanvasLayer **scale** so it is the same physical
   size on any monitor, and **anchoring** so it fits any window *shape*.
2. **Surviving damage replicates.** `BuildingSim.damage` marks the
   building dirty on any change of health, not only on the killing blow —
   quantised to `HEALTH_REPLICATION_STEPS` (32) so a siege costs a bounded
   number of messages. The client draws a health bar over the building
   itself, not only in the selection panel.
3. **Right-click sets a rally point again.** The building branch of
   `_order_selected` now runs *before* the empty-selection guard.
4. **A building covered in units is selectable** (`selection_pick.gd`):
   squads and buildings are ranked on one scale instead of two.

**The shape three of these share:** each was a rule that was fully
written, correct in isolation, and never reached. Rally orders were
encoded, sent-ready, validated server-side and drawn on the ground — and
the client returned two lines before the branch that sends them, because
selecting a building clears `_selected` and the guard against ordering an
empty selection fired first. `health_fraction` was in the wire format, in
`ClientState`, and drawn by the panel — and only ever carried the value
1.0, because nothing marked a damaged building dirty. Buildings competed
for clicks against a score that was negative by construction, so a
comparison that reads correctly (`if distance < best`) could not be true.

That is the same class as the uncalled `BuildingSim.damage()` of D-055,
`UnitDef.cost`, and `BuildingDef.cost` — but a step harder to find,
because the member here *does* have a caller. The caller is simply
unreachable, or reachable only with an argument that cannot occur. **Grep
for uncalled public members catches the first kind and not this one.** The
only thing that found these was playing the game and noticing that a
thing which plainly ought to work did not.

**Why the HUD needs both scale and anchoring:** either alone looks like it
is enough and is not. On a 16:9 monitor scaling by itself is sufficient,
which is exactly the trap — every common desktop is 16:9, so an anchoring
bug hides until someone runs at 21:9 or drags the window. Anchoring by
itself leaves a 4K HUD the size of a postage stamp. The reference window
is 1280x720 and the scale is `min(w/1280, h/720)`, so any 16:9 window
comes back to a design space of exactly 1280x720 and reproduces the
hand-tuned layout pixel for pixel; other shapes deviate only in where the
edges are.

**Why building health is quantised rather than streamed:** a besieged
building takes damage every attack cooldown, and marking each hit dirty
would resend its whole entry several times a second per attacker — D-003's
per-tick snapshot wearing a health bar. 32 steps is finer than the drawn
bar resolves and bounds a building's whole life to at most 32 health
messages. Note the first scratch always crosses a step, because full
health sits on a boundary: "this building has been touched at all" is
worth a packet.

**Why selection compares two different metrics:** *which squad* is decided
by distance normalised by each candidate's own footprint, so a small squad
clicked squarely beats a huge one merely grazed. *Squad or building* is
decided by raw distance to centre. Normalising both was tried first and
fails: a formation filling the screen scores near zero almost everywhere
and still swallows the town centre standing in the middle of it. Which
centre the cursor is nearer does not care how big either thing is.

**Rejected alternatives:**
- *Godot's `canvas_items` stretch mode for the HUD* (rejected — it pins
  the root viewport to the base resolution, so the 3D world would render
  at 1280x720 on a 4K monitor. The whole point of a big screen here is
  seeing more soldiers).
- *Streaming building health every tick* (rejected — D-003).
- *"A building always wins an overlapping click"* (rejected — clicking a
  soldier standing beside a barracks has to select the soldier; the fix
  must not become the mirror of the bug).
- *Scaling the HUD by adjusting font sizes and widths individually*
  (rejected — one transform carries borders, padding and bar thicknesses
  together, and none of them can be forgotten).

**Measured, not asserted.** `just test-load 4 120`, the same run with and
without the change (stashed), 52 squads:

| | bytes | µs/squad | worst tick |
|---|---|---|---|
| before | 523,544 | 73.07 | 58.3 ms |
| after | 522,880 | 75.52 | 67.3 ms |

Bandwidth is **unchanged** — the after figure is 664 bytes *lower*, which
is run-to-run noise, and so is the µs/squad difference (D-020's caveat:
the order of magnitude is the result, not the third digit). Both runs:
`VERDICT ok`, 0 desyncs, 0 building desyncs, 0 dropped ticks. So health
replication at 32 steps costs nothing detectable at this scale, which is
what quantising was for. It has NOT been measured under a long siege of
many buildings at once, which is where it would show if anywhere.

**Consequences:** the HUD's scale is clamped to [0.75, 2.0], so a very
large monitor gets a HUD that stops growing rather than one that keeps
pace — deliberate, since the reason to own one is seeing more map. Mouse
positions arrive in real pixels and HUD geometry is in design units, so
anything doing its own pixel arithmetic against the HUD must convert
(`Client._to_hud`); Godot handles Controls itself, so this is only the
minimap hit-test and the drag box. Both are converted; a third such site
added later and left unconverted would fail silently and look like a
mis-aimed click rather than a scaling bug.

**What is NOT verified, and should be said plainly:** the health bar's
DRAWING has not been photographed. The HUD was rendered and looked at at
1280x720, 1920x1080 and 2560x1080 (the last is the case scale alone
cannot fix), and the replication fix has a test that was watched failing.
But getting a building damaged *on camera* under the software rasteriser
did not happen: `test-client`'s capture scenario never had its base
attacked, and a ladder match with AI opponents killed the client
container every time — llvmpipe at 200s+ with four players' armies is
past what it will carry on this host. One real defect in the drawing was
found by reading rather than seeing (the bar of a destroyed building was
never hidden, because `_refresh_buildings` skips past the update on the
`destroyed` branch — it would have hung over the rubble EVERY time a
building died). Treat the rest of that path as reviewed, not proven, and
look at it the next time a real match is played.

**Revisit trigger:** if the HUD grows a piece that must stay a fixed
number of REAL pixels regardless of scale — a crosshair, a
pixel-art-aligned element — the single-transform approach stops being
sufficient and the layer split has to be reconsidered.
---

> **D-068 through D-074 are one argument and read in ascending order**,
> against this file's usual newest-first convention. They are the output
> of the age/tech planning milestone Q15 reserved, all dated 2026-08-04.
> D-068 is the derivation base: every number in the six that follow is
> supposed to trace back to a line in it. Read it first or the rest look
> arbitrary.
>
> **Numbering note, and a near miss worth recording.** This block was
> first written as D-063…D-069 against a worktree that was 14 commits
> behind `origin/main`. Main had meanwhile allocated **D-063 through
> D-067** for the HUD, formation-on-the-wire, building damage and the
> anti-rush rule — so the block was renumbered to D-068…D-074 before the
> merge, while every occurrence was still unambiguously local.
>
> **The check that missed it was run against un-fetched refs**, which is
> the same shape as trusting a stale sweep over a live run (D-043).
> Allocating a decision number requires `git fetch` first, then a scan of
> **both** this file's headings and the code citations — D-048, D-049,
> D-050, D-053, D-054, D-057 and D-062 are all cited by code with no
> entry here, so the highest heading has never been the highest number
> in force. That doc debt is unfixed and is its own job.
>
> **Milestone numbering moved too:** main's ladder is M7 = real models
> and textures, M8 = Steam. The epoch work is therefore **M9**.
