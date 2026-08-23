# D-20260818 · Battle quality outranks player count

**Status:** ACCEPTED — the owner's call, 2026-08-18, given while
accepting D-20260818-rome-total-war-formations-in-three-tiers: *"close
all the gaps — sacrifice total player count to achieve it."*

**Amends:** D-018 (full-scale target) and D-089 (20 players as design
target) — both get dated amendment notes pointing here; neither is
superseded, because the replacement number does not exist until it is
measured. **Extends:** D-20260818-rome-total-war-formations-in-three-tiers
(the three tiers are the first three workstreams of this programme).
**Relates to:** D-006, D-019, D-024, D-058, D-082.

## The call

A gap analysis (2026-08-18, this session) compared the accepted
three-tier plan against Rome: Total War-quality battles, unit control
and fighting, and found the tiers close the fighting-visuals gap and
half the frontage gap while most of what makes an RTW battle read as
one lives outside them: morale sophistication, control verbs, charges,
visible deaths. The owner's answer was to close **all** of it, and to
name the budget that gives way: **total player count.**

## What this does and does not change

**Unchanged, and binding on every workstream below:**

- **Server-authoritative, squad-level, stochastic combat (D-024).** The
  gap analysis itself established that no gap on the list needs
  per-soldier combat resolution — every new combat term is a
  squad-level scalar or a pure function of replicated state. Closing
  the gaps must not turn 40,000 soldiers into 40,000 simulated
  entities; per-soldier VISUALS and per-soldier PAIRING are not
  per-soldier resolution.
- **Derived animation phase (D-082).** `phase = fract(t*rate +
  hash(slot))`, in the shader, from TIME. A phase counter advanced by
  delta time is integration state in cosmetic disguise, whatever tier
  it arrives in.
- **The fairness rule.** Combat outcome cannot depend on where
  anybody's camera is pointing. This survives from the three-tier
  decision as Tier 3's binding constraint and applies to everything
  here.
- **D-006 clause 1 until its explicit amendment.** Tier 3's emergent
  per-soldier movement lands only after D-006 is amended in its own
  file: what is newly allowed, what stays forbidden, what the new
  revisit trigger is.

**Changed:**

- **D-018's 20 players / 40,000 soldiers stops being the binding
  budget.** The new rule inverts the old one: build the battle quality
  first, spending knowingly and measuring as this project always has
  (every number with its squad count), then **measure the player count
  the budgets still sustain** — 100 ms tick on the server, a playable
  frame on the reference client — and that measured number becomes the
  full-scale target. D-020's 100 ms tick itself does not move; what
  gives is how many players fit inside it.
- **D-089's revisit trigger is effectively pulled, from a new
  direction.** It anticipated the design target falling because 20
  players proved un-fun; instead it falls (if it falls) because the
  owner priced battle quality above headcount. The engineering work
  D-089 obliges (fill, resilience, repossession) is untouched — a
  smaller headline match still needs all of it.

## Scope — the gap inventory, as workstreams

One PR per workstream, in dependency order. The first three are the
already-accepted tiers.

1. **Tier 1 — cosmetic duels** (D-006 clause 2, legal today). Men pair,
   face, step into contact, strike at their opponent. Render layer only.
2. **Visible deaths.** A casualty plays a death animation and leaves a
   corpse that persists on the field. Render layer: death events are
   already ordered, replicated state (D-006 clause 3), so which slot
   dies and when is derivable; a corpse is a client-side record of a
   replicated event, not new state. Needs a death clip in the VAT
   (art pipeline, D-081/D-082).
3. **Tier 2 — derived pairing that combat reads.** The contact set as a
   pure function of replicated squad state. Frontage becomes real; only
   men in contact fight. The purity collapse trigger from the
   three-tier decision stands: if pairing needs cross-tick memory, stop
   and re-decide.
4. **Morale terms** (reads Tier 2's contact set; all squad-level
   scalars, D-024-legal). Flank/rear shock — being engaged from the
   flank or rear costs morale beyond the casualties; **chain rout** — a
   friendly squad breaking within sight costs nearby squads morale, so
   battles can cascade to a decision instead of grinding to
   annihilation; **pursuit** — a routed squad pursued by a faster enemy
   takes cut-down casualties, so a rout is a defeat mechanism rather
   than a pause.
5. **Control verbs, first half: facing and width/depth.** Wire opcodes,
   server-validated like every command, UI on the command panel.
   Facing stops being purely path-derived; ranks/files stop being
   `.tres` constants. Named "ordinary once Tier 2 exists" by the
   three-tier decision; scheduled here.
6. **Charge.** A squad ordered to charge closes at speed and its first
   contact applies an impact bonus (squad-level, momentum from its own
   replicated speed and mass class). What distinguishes cavalry
   arriving at speed from cavalry standing still.
