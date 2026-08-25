**RTW-quality battles — a programme, in progress
(D-20260818-battle-quality-outranks-player-count).** The owner accepted
the three formation tiers
(D-20260818-rome-total-war-formations-in-three-tiers) and then widened
the order on the same day's gap analysis: close every gap between this
game's fights and Rome: Total War-quality battles, unit control and
fighting — morale terms, control verbs, charges, visible deaths, the
lot — and **sacrifice total player count to afford it**. The programme
entry has the twelve workstreams in dependency order and the exit
criteria; the trade's mechanics matter more than its slogan:

- **D-018's 20 players / 40,000 soldiers stops being the binding
  budget, but its successor is not chosen — it will be MEASURED** at
  programme end (exit criterion 8) and recorded in an entry superseding
  D-018's number. Until then nothing may quietly re-quote 20, and every
  measurement still carries its squad count.
- **What does NOT move:** server authority; squad-level stochastic
  combat (D-024 — the gap analysis found no gap that needs per-soldier
  resolution); derived animation phase (D-082); the fairness rule
  (outcomes never depend on where a camera points); and D-006 clause 1
  until its explicit amendment, which is workstream 10's first act, not
  a side effect.

**Workstream 1 — Tier 1, cosmetic duels — landed.** In a melee the
render layer pairs each man with his nearest opponent, faces him, steps
him into contact (`CosmeticDuel`, all-static and pure, D-006 clause 2)
and strikes at his own opponent rather than the squad's centre-point.
Outcomes, wire and server untouched — `combat.gd` is not in the diff.
Three things worth knowing:

- **Pairing is memoryless on purpose, and that is a probe, not a
  shortcut.** Nearest-opponent is recomputed per frame from both squads'
  derived positions; it is stable because its inputs are (curves move on
  keyframes, casualties restamp), and `SoldierMotion.ease` glides the
  retargets when they do happen. The three-tier decision's collapse
  trigger — "if a man must REMEMBER his opponent, Tier 2 is not a pure
  function" — is therefore being tested from day one. If Tier 1 duels
  visibly re-target in play, that is the trigger firing; report it
  against the decision, do not add a cache.
- **The duel can never scatter a formation.** A man steps at most
  `MAX_STEP` (1.1) from his authoritative slot, closes HALF his excess
  gap (both sides step, so mutual pairs meet exactly `CONTACT_GAP`
  apart — closing the full gap double-counts and stands men inside
  each other), and past `ENGAGE_RANGE` (6.0) holds his slot exactly
  while still bracing toward the enemy. A man who cannot REACH contact
  takes a short `REAR_LEAN` instead of his full step — the first
  preview picture showed second-rank men walking `MAX_STEP` into their
  own front rank, two squads reading as one blob, with every number
  green. Selection, culling, separation and the composition hash all
  still read the derived transforms.
- **`just gen-duel-preview` is the instrument.** Two authored squads,
  real `Formation.slot_offset` lines, the real three-call pipeline
  client.gd runs per frame, screenshot to `artifacts/duel-godot.png` —
  **look at it**; the recipe fails if nobody moved or nobody reached
  contact, and prints the duel pass's µs with its squad sizes. It
  exists because `test-client` frames a spawn, which is the one place a
  melee is not (the same lesson as cliffs, forests and the fog edge).

**Workstream 2 — visible deaths — landed, with its art half blocked by
the HOST** (D-20260819-a-casualty-is-visible). A casualty event now says
whether its men FELL (one wire byte; consumption per D-031 and
disconnect wipes per D-033 share combat's message and decode as
not-fallen without being edited), and the client lays a corpse at every
slot the restamp vacates — derived by the same formation function that
drew the man, capped in a ring (`CorpseLedger`, pure and tested
headless), dimmed by fog like the props (#81's rule: a corpse is
knowledge, drawn forever like a building, never a ghost), and drawn at
every visible lattice copy. The fall phase is
`clamp((now − event_time)/FALL_SECONDS)` — derived from the replicated
event, never accumulated — written into the shader's rate-zero phase
float only while the man falls.

- **The VAT has no death clip yet, and cannot get one on this machine:**
  a Windows Application Control policy now blocks `bpy`'s DLL in every
  worktree's venv, so `just build-assets` fails host-wide and any edit
  under `art/` reds the staleness test until the owner unblocks it.
  Corpses therefore TIP at the feet (the felled-tree language) with the
  pose frozen; the moment a rebuilt bake ships a `death` clip, every
  model upgrades through the manifest (`UnitMesh.has_death_clip`) with
  no code change. The clip itself is specified in the decision.
