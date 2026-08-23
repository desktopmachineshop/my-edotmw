### D-20260823-fantasy-civs-on-a-four-epoch-ladder · 2026-08-23 · Provisional — the civ roster is fantasy, and the ladder runs medieval → imperial → modern → futuristic

**Supersedes D-069 (the five-rung antiquity-to-medieval ladder) and
D-071 (six historical civs).** Owner's call, 2026-08-23: the setting is
fantasy, not history, and the epoch ladder spans **medieval → imperial →
modern → futuristic** — the *Empires: Dawn of the Modern World* shape this
project was named for, carried one rung past it. D-070 (rosters grow by
replacement), D-068 (upkeep) and D-072 (the power budget) are unchanged
and still the derivation base; D-047 (civs are data, mechanical
differences are knobs every civ has) is the rule this entry is written
under and does not touch.

**Nothing in code or `.tres` changes with this entry.** M9 is still
planned and not built; this is the specification it builds to, exactly as
D-069–D-074 were. The two shipped civs keep their ids until M9's first
slice lands (see *Migration*).

---

#### The ladder: four epochs, each a new verb

D-069 rejected four epochs because "each rung stretched past the point
where its content stays interesting" — which was true of a span that ends
at the high medieval period, where rungs 3 and 4 had to be *hold* and
*break* split apart to fill the count. A span that crosses gunpowder,
industry and energy weapons has no such problem: **every rung changes what
an army IS**, not merely how hard it hits, and the new-verb filter D-069
wrote passes all four without a split.

| # | Epoch | The epoch is when… | Verb | What arrives | Player time |
|---|---|---|---|---|---|
| 1 | **Medieval** | …a place and a standing army become possible. Town hall, gatherers, levy, the counter triangle in steel (spear / sword / missile), light horse. | settle & field | everything that ships today | 0–25 |
| 2 | **Imperial** | …**holding ground and breaking it** become possible, together. Powder: musket lines, cannon, star-forts and walls worth the name; horse at its peak and about to be obsolete. | hold & break | gunpowder foot, artillery, fortress tier, heavy cavalry | 25–50 |
| 3 | **Modern** | …**the machine replaces the animal and the wall.** Rifles, machine guns, field artillery at reach, armour, engines. Range and attrition decide; cavalry dies or mechanises. | reach | armour, mechanised transport, indirect fire, air scouting | 50–75 |
| 4 | **Futuristic** | …**scarce and decisive** technology. Energy weapons, hover and flight, shields, each civ's signature war-machine. | decide | elite tech units, the signature, the late super-building | 75+ |

**D-069's matched pair survives as one rung.** Imperial delivers *hold*
(fortresses, walls — D-076 exists now, so the fence D-069 put round walls
is gone) and *break* (cannon) in the same epoch, which is what kills the
turtle-to-last-epoch failure more cleanly than two rungs did: there is
never a state where ground is holdable and not yet breakable.

**The advance gate is unchanged in kind** — `/epochs/*.tres`, researched
at a town centre, no script names an epoch. Costs re-derived from D-069's
table at four gates instead of five, keeping its rule that the last
advance is priced above the biggest measured un-spent bank (2,480, D-056):

| Advance | food | wood | gold | stone | research |
|---|---|---|---|---|---|
| Medieval → Imperial | 600 | 400 | 100 | — | 100 s |
| Imperial → Modern | 1100 | 700 | 400 | 200 | 140 s |
| Modern → Futuristic | 1800 | 1200 | 900 | 500 | 180 s |

Provisional and to be replaced by telemetry, as before.

**The archetype vocabulary** grows from 8 to roughly 22–26 across four
rungs (D-069 estimated 25–30 across five); D-074's unlock-overload
detection still applies and the train UI still has to become
epoch-scoped.

---

#### The civs: six, on D-071's seven-column frame

The frame is kept whole because it was never about history — it is what
makes distinctness structural. **Governing rule unchanged: no two civs
may match on more than one column.** The six mechanical AXES are
retained verbatim from D-071, so every knob a civ already has (D-047,
D-073) still has a civ asking for it; only the *basis* column is
replaced.

| | Dominion | Warhost | Centaurs | Deepholds | Gilded | Sylvans |
|---|---|---|---|---|---|---|
| **Axis** | quality | quantity | mobility | fortification & siege | economy & flexibility | ranged attrition |
| **Basis** | a human empire — disciplined, centralised, ordered | orc clans — brute numbers, scavenged iron, tribal rage | centaur herds of the open steppe | dwarven mountain-holds — stone, forge, engineering | goblin trade-compact — bankers, brokers, mercenaries | elven forest realm — long lives, long bows, longer memory |
| **Economy** | steady; strong from few well-held sites | raid-supplemented; profits from wrecking yours | low infrastructure early, settles late | slow, secure, stone-heavy | highest gather and the broadest use of gold | infrastructure-heavy, food-led |
| **Military** | heavy foot + disciplined missile; no light horse | cheap fast foot + skirmishers; no heavy foot | fast missile-and-lance herds; poor foot, no siege | defensive foot, engines, the best walls | the broadest roster, most of it gold-priced | massed missile; adequate foot, weak horse |
| **Best at** | winning even fights; holding a line | early tempo; raiding economy | map control; punishing overextension | holding ground *and* cracking it | out-scaling; adapting late | grinding down at distance |
| **Bad at** | reacting; map control | pitched battles; sieges | taking fortified ground | open field; early tempo | any specific fight before it is rich | being closed on |
| **Signature (epoch)** | the Iron Legion — highest morale in the game (E3) | the Horde — cap and tempo bonus (E1) | mounted missile at reach (E2) | the siege train (E2) | mercenaries — most archetypes, gold-priced (E2) | the volley — earliest strong missile (E1) |

