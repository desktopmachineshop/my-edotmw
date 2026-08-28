extends RefCounted
class_name AiInvestment

## What an AI has to DO to acquire a capability it does not have yet, and
## which step of it is next (naval plan §6.1, #301; #337 for walls).
##
## ## Why this exists at all
##
## D-076 shipped walls, gates and a walkable wall-top tier, and its own
## entry ends: *"no AI behaviour for building or using walls/gates exists
## yet — `just ai-ladder` cannot exercise any of this feature until an AI
## player is taught to want one."* Sixteen days later that was still
## true, and it is exactly why #210 (an auto gate never opened for an
## ally) sat undetected: **the estate had no way to run the feature.**
## #337 is that same gap, filed again.
##
## Naval is the second feature to need the same thing, which is what
## makes the shape worth naming rather than writing twice. An investment
## is always the same four questions:
##
##   1. **Do I need this?** A trigger read off what the AI KNOWS.
##   2. **Have I got it?** Otherwise the AI re-buys it every think.
##   3. **What is the next unmet step?** Building, then unit, then use.
##   4. **How committed am I?** A profile knob, never a bonus.
##
## ## What this deliberately is not
##
## It is not a planner, a goal stack or a behaviour tree. It answers ONE
## question — which step is next — from a list the caller supplies, and
## it holds no state. Everything clever stays in the caller, where it can
## be read beside the rest of that feature's reasoning; the alternative
## is a framework that has to be understood before either feature can be.
##
## All-static and pure, for `bot_patrol.gd`'s reason: the half of an AI
## with the interesting failure mode should be testable without a server.


## A step of an investment. `done` is a Callable taking no arguments and
## returning bool — "is this already true?" — and `act` is what to do
## when it is not.
##
## `label` is not decoration: it is what the harness counts and what a
## human reads when a gate reports which leg broke. `landings = 0` is
## what a free-for-all, an unplayed match and a broken transport all
## report, so the step names are how a zero says WHICH.
static func step(label: String, done: Callable, act: Callable) -> Dictionary:
	return {"label": label, "done": done, "act": act}


## The first step that is not done yet, or an empty Dictionary when the
## investment is complete.
##
## In ORDER, and short-circuiting: an AI that trained a transport before
## it had a dock to train it from would spend the money and get nothing.
## The order is the plan.
static func next_step(steps: Array) -> Dictionary:
	for entry in steps:
		var done: Callable = entry["done"]
		if not done.call():
			return entry
	return {}


## How far through an investment the AI has got, for the stats line.
##
## Reported rather than merely used, because "the AI is doing nothing"
## and "the AI is stuck on step 2" look identical from outside — and
## D-076's gap was invisible for sixteen days precisely because nothing
## reported it.
static func progress(steps: Array) -> int:
	var done_count := 0
	for entry in steps:
		var done: Callable = entry["done"]
		if not done.call():
			break
		done_count += 1
	return done_count


## Whether an AI should pursue an investment at all this think.
##
## `wanted` is the trigger — "is there an enemy I cannot walk to?" for
## naval, "am I being raided at home?" for walls. `commitment` is the
## profile knob (D-20260818-ai-profiles-are-data): a number in 0..1 that
## decides how much of the army is willing, never what the AI KNOWS or is
## GIVEN. A profile with `0.0` simply never invests, which is a
## difficulty setting and not a handicap.
##
## The two are separate arguments rather than one because they fail
## differently and a gate needs to tell them apart: `wanted == false` is
## "this map does not call for it", `commitment == 0.0` is "this
## difficulty does not do it".
static func should_invest(wanted: bool, commitment: float) -> bool:
	return wanted and commitment > 0.0


## How many of `available` squads this investment may claim.
##
## Rounded DOWN, with a floor of ONE whenever the commitment is above
## zero: an investment allowed to take a fraction that rounds to zero is
## an investment that reports itself active and never moves, which is the
## shape of every silent AI gap this file exists to prevent.
##
## Zero commitment is the one case that returns zero, and it has to be
## checked HERE rather than left to the caller. The first version said
## "a caller that wants none never reaches here" and `AiNaval.sailing_party`
## reached here with 0.0 on its very first test — a profile that had
## declined to sail put one squad to sea anyway. The rule and the
## guard belong in the same function.
static func share_of(available: int, commitment: float) -> int:
	if available <= 0 or commitment <= 0.0:
		return 0
	return clampi(int(floor(float(available) * clampf(commitment, 0.0, 1.0))), 1, available)
