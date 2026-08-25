# D-20260821 · A recruit steps out of the door nearest his rally point

**Status:** ACCEPTED — the owner's playtest request (2026-08-21): *"when
units spawn from a building have them appear on the side closest to
where the roster point is instead of the opposite side and have to walk
around."* **Extends:** D-039/D-060's spawn-placement family;
`BuildingSim.rally_of` (the default-or-set rally that already exists).

## The defect

`SquadSim._spawn_cell_near` picked the FIRST free cell at ring ≥ 2 in
`TorusSpace.disk_offsets`' fixed enumeration order. That order starts at
the disk's dq-minimum, so which side of the building a new squad
appeared on was an accident of the lattice — routinely the side facing
AWAY from the rally point, after which the squad's own move order
marched it around the building it was just made in.

## The rule

Among the free cells at the smallest workable ring, a new squad appears
at the one CLOSEST to the building's rally point (toroidal hex
distance). The ring still takes priority over the bearing — a squad
stands at the door before it stands two cells further out on a better
bearing — and `rally_of` already answers with the default forward point
when no rally was ever set, so every building has a "near side" by
construction.

Determinism is preserved, which is what makes this legal on the
authoritative side at all: the enumeration order is fixed, the
improvement test is strict (`<`), so ties resolve to the earlier
candidate and server and replay still agree about where a unit
appeared.

## Rejected alternatives

- **Doing it client-side as a render nicety.** The spawn cell is
  authoritative state — the squad's curve starts there — so a client
  that drew the near side while the sim used the far side would desync
  the drawn walk from the real one. This is a sim decision or nothing.
- **Spawning ON the rally bearing regardless of blockage.** The
  existing free-cell/ring walk exists because doors get blocked; the
  bearing is a preference within it, not a replacement for it.

## Revisit trigger

If spawn placement ever needs to consider the building's authored door
geometry (mesh yaw), that supersedes the rally bearing — a door is a
stronger fact than a preference.