7. **Stances: guard, skirmish, fire-at-will, walk/run.** Squad-level
   flags changing movement/engagement behaviour, replicated like shape.
8. **Drag-out placement and group formations.** Position + facing +
   width in one gesture; a selected group arranged as one battle line.
   Client UX over the opcodes from workstream 5.
9. **Special formations as data.** Phalanx / testudo / shield-wall
   mechanical knobs on `FormationDef` (directional damage/armour
   modifiers), civ-gated the D-047 way — no script names a formation.
10. **D-006 amendment + Tier 3 — emergent per-soldier movement.** Men
    fill vacated slots, chase routers, shove. Client-side integration
    state, explicitly legalised, with outcome-affecting state still
    squad-level. Last on purpose: it is the founding-rule change, and
    everything above lands without it.
11. **Fatigue and terrain height.** Squad-level fatigue draining under
    run/charge/melee and feeding the morale model; a height-advantage
    combat term (elevation finally acquiring tactical meaning — noted
    as the trigger that un-frees D-084's rendering split, so this
    workstream must revisit that entry).
12. **Generals.** A per-player general unit whose presence steadies
    morale and whose death shocks it. Deliberately last and deliberately
    small-scoped here; if it grows (auras, abilities, succession) it
    gets its own decision first.

**Explicitly deferred, not silently dropped:** archer ammunition and
missile friendly fire (a real RTW resource/risk, but it needs a
projectile model D-024 deliberately does not have — reopen against
D-024 if wanted); pause-and-order (structurally impossible in a
20-seat realtime match and not wanted in a 2-seat one).

## Exit criteria (written before the code, D-026/D-044 style)

Each workstream's PR must show its own criterion met; every new check
observed to fail before it is trusted; every number quoted with its
squad count.

1. **A picture of a melee** shows paired men facing their own
   opponents in contact — from a purpose-framed instrument (the
   gen-*-preview pattern), because `test-client` frames a spawn and
   cannot see a fight.
2. **A casualty is visible:** a man falls where he stood and his corpse
   is still there a minute later, in the picture.
3. **Frontage decides:** with shipped defs, a wide line beats an
   identical-troops deep column at the point of contact, in a
   whole-encounter test (the D-066 rule: shipped numbers, not
   caricatures) — and an enveloping squad lands more men in contact
   than a frontal one, measured.
4. **Morale reads the fight:** rear engagement breaks an otherwise
   identical squad sooner than frontal (shipped defs); one squad
   breaking measurably drains a nearby friend; a faster pursuer cuts
   down a router. Each in a test that fails with the term removed.
5. **Facing and width are the player's:** opcodes validated
   server-side, reachable from the UI (the D-061 lesson — prove the
   caller is reachable, not just written), and a drag gesture sets
   position + facing + width in one motion in a played match.
6. **A charge lands:** impact bonus measurable with shipped defs;
   a cavalry charge visibly reads as one in the picture.
7. **Tier 3 diverges nowhere it counts:** after the D-006 amendment,
   `test-load` still reports 0 desyncs over its full comparison count,
   because everything outcome-affecting stayed squad-level.
8. **The new player count is measured, not asserted:** at programme
   end, the maximum count holding D-020's 100 ms tick server-side and a
   stated reference frame budget client-side is taken via `just
   test-load` / `just bench-render` (with hardware named, per D-085's
   rule) and recorded in a successor entry that supersedes D-018's
   number. Until then, nothing else may quietly re-quote 20.
9. **A human plays a battle and says the fight reads as a fight**
   (D-085 criterion 14; "landed" and "meets criteria" are different
   claims).

## Rejected alternatives

- **Pick the new player count now** (e.g. "8 players") and budget
  against it. Rejected: any number chosen today is invented, and this
  project's record on invented numbers is the reason its rules say
  measure first. The count is an *output* of the programme.
- **Per-soldier authoritative combat to close the gaps "properly".**
  Rejected on the gap analysis's own finding: no gap needs it. It
  remains the road to 40x netcode and a rewritten LOD story (D-024's
  rejected alternatives, unchanged).
- **Close only the cheap gaps (morale terms) and re-ask.** Rejected by
  the owner's instruction: close all of it.

## Revisit trigger

If the measured player count at programme end lands below what the
owner can accept for the Steam headline (D-089's discovery/fill design
assumed 20 seats), the owner chooses: cut workstream cost (Tier 3 and
fatigue are the expensive ones) or accept the count. Also: the
three-tier decision's Tier-2 purity collapse trigger is inherited
here — test it early in workstream 3, before workstreams 4–9 build on
the contact set.