- **Bots record nothing:** the casualty-site drain only writes when
  `record_corpses` is set, which only the GUI client sets.

**Workstream 3 — Tier 2's contact set — landed**
(D-20260819-only-men-in-contact-fight). A squad's damage multiplier is
its men within fighting reach of the enemy's men over both squads'
DERIVED positions — frontage is real (a wide line beats a deep column
of the same troops, played whole with a roster def), envelopment is
geometry, nothing new on the wire. Four things to know before touching
it:

- **`engagement.gd` is THE definition of pairing, reach and contact**,
  read by combat for resolution and the Tier 1 duels for drawing — one
  function so the fight a player sees is the fight that resolves. It is
  all-static and a test forbids state: a remembered pairing is the
  three-tier decision's collapse trigger, and the answer is a
  re-decision, never a cache.
- **Contact reach is `attack_range + 2×MAX_STEP`, and the slack is
  load-bearing:** engaged front ranks stand a cell apart, which exceeds
  a bare melee reach — measured raw, an engaged pair counts zero contact
  and melee deletes itself (the D-067 opposed-arithmetic family).
- **Transforms derive at the ROUND SNAPSHOT** (memoised per tick), or
  the formation restamp smuggles D-024's simultaneity bias back in. And
  **the torus tax is paid in `aligning_offset`** — unaligned, a seam
  battle derives its enemy a map away and resolves zero damage forever
  (a latent Tier 1 seam wart went with it).
- **Fights are slower per exchange and bloodier overall** (A/B in the
  decision: combat 9.59 → 33.19 µs/squad at 24 squads; casualties 469 →
  698 in the same window — less rout ping-pong, more grind). Any timing
  or gate tuned against the old kill pace is measuring a different fight
  now; the siege loop's fog gate already tipped on exactly this and the
  standing window-before-fault rule applies.

**Workstream 4 — morale reads the fight — landed**
(D-20260819-morale-reads-the-fight). Three squad-level scalar terms,
server-only, nothing on the wire: a casualty's morale cost is
multiplied by the blow's aspect (front ×1, flank ×1.5, rear ×2.5, from
`Engagement.aspect` over the squad's own derived facing, torus tax
paid); a breaking squad costs every ally within 8 cells 12 morale and
can cascade (`_break_squad` is the one machinery — melee and tower
routs shock identically); a routed defender takes ×2 damage, gated on
the round snapshot. Envelopment now BREAKS a line rather than merely
out-trading it, battles can cascade to a decision, and a rout is a
defeat rather than a pause. The multipliers are `combat.gd` constants
in `ROUT_FLEE_MULTIPLIER`'s style — the decision records exactly when
they become schema (a civ or unit identity asking to vary one), and
the first tuning lever if battles DECIDE too fast is
`CHAIN_ROUT_MORALE_LOSS`, then the radius.

**Workstream 5 — facing and width are orders — landed**
(D-20260819-facing-and-width-are-orders). Two new replicated squad
values riding D-058's exact machinery (validated through the shared
helper, SQUAD_INFO rebroadcast, hashed on both sides): ordered FACING —
quantised to 1/4096 of a turn so both machines reconstruct one integer,
resolved in ONE place (`Formation.facing_angle`: path while moving,
order while standing) that soldier derivation AND combat's rear-shock
aspect read, so bracing a line is a defence — and ordered FILES (width),
which frontage, footprint, culling and separation all read, so widening
a line is an attack. Interim UI until workstream 8's drag: Alt+right-
click faces the selection at the clicked point; Widen/Narrow buttons in
the orders column. The torus tax is paid in the facing click too (the
clicked point may be a lattice copy away from the squad's canonical
position).

**Workstream 6 — charge — landed**
(D-20260819-a-charge-is-spent-on-its-impact). A charge is attack-move at
×1.5 speed with ONE ×3 impact blow waiting at the end, all squad-level.
The rules each close an exploit or a misfire: the charge is spent ON THE
BLOW, not on contact (a charging squad skips D-034's halt until its
attack fires — halting first killed the flag one line before the attack
it carried); point-blank orders degrade to attack-move (no free impact
per click); the sprint expires after 8 s (fatigue replaces the deadline
in ws11); a plain move, a player stop or a rout cancels. The impact
multiplies CONTACT damage and its casualties carry ASPECT shock, so a
wide rear cavalry charge compounds through three mechanics that never
read each other's internals. Nothing is cavalry-cased — a knight hits
harder because his data says so. The Charge button arms the next
right-click, mirroring the Target button's split; the visible half of a
charge is SPEED, which no still can show — the owner's playtest is the
instrument, per the decision.