**Frame audit**, the two closest pairs checked rather than assumed:
*Deepholds and Sylvans* both defend prepared positions — one with stone
and cracks stone, the other with fire and cracks nothing; one shared
column. *Warhost and Centaurs* both raid — one on foot with tempo, the
other cannot be caught; one shared column. Rule holds, as it did for the
historical set it mirrors.

**The arc test, at four rungs.** D-071's reason for choosing factions was
that each needs a believable development stage per epoch. A fantasy race
has the advantage that its arc can be *designed* rather than found, and
the obligation that it be designed deliberately — so each row is written
down, and it is also the flavour brief every image board and every model
is authored against:

| Civ | Medieval | Imperial | Modern | Futuristic |
|---|---|---|---|---|
| **Dominion** | steel-and-tabard men-at-arms, longbow, knights | redcoat musket lines, field guns, cuirassiers under the eagle | greatcoats and rifles, machine-gun companies, riveted steel tanks | power-armoured Iron Legion, rail rifles, walker tanks |
| **Warhost** | grunts, pike-brutes, wolf riders, the warchief | blunderbuss mobs, scrap cannon, war-boar shock cavalry | scrap-iron half-tracks, belt-fed "choppas", fume-belching rust armour | looted energy weapons bolted to anything, burner-jets, the Doom Engine |
| **Centaurs** | lance and bow herds, no town to speak of | dragoon herds — carbine at the gallop, horse-drawn light guns | mechanised "iron herds": motorcycle-born scouts, armoured cars, mobile artillery | hover-skimmers, rail lances, gravity cavalry |
| **Deepholds** | shieldwall, crossbow, the first stone walls | bombards, grenadiers, star-forts cut into rock | steam-armour, heavy howitzers, tunnelling engines | sealed bulwark suits, siege beams, the mountain-fortress crawler |
| **Gilded** | hired blades of every kind, a counting-house for a hall | mercenary regiments, privateers' guns, a mint | contract armies, armoured trains, the bank as a super-building | drone swarms bought by the thousand, orbital broker, the Exchange |
| **Sylvans** | longbow volley, glaive foot, stag riders | rifled long-guns, ranger corps, living-wood palisades | sharpshooter battalions, grown artillery, canopy gliders | lightline archers, spirit-shield groves, the Worldtree |

**All six ids verified** against every non-test, non-addon `.gd` file the
way D-071 did (`grep -ril <id> --include=*.gd`), comments included,
2026-08-23: `dominion`, `warhost`, `centaurs`, `deepholds`, `gilded`,
`sylvans` return nothing. Checked before the names were chosen, not
after.

---

**Rejected alternatives:**
- *Keep D-069's five rungs and fantasy-skin them.* Rejected — five rungs
  across medieval→futuristic forces a split somewhere (early-modern vs
  industrial, or near- vs far-future) that fails the new-verb filter
  exactly the way D-069 said a sixth historical rung would.
- *Undead as the sixth civ instead of the Gilded.* Rejected — undead pull
  hard toward quantity AND attrition, colliding with the Warhost on one
  column and the Sylvans on another; the frame has no empty axis for
  them. They are the first candidate if a seventh civ is ever wanted and
  an axis is found for it.
- *Per-civ ladders (e.g. Sylvans never industrialise).* Rejected for
  D-069's reason: it breaks the shared advance gate that makes "who is
  ahead" legible to players and the AI. A civ's *flavour* of Modern may
  be grown rather than forged; its *gate* is the same.
- *Dragons, giants, hero units.* Still fenced out, as D-069 fenced heroes:
  a single-entity super-unit is per-unit simulation in disguise (D-005).
  The futuristic signature is a *squad* or a *building*, never a hero.

**Consequences:**
- D-069 and D-071 are superseded; D-070, D-072, D-073, D-074 stand and are
  re-read with four rungs in place of five. D-072's epoch-1 vertical slice
  is now **Medieval** and is, to a close approximation, the roster that
  already ships.
- The content bill (D-070) drops from 90–130 unit `.tres` to roughly
  **70–100** at six civs × four rungs.
- `CivDef.epoch_names` (D-070's proposed schema) carries four strings, not
  five.
- *Migration:* the shipped `legion` and `northmen` civs are the Dominion
  and the Warhost by axis. Renaming their ids and re-skinning their
  archetypes is M9's first slice, not this entry; until then the two ids
  stay and nothing referencing them moves. The `tests/test_civs.gd`
  consequences D-071 listed (the 4000-draw split, the `ids()[0]/[1]`
  pair) are unchanged in shape.
- Every art brief — image boards, authored `.blend` files — is written
  against the arc table above, so a model can be checked against what its
  civ is supposed to look like in that epoch.

**Revisit trigger:** D-069's, unchanged — any rung that telemetry shows is
entered and left without the player's behaviour changing is a stat bump,
not an epoch, and merges into its neighbour. And D-071's — the first civ
whose identity cannot be expressed through a knob every civ has.

---
