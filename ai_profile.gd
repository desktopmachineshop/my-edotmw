extends Resource
class_name AiProfileDef

## How an AI plays, as data (D-20260818-ai-profiles-are-data). New
## difficulty levels are added as .tres files under /ai/, never as a
## branch in ai_player.gd and never as an enum somewhere.
##
## ## Every field here is a DECISION, never a privilege
##
## The governing constraint, and the one to check any new field against:
## a profile may change what the AI *decides*, never what it *knows* or
## what it is *given*. D-051's structure — a real `ClientState` fed
## fog-gated packets, orders through the server's own dispatcher — is
## what makes an AI win mean anything, and a resource or vision bonus
## would quietly undo it. An AI that saw more would not look like a bug.
## It would look like a good AI.
##
## A handicap, if one is ever wanted, belongs in the lobby where a player
## can see it — not in this file, where it would be indistinguishable
## from skill.
##
## ## The defaults ARE the constants ai_player.gd used to hold
##
## So `AiProfileDef.new()` with nothing loaded plays exactly the AI that
## shipped before profiles existed, and `ai/standard.tres` is these
## defaults written out. A missing or unreadable /ai costs *difficulty*,
## never the game — the same shape as an empty `model_id` meaning "use
## the capsule" (D-081).
##
## It is also what keeps the ladder's history readable: every figure taken
## before profiles existed was taken against `standard`, so a figure taken
## after it is comparable to one taken before it.
##
## ## What is deliberately NOT here
##
## `AiPlayer.FOUND_RETRY`, `UNREACHABLE_AFTER` and `SCOUT_LEG_SECONDS`
## stay constants. Each bounds a FAILURE — an order that never landed, a
## node no crew can reach, a scouting leg that never ends — and a
## difficulty setting able to starve an AI of its opening is not a
## difficulty setting, it is a way to ship a broken opponent by data
## entry.

@export var id: StringName
@export var display_name: String = ""

## Flavour for the lobby, so a player choosing an opponent knows what
## they are picking. Not mechanics.
@export_multiline var summary: String = ""

## Where this sits in a list a player is shown, easiest first. Sorted on,
## so the roster's order is the file's business rather than the UI's.
@export var order: int = 0

## The one profile a seat gets when nobody chose. Exactly one shipped
## profile may set it, and the roster test says so — a second would make
## "the default" depend on filename sort order, which is precisely the
## kind of answer that is right until somebody adds a file.
@export var is_default: bool = false

## How often the AI reconsiders, in seconds. Ten times slower than the
## simulation tick on purpose — a human does not issue orders at 10 Hz,
## and thinking every tick would spend real CPU to play worse.
##
## A reaction-time axis rather than a pacing one, and deliberately mild
## for now: it is what will matter once the AI reacts to being attacked,
## which today it does not.
@export var think_interval: float = 1.0

## How many gatherer SOLDIERS to field before spending on soldiers.
##
## Was 3 squads, which is why the AI never fought: three crews haul too
## slowly to reach a barracks' 150 wood inside a match. Counted in
## soldiers rather than squads because `gather_rate` is per living
## soldier (D-028) — a target expressed in crews silently fell to a third
## when crew size went from 16 to 5, with nobody touching the AI.
##
## The pacing knob that matters most: this is the switch from economy to
## army, so it is most of the answer to "when does the first attack
## land".
@export var gatherer_soldiers_wanted: int = 110

## Seconds between production orders, so the queue cannot outrun the
## target the AI is aiming at.
##
## ## Per ORDER, and that is deliberate — do not "fix" it
##
## Because it gates orders rather than labour, shrinking gatherer crews
## from 16 to 5 tripled the time to staff an economy: the same ~110
## workers take 22 productions instead of 7. First contact moved from
## 121-160 s to ~326 s, which reads as a bug and is not — the owner's
## call is that the old ramp was FAR too quick (2026-08-04), and a slower
## build-up pulls the same direction as D-056's 1-2 hour target.
##
## It is a profile field now precisely so a faster ramp is a *choice a
## file makes*, rather than something a future reader reverts in the
## engine because the comment did not stop them.
@export var train_cooldown: float = 5.0

## How many military squads it masses before committing to an attack.
##
## The other half of what a human feels, and the one that decides what
## ARRIVES rather than when: at 2 the AI dribbles pairs of squads across
## the map, at 4 it turns up as an army. Raising it delays the first
## attack and makes it hurt more, which is why "harder" is not simply a
## smaller number here.
@export var attack_squads_minimum: int = 2

## How long the army is left to carry out an attack order before the AI
## reconsiders, counted in THINKS rather than seconds.
##
## In thinks because it is a regroup interval measured against the same
## clock the decision was made on: an AI that reconsiders twice as often
## should not also be re-ordering its army twice as often for free.
@export var attack_regroup_thinks: float = 8.0

## Enough food to keep training, and enough wood for the first building
## that makes soldiers. Below these, workers are sent after that resource.
##
## Lifted here because ai_player.gd's comment asked for it, NOT because
## it is a difficulty axis: every shipped profile carries the same floors.
## A floor is where the economy stalls, and moving one without measuring
## is how the AI spent a whole session gathering zero wood while its food
## pile looked perfectly healthy (D-054's `substituted` counter).
@export var food_floor: int = 180
@export var wood_floor: int = 200


## Returns "" if valid, else the reason. Called at load, so a broken
## profile fails loudly rather than producing an opponent that quietly
## does nothing — which is exactly what a zero cooldown or a zero think
## interval would produce.
func validate() -> String:
	if id == &"":
		return "ai profile has no id"
	if think_interval <= 0.0:
		return "ai profile %s thinks at or below zero seconds" % id
	if train_cooldown < 0.0:
		return "ai profile %s has a negative train cooldown" % id
	if gatherer_soldiers_wanted <= 0:
		return "ai profile %s wants no economy at all" % id
	if attack_squads_minimum < 1:
		return "ai profile %s would attack with no army" % id
	if attack_regroup_thinks <= 0.0:
		return "ai profile %s re-orders its army every think" % id
	if food_floor < 0 or wood_floor < 0:
		return "ai profile %s has a negative resource floor" % id
	return ""


func is_valid() -> bool:
	return validate() == ""
