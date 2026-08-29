extends Resource
class_name UnitDef

## Data-driven squad/soldier definition (D-010). New units are added as
## .tres files under /units/, not new script subclasses. Extend fields
## here when a unit needs a stat that doesn't exist yet — per CLAUDE.md,
## record the schema change in game_design_decisions.md.

@export var id: StringName
@export var display_name: String = ""
@export var civ: StringName = &"neutral"

## The shared idea of a troop type — spearmen, archers, cavalry (D-047).
##
## A UnitDef is ONE CIV'S VERSION of an archetype. Two civs that both
## field spearmen have two UnitDefs with the same `archetype` and
## different ids, stats and costs: one may be cheap and weak, fielded fast
## and in numbers, and lose to a smaller body of the other's.
##
## This is what lets every script stay civ-agnostic (D-046 criterion 3).
## Keybinds, production UI and the AI all reason about archetypes, so one
## key trains *your* civ's spearmen whatever that civ calls them, and
## nothing anywhere needs to know a civ id.
##
## Distinct from `armour_class`, which has three values and answers "what
## beats this" for `bonus_vs`. This answers "what IS this", and there are
## more archetypes than armour classes.
@export var archetype: StringName = &"militia"

## The tech LINE that makes this unit producible, or empty for "always"
## (`D-20260827-the-tree-is-the-ladder`). Names a LINE, never a tech id,
## so one entry covers every civ's version of the tech exactly as
## `built_by` covers every civ's version of a builder.
##
## Empty is the default and every `gatherers`, `general` and `levy` def
## leaves it so: the opening does not change, and a build with no /techs
## at all plays exactly as it did before the tree existed. That is D-070's
## own safe-default reasoning ("an unaware .tres is free to keep"),
## applied to a gate rather than to an epoch number.
##
## Deliberately the ONLY availability gate. D-070 also proposed
## `UnitDef.epoch`; two gates on one question is one too many and the pair
## would be free to disagree — the D-058/D-065 family, which this project
## has now paid for four times. Epoch gates TECHS; techs gate this.
@export var requires_tech: StringName = &""

# Squad composition (D-005: squads are the atomic sim unit; D-018: full
# scale target is ~40 soldiers/squad, ~50 squads/player).
@export var squad_size: int = 40

# Per-soldier stats. Combat resolution model (Q7) is not yet decided —
# these are the stats a deterministic-per-soldier or stochastic-squad
# model would both need as inputs.
@export var health: float = 100.0
@export var damage: float = 10.0
@export var move_speed: float = 3.5
@export var attack_range: float = 1.5
@export var attack_interval: float = 1.0

# Formation & morale (D-019: Total War-style formations/morale/routing,
# no campaign layer). Exact rout behavior (Q7) is still open.
## The formation this unit uses by default. Validated against
## /formations/*.tres by the roster test rather than an enum here, so
## adding a formation is one file and not two edits (D-058).
@export var formation_shape: String = "line"
# Centre-to-centre spacing between adjacent soldiers, in world units.
# Schema addition 2026-07-29 (M1, recorded against D-010): formation
# geometry needs a per-unit spacing — cavalry and skirmishers do not
# occupy the same footprint as line infantry. Existing .tres files pick
# up the default.
@export var formation_spacing: float = 1.0

## Extra formations GRANTED to this unit beyond the globally offered set
## (D-20260819-a-formation-is-a-fighting-style) — how one civ's spearmen
## know the shield wall while another's do not, with no script naming
## either (D-047). Validated server-side against offered-or-granted.
@export var formations: Array[StringName] = []

## A general (D-20260819-a-general-holds-the-line): presence steadies
## nearby allies (double morale recovery, half the chain-rout shock) and
## his death shocks them. Limited to one ALIVE per player, enforced where
## production is validated.
@export var is_general: bool = false
@export var morale: float = 100.0
@export var rout_threshold: float = 25.0

# Schema addition 2026-07-30 (M2, recorded against D-010): combat and
# morale tuning for D-024/D-019, plus vision for D-025 (owned by the fog
# worker, added here because this file is combat's, not theirs, to touch).
# Existing .tres files pick up these defaults, same as formation_spacing.
#
# How far this unit's squad can see, in world units (D-025). Radius-only
# on the torus — elevation does not occlude in M2.
@export var vision_range: float = 12.0
# Morale regained per second while not taking casualties (D-024/D-019).
@export var morale_recovery_per_second: float = 2.0
# Hysteresis above rout_threshold a routed squad must recover past before
# it rallies — without this a squad sitting exactly at the threshold
# would flicker in and out of routing every tick it takes no damage.
@export var rout_rally_margin: float = 15.0
# Morale lost per soldier this squad loses to casualties.
@export var morale_loss_per_casualty: float = 4.0

