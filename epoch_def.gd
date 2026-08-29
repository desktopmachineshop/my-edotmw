class_name EpochDef
extends Resource

## One rung of the ladder, as data.
##
## `D-20260828-the-epoch-ladder` is THE description of the ladder — what
## the rungs are, what advances you, and what that costs. This file is
## D-069's `/epochs/*.tres`, delivered by
## `D-20260827-the-tree-is-the-ladder`.
##
## ## What is NOT here, and it is the whole point
##
## No cost, no research time, no prerequisite buildings. D-069 put all of
## those here, because an epoch was a thing you BOUGHT. It is not: an
## epoch is a thing you have ARRIVED at, by completing the `defining`
## techs of the rung below. So this resource carries only what an epoch
## IS — its number, its name, and the verb that says what it changed —
## and the ladder's arithmetic lives entirely in `/techs`.
##
## That is also what makes the rung COUNT cheap to change. Collapsing five
## rungs to four is deleting one of these files and moving a `defining`
## flag on ten techs. No script names an epoch, so no script changes.

## 1-based. Epoch 1 is where every player starts.
@export var index: int = 1

## What a player reads: "The Founding", "The Mustering", ...
## A civ may override this with its own word through `CivDef.epoch_names`.
@export var display_name: String = ""

## D-069's new-verb filter, kept as data so it is visible rather than
## remembered: "a rung whose honest one-line justification is 'the stats
## go up' was cut rather than rewritten."
@export var verb: String = ""

## One line: what becomes possible here.
@export_multiline var summary: String = ""


func validate() -> String:
	if index < 1:
		return "epoch has index %d" % index
	if display_name == "":
		return "epoch %d has no display name" % index
	if verb == "":
		return "epoch %d names no verb — see D-069's filter" % index
	return ""
