extends Resource
class_name FormationDef

## A formation, as data (D-058, against D-010). New formations are added
## as .tres files under /formations/, never as a new branch in
## formation.gd or a new entry in a hardcoded list.
##
## ## What is data and what cannot be
##
## The GEOMETRY KIND is an algorithm — "a grid", "a scattered grid",
## "concentric rings", "a triangle" — and an algorithm cannot live in a
## text file. What is data is which kinds exist as formations, what they
## are called, how they are parameterised, and which of them a player is
## offered. That is the same split `UnitDef` makes: `mesh_primitive`
## chooses among generators the engine implements, while every number
## around it is in the file.
##
## So adding "column of four at double spacing" is a .tres. Adding a
## spiral is a new `kind` plus a .tres — and the test that every offered
## formation resolves to an implemented kind is what stops the first half
## of that being done without the second.
##
## ## Why this is not just a list of names
##
## `Formation.slot_offset` used to hold the ranks, the spacing multipliers
## and the scatter amount as literals, and the offered set as a `const`
## Array. Every one of those is a tuning number somebody balancing the
## game should be able to move without editing a script, which is the
## whole premise of D-010 and of this project being editable by Claude
## Code without the Godot GUI.

@export var id: StringName
@export var display_name: String = ""

## Which geometry generator this formation uses. Adding a value here means
## implementing it in `Formation._offset_for` — the roster test fails
## loudly if a .tres names a kind nothing implements, rather than falling
## through to a line and looking merely wrong.
@export_enum("grid", "scatter", "wedge", "ring") var kind: String = "grid"

## Multiplies the unit's own `formation_spacing`, so a formation is
## tighter or looser than that unit's natural order without every UnitDef
## needing to know about every formation.
@export var spacing_scale: float = 1.0

## grid only: how many ranks deep. A line is defined by its depth.
@export var ranks: int = 0

## grid only: how many files wide. A column is defined by its width.
##
## Both zero means SQUARE — files and ranks derived from the headcount,
## which is what `tight` wants and what keeps a big squad from becoming a
## single absurd rank. Setting both is a contradiction; `ranks` wins, and
## the roster test says so rather than leaving it to discovery.
@export var files: int = 0

## scatter only: how far a soldier may sit from his slot, as a fraction of
## spacing. Deterministic, hashed from the slot index — never random, or
## client and server would disagree about where everyone is standing.
@export var jitter: float = 0.0

## Whether a player may choose this one. `line`, `column` and `wedge` are
## implemented and available to UnitDefs as defaults without cluttering a
## three-button row.
@export var offered: bool = false

## Sort order in the UI, so the offered set has a deliberate order rather
## than whatever the filesystem returns.
@export var order: int = 0
