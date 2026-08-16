### D-066 · 2026-08-04 · Provisional — building damage is on its own scale, and was authored on the wrong one
**Decision:** `BuildingDef.damage` raised on both shipped shooters. First
pass, on evidence that the defence was invisible: town centre **12 → 45**,
watch tower **20 → 80**. **Superseded within the day by D-067**, which
raised them again (60, and 85 at 1700 HP) to meet an explicit anti-rush
rule — read D-067 for the shipped values. No code change in either: the
mechanism was never broken.

**The report was "the town hall was meant to have some ranged defensive
ability but doesn't seem to".** It has one, and it fires: measured, a
shipped town centre engages at 4 cells, on schedule, every 2 s. It simply
did almost nothing.

**The cause is a scale mismatch between two fields with the same name.**
A squad's volley is `UnitDef.damage x alive` — 36 militia at 9.5 is
**342 per second**. A building fires one flat `BuildingDef.damage`,
multiplied by nothing: a town centre was **6 per second**, or 1.8% of one
squad. The numbers look comparable in the `.tres` files; they are a
factor of ~40 apart. Measured, one militia squad against each shipped
defence, no support on either side (the "after" column is this pass's
45/80, not the shipped values — see D-067):

| | before | this pass |
|---|---|---|
| town centre razed in | 63 s, costing **4 of 36** | 82 s, costing **20 of 36** |
| tower razed in | 30 s, costing **4 of 36** | 44 s, costing **26 of 36** |

**Why not higher.** At 65 the town centre wipes a lone militia squad and
survives on 408 of 3000 — which matches the code comment's intent ("an
early rush cannot simply walk into a base"), and is deliberately NOT what
shipped. D-055 is the reason: this project has already had every ladder
match end in a draw because buildings could not be destroyed, and read it
as an AI weakness for several rounds. Defence that is *felt* is the goal;
defence that *repels* trades a real risk to decidability for it. 45 keeps
a lone squad able to take a town centre while losing over half its men.
Raising it further is a live option and a one-line data change.

**Why the tower is 80.** It is bought with 120 stone and is the only
building whose purpose is fighting, so attacking it must be decisively
worse than attacking the town centre you start with — otherwise nobody
builds one. It still falls to a single squad in ~44 s, which keeps a
tower a delay rather than a wall.

**The test gap this went through, which is the part worth keeping.** The
buildings-shoot tests all used a synthetic def — damage 40, a 0.1 s
interval, 20 HP defenders — chosen so a five-tick test can observe a
casualty. They prove the MECHANISM and are silent about the shipped
numbers, and the only test that touched the real `.tres` asserted
`damage > 0`. So: mechanism correct, data nonzero, feature invisible,
everything green. Two tests now run a whole encounter with shipped defs
and assert what it COSTS an attacker, as a floor (a third of the squad
for a town centre, half for a tower) rather than an exact number, so
ordinary tuning does not thrash them.

**Rejected alternatives:**
- *Scaling building damage by something, so the two fields read alike*
  (rejected — a building has no `alive`; the honest fix is to document
  the scale, which `building_def.gd` now does at the field).
- *Leaving it and calling it balance* (rejected — the owner reported it
  as a missing feature, which is what a 1.8%-of-a-squad defence is).
- *Raising building damage generally* (rejected — barracks and storehouse
  are targets by design, and that is D-032's data-driven point).

**Consequences:** attacking into a base is now a real cost, so matches
lengthen — the direction D-056 wants, though nowhere near its 1–2 hours,
and for D-056's own reason: there is still no progression to spend the
time on. AI ladder behaviour is affected and was checked for
decidability, not tuned for.

**Revisit trigger:** if ladder matches start drawing at the time cap
again, this is the first number to look at — and D-055's lesson says
check whether anything can still die before concluding the AI is weak.

---