**Workstream 7 — stances — landed**
(D-20260819-stances-are-standing-orders). One stance byte, ordered
whole, on SQUAD_INFO but not hashed: GUARD opts out of idle pursuit
(the control combat.gd's pursuit header always named as future work),
SKIRMISH steps an idle missile squad away from a closing enemy through
the ordinary move order, HOLD FIRE holds until an explicit attack order
RELEASES it (gating on the attack-move flag falls to D-034's halt
spending it on contact — a held squad ordered to attack would fire once
and fall silent). Walk/run deliberately waits for fatigue (ws11).

**Workstream 8 — a drag draws the battle line — landed**
(D-20260819-a-drag-draws-the-battle-line). Right-press, drag, release:
the selection forms along the stroke — position, facing and width in
one motion, several squads at once, compiled entirely into workstream
5's orders so the server learns nothing new. `battle_line.gd` owns the
arithmetic (all-static — the D-061 "client geometry nobody can test"
lesson as code): segments dealt by projection so lines never cross
while forming, facing the stroke's perpendicular away from the troops,
files what fits shoulder to shoulder. A short release is yesterday's
click exactly, Alt still means face; ctrl-drag forms with attack-moves.
A ground stroke previews while dragging (canonical copy only — a
transient input hint, not world state).

**Workstream 9 — a formation is a fighting style — landed**
(D-20260819-a-formation-is-a-fighting-style). FormationDef carries
directional damage-taken, missile_taken and pace_scale (all default 1.0,
pinned); combat computes each blow's aspect ONCE for both the defence
and the morale shock; shield_wall and testudo ship as .tres, granted per
unit through UnitDef.formations — no script names a civ.

**Workstream 11 — tired men, and men fighting uphill — landed**
(D-20260819-tired-men-fight-uphill). Fatigue (server-only scalar):
sprint -12/s, fight -2/s, run -6/s, rest +4/s; damage scales
0.5+0.5·f/100; charges refused under 40 and ENDED at 25 — the charge
tick deadline is GONE, replaced as promised, so charge-rest-charge is
priced. RUN joined the stance byte. Height: the sim carries the
server's own elevation field (empty = flat) and combat prices the
slope ×1.15/×0.85 past a 0.05 step — discrete, server-side, D-084's
interpolation split untouched.

**Workstream 12 — a general holds the line — landed**
(D-20260819-a-general-holds-the-line). UnitDef.is_general; one per civ
as .tres from the town centre; double recovery and half chain shock in
a 10-cell aura (stamped per tick from the few generals — O(1) per
squad, the vision.gd shape); death = twice a chain rout through the
same machinery; one alive per player at the production gate; the load
bots skip generals BY FIELD (their brains read no morale).

**Workstream 10 — Tier 3 lives on the render side — landed**
(D-20260819-tier-three-lives-on-the-render-side; **D-006 amended, in
its own file, 2026-08-19**). D-006's fired trigger honoured in the
open: clause 2 now permits bounded, one-way, outcome-blind per-soldier
render state, and `soldier_motion.gd` is where it lives — survivors are
DEALT to restamped slots by nearest-match and WALK in (the vacated-slot
behaviour the old trigger named first), and drawn men JOSTLE apart with
the drift clamped to MAX_RENDER_DRIFT where it is made. The new revisit
trigger: any OUTCOME wanting a drawn position reopens the
40k-entities-vs-divergence choice as a decision, never a patch.

**The programme's twelve workstreams are all landed.** Open ends, none
of them code on this stack: the VAT death clip (host bpy policy), exit
criterion 8 (the player-count MEASUREMENT that supersedes D-018's 20 —
to be taken once the stack merges, on hardware named), and criterion 9
(the owner plays a battle and says the fight reads as a fight).

**The drag shows the line it will form (D-20260823).** A right-drag now
previews the battle line as translucent discs — one per living man, at
the spot he will be commanded to — computed from the SAME
`BattleLine.plan` + `Formation.slot_world_offset` the release sends, via
one shared `_order_drag_squads()` gatherer. `slot_world_offset` was
extracted from `soldier_transform`, not written beside it: a preview
with its own arithmetic is a preview that eventually lies (D-096, third
occurrence). Shape belongs to the GESTURE — long stroke, thin line;
short stroke, deep block; the sizes between, square — and a dragged
width already outranked a formation's declared ranks. Tightness belongs
to the FORMATION and may only change closeness, which is why `plan` now
deals files at `Formation.effective_spacing`: dealing them at the unit's
raw spacing gave a tight squad a loose squad's file count, so it packed
short of its own stroke and left a gap at each end.