## The squad size `morale_loss_per_casualty` is authored against.
##
## 36 because that is what the old legion/northmen line squad was when
## the shipped 4.0 was written, so a 36-man squad behaves exactly as it
## always has and every other size is normalised to it rather than to a
## number picked now.
const MORALE_REFERENCE_SQUAD := 36.0


## Morale lost for ONE casualty, scaled to this squad's size (#266).
##
## The authored field is a flat per-man number, and this roster runs from
## 3 men to 48. Flat, the casualties needed to break are a CONSTANT —
## `(morale - rout_threshold) / morale_loss_per_casualty`, which at the
## shipped 100/25/4.0 is 18.75 — so **any squad of 18 men or fewer is
## annihilated before it can be frightened.** Not rarely: never, at any
## level of beating, from any direction, with recovery disabled entirely.
## Measured: 12 of 27 combat defs, including EVERY cavalry def in the
## game and the whole of one civ's non-levy roster.
##
## Scaled, the casualties needed become a constant FRACTION of the squad
## instead: `(morale - rout_threshold) / (loss * REFERENCE)`, about half
## the squad at the shipped numbers, whatever its size. A six-man breaker
## and a forty-eight-man levy now break at comparable attrition, which is
## what "morale" was always supposed to mean.
##
## Fearlessness survives untouched and for free: a fearless def ships
## `morale_loss_per_casualty = 0`, and zero times any scale is zero
## (#191, `tests/test_fearless.gd`). That matters more than it looks —
## the defect this fixes was silently sharing the fearless civ's one
## distinguishing feature with twelve units belonging to the other five.
##
## An APPLIED accessor rather than the raw field, per
## `D-20260823-a-civs-knobs-are-read-by-the-simulation`: both readers are
## in combat and `x * REFERENCE / squad_size` written out twice is two
## copies of one rule, free to drift.
func morale_loss_for(casualties: int) -> float:
	if squad_size <= 0:
		return float(casualties) * morale_loss_per_casualty
	return float(casualties) * morale_loss_per_casualty \
		* MORALE_REFERENCE_SQUAD / float(squad_size)


## Casualties this squad can take before it breaks, or a very large
## number if it never will. The reachability question #266 is about,
## answerable without running a fight.
func casualties_to_rout() -> float:
	var per := morale_loss_for(1)
	if per <= 0.0:
		return INF
	return (morale - rout_threshold) / per
# Stochastic spread on this unit's damage roll: output is drawn uniformly
# from [damage * (1 - variance), damage * (1 + variance)] per D-024's
# "rolled stochastically". 0 would make combat deterministic attrition,
# which D-024's rejected alternatives explicitly reads as too decided by
# stat ties alone.
@export var damage_variance: float = 0.25

# Primitive-tier mesh generation (D-011, see primitive_unit.gd). Tiers 2
# (modular/parametric) and 3 (Blender/glTF final-fidelity) are
# unscheduled — don't add fields for them speculatively.
# Counters (D-032, a D-024 amendment). Schema addition 2026-07-30 (M3,
# recorded against D-010): D-015's cut line asks for 3-4 unit types, and
# four types distinguished only by flat stats give none of the
# rock-paper-scissors the genre runs on.
#
# `armour_class` is what this unit IS for targeting purposes;
# `bonus_vs` maps an opponent's armour_class to a damage multiplier, so
# the counter table is data rather than a match statement in combat.gd.
# A missing entry means 1.0 — a unit with no bonuses is simply a
# generalist, not a special case.
@export_enum("infantry", "cavalry", "missile") var armour_class: String = "infantry"
@export var bonus_vs: Dictionary = {}

## Fraction of this squad's damage that lands on a BUILDING. Schema
## addition 2026-08-02 (M6, against D-010), recorded in D-056.
##
## Soldiers are not siege engines. Without this, siege damage was the full
## `damage * alive` a squad deals to flesh, and measurement said a single
## 36-strong militia squad razed a 900 HP town centre in **2.1 seconds** —
## so once any army arrived, a base evaporated and the match was over.
##
## A separate field rather than an entry in `bonus_vs`, deliberately.
## `bonus_vs` reads 1.0 for a missing key, which is the right default for
## a counter table (no bonus = generalist) and exactly the wrong one here:
## forgetting the entry on a new unit would silently restore the
## three-second base. This field's default is the SAFE end of the range,
## so a new .tres that never mentions it is conservative rather than
## catastrophic.
##
## Raise it for units that are meant to break walls — that is the hook a
## future siege archetype hangs on, and it needs no code change.
@export var damage_vs_buildings: float = 0.15

