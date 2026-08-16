### D-099 · 2026-08-16 · Accepted — a concealed squad disappears; a seen building stays

**Numbering note.** D-099 is this entry's ASSIGNED id, from the session
coordinating seven parallel fix branches (#68=D-099, this one). See
D-100's own numbering note above for the assignment in full, and for the
unresolved D-100 collision with ground cover — nothing here depends on
how that is settled.

**Decision:** Fog of war has ONE rendering rule per entity kind, and they
differ:

1. **A concealed squad is not drawn at all** — not in the 3D view and not
   on the minimap. Its node is explicitly hidden the frame it becomes a
   ghost, rather than left untouched: a squad's `PrimitiveUnit` holds
   whatever transforms the live pass last gave it, so "stop updating it"
   renders a frozen, fully opaque squad standing where it was last seen,
   which is worse than either alternative.
2. **A building once seen stays drawn**, at its last-known state, with no
   fade and no styling of any kind. That is persistent-explored fog
   (D-029/D-030) and it is unchanged by this entry — it is written down
   here only so the asymmetry is deliberate rather than accidental.

**None of D-025 changes.** The ghost remains exactly what it was on the
wire and in `ClientState`: `ghost_squad_ids()`, `ghost_info()`, the
explicit conceal event, the stale last-known curve and composition, and
`composition_hash()` covering live squads only. This is a display decision
about a squad that is already a ghost, not a change to what a ghost *is*.
`ClientState.is_ghost` is still the question the renderer asks — the
shipped answer is now "then draw nothing" rather than "then draw it
faded".

**Consequently the ghost-render path is deleted**, not kept dormant:
`PrimitiveUnit.set_ghost` and its `_is_ghost` material branch,
`UnitMesh.material_for`'s `ghost` argument and `GHOST_SHADER`,
`client.gd`'s `_set_ghost_look`, and `shaders/unit_anim_ghost.gdshader`.
`tests/test_ghost_squads_are_not_drawn.gd` guards both halves — that the
path stays gone, and that both draw sites still actively hide a ghost.

**This supersedes D-026 criterion 11's visual half** — the ghost fade, as
recorded in D-026's own completion review ("a worker also found... that
`GeometryInstance3D.transparency` renders nothing under the
`gl_compatibility` rasteriser") and cited by `_set_ghost_look`'s doc
comment. Criterion 11's replay half (casualty and rout events in the curve
log, `just replay-info` reconstructing strengths) is untouched and still
holds. D-082's mention of `unit_anim_ghost.gdshader` is superseded to the
same extent.

**The finding that machinery was bought with, kept because it will be
rediscovered otherwise:** `GeometryInstance3D.transparency` is
per-instance and **renders fully opaque under the `gl_compatibility`
rendering method**, which is the only renderer `just test-client` can use
(Mesa ships software OpenGL, not software Vulkan — D-014's 2026-07-29
amendment). Confirmed by turning it to 0.95 and finding the captured frame
pixel-identical to 0.6. Material-level alpha works everywhere the instance
property does not. And since M7 the mechanism differs by render path
anyway: a primitive mutates its `StandardMaterial3D`, an authored model
must swap to a *different shader program*, because whether a material is
transparent is fixed at shader COMPILE time (see
`shaders/unit_vat.gdshaderinc`). **Anything that wants a translucent unit
in future pays all three of those costs** — that is the price this entry
is recording, not the shader it deletes.

**Rationale:** The shipped behaviour has been "not drawn" since 2026-08-12
(the UI rework), as a deliberate display choice, and no entry recorded it.
That left `_set_ghost_look` citing D-026 criterion 11 as its justification
while deliberately not satisfying it, and left ~90 lines of shader and
material machinery reachable from nothing — the declared-and-unread shape
CLAUDE.md names as this project's one structurally invisible defect class,
here arrived at from the other direction: the code changed and the record
did not. It also cost a playtest cycle a false expectation (#40's pass
criterion 2 asked for a ghost shader that can never appear).

Why "not drawn" is the right rule and not merely the shipped one: a faded
squad standing where an enemy *used* to be is a claim the client cannot
back. It is stale by construction, it is indistinguishable at a glance
from a live squad that is simply idle (the fade is subtle at any playable
zoom, and unreadable at the LOD distances D-045 draws most squads at), and
the player acts on it as if it were current. Buildings do not have that
problem — a building that was there is still there until someone razes it,
which is exactly why the two rules differ.

**Rejected alternatives:** *Keeping the fade* (rejected on the paragraph
above, and it is what shipped for two milestones without anyone reporting
they read anything off it). *Keeping the code but never calling it*
(rejected — that is precisely the state the issue was filed about; dormant
machinery with no caller is invisible to every test and rots against the
renderer under it). *A last-seen marker instead of a squad* — an icon, a
footprint, a minimap tick at the last-known cell (**not rejected, only not
now**: it is the honest form of the tactical-memory argument D-025's
"hard removal on conceal" rejection makes, because a marker says
"remembered" without drawing men who are not there. It needs its own
decision, and it is what the revisit trigger below is for). *Amending
D-026 in place* (rejected — this file supersedes, it does not edit
history).

**Consequences:** D-025's "hard removal on conceal" rejection is narrowed
to what it always actually protected: the client keeps a concealed squad's
last-known curve and composition, and any future memory affordance is
built from that data, which is still there. What is gone is only the
*picture*. `test-client`'s verdict still reports `ghosts` and
`ghosts_peak`, which are counts of that data and remain meaningful; its
comment no longer claims the frame shows ghosts drawn distinctly, because
it does not. A player currently has no on-screen memory of where an enemy
squad was last seen — stated plainly, because it is the cost of this
decision and the thing a playtest should judge.

**Revisit trigger:** A playtest reporting that losing sight of an enemy
army loses the thread of the battle — that is the last-seen marker above,
and it needs a decision entry rather than reviving the fade. Also revisit
if unit transparency is wanted for anything else at all (stealth,
placement previews of units, selection ghosting): the three costs recorded
above apply to any of them, and the deleted shader is in git history at
`shaders/unit_anim_ghost.gdshader`.

---