@export_enum("capsule", "box", "cylinder", "hull") var mesh_primitive: String = "capsule"
@export var mesh_color: Color = Color.WHITE

## Which authored model this unit wears (D-064). Schema addition 2026-08-09
## (M7, against D-010).
##
## Names a build product under `generated/models/<model_id>.glb` with a
## matching vertex animation texture. EMPTY means "use the primitive above",
## and that is the default on purpose: bots, tests and a fresh clone whose
## `generated/` has not been built all keep working, so a failed art build
## costs fidelity rather than the game.
##
## Keyed by ARCHETYPE, never by civ. D-046 criterion 3 has a test asserting no
## `.gd` file names a civ id, and a model keyed by civ would make civ three an
## art task exactly as a code branch would make it a programming task.
@export var model_id: StringName = &""

## A squad that WEARS MORE THAN ONE MODEL (D-20260826-a-squad-wears-more-
## than-one-model). Schema addition 2026-08-26, against D-010.
##
## `slot_models` names the models of the LEADING formation slots, one entry
## per slot: a hero squad's slot 0 is its general, a cannon crew's slot 0 is
## the gun carriage. Slot 0 is also the LAST slot render LOD ever drops
## (`Formation.soldier_transforms_sampled` picks `i * alive / n`, so drawn
## index 0 is always slot 0) — the one soldier the squad is ABOUT stays on
## screen at every distance.
##
## `model_mix` is dealt round-robin across every slot past `slot_models`, so
## a retinue reads as a body of dwarfs with mixed kit rather than eight
## copies of one man. Empty means every remaining slot wears `model_id`,
## which is what the whole existing roster does — both fields default empty,
## so no shipped .tres changed meaning.
##
## RENDER-ONLY, deliberately. The simulation knows `squad_size` and `alive`
## and nothing else (D-005/D-024): which slot wears which mesh changes no
## outcome, so these fields are read by `PrimitiveUnit` and by nothing on
## the server.
@export var slot_models: Array[StringName] = []
@export var model_mix: Array[StringName] = []

# Naval (#301, `docs/plans/naval.md` §2.2 and §5). Schema addition
# 2026-08-28, against D-010.

## Which movement DOMAIN this unit lives in. Ground is every unit that has
## ever existed here; water is a ship.
##
## A domain rather than a flag because `SquadSim._tier` gains a third
## value (`DOMAIN_GROUND` / `DOMAIN_WALL_TOP` / `DOMAIN_WATER`) and the
## three are mutually exclusive by construction — a ship is never on a
## wall, and a land squad is never on open water except as cargo, which is
## not in the world at all.
##
## The PATHING half of this is naval stage 2 and is not in the tree yet.
## The field is here because ten ship `.tres` files are, and a `.tres`
## naming a property its schema lacks is a value that silently becomes a
## default. Its first reader is `tests/test_naval_roster.gd`, which
## screens by it and asserts every land unit in the roster is `ground`.
@export_enum("ground", "water") var movement_domain: String = "ground"

## How many SQUADS this unit can carry as cargo. Zero for everything that
## is not a transport, which is every unit outside `/units/*_*` naval defs.
##
## Squads rather than soldiers, because a carried squad is removed from
## the world whole (naval design §3.1) — there is no partial load and so
## nothing to count in men. Read by the roster screen, which prices a
## transport in capacity per resource point because V cannot price
## carrying.
@export var transport_capacity: int = 0

# Economy
# Gathering (D-028). Schema addition 2026-07-31 (M3, against D-010).
# A unit with carry_capacity > 0 IS a gatherer — no separate boolean to
# fall out of step with it. Zero is the default, so every existing .tres
# stayed valid and no fighting unit accidentally became a villager.
@export var carry_capacity: int = 0
## Units gathered per second per LIVING soldier, so casualties cut income
## without any special case (D-028).
@export var gather_rate: float = 0.0

# Cost, per resource (D-028's four). Schema addition 2026-07-31 (M3,
# against D-010), replacing the single `cost` field that sat unread since
# M0 — four resources need a table, not a number. `cost` is left in place
# for now rather than removed, because nothing reads it and deleting a
# field from a Resource rewrites every .tres that mentions it.
@export var cost_food: int = 0
@export var cost_wood: int = 0
@export var cost_gold: int = 0
@export var cost_stone: int = 0

@export var build_time: float = 10.0
@export var cost: int = 50
