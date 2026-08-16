### D-071 · 2026-08-04 · Provisional — the civ design frame, and six civilizations
**Decision:** Six civs at launch, each filling the **same seven-column
frame** so that distinctness is structural rather than a matter of taste.
Governing rule: **no two civs may match on more than one column.**

| | Legion | Northmen | Magyars | Byzantines | Carthaginians | Chinese |
|---|---|---|---|---|---|---|
| **Axis** | quality | quantity | mobility | fortification & siege | economy & flexibility | ranged attrition |
| **Basis** | Rome, Republic → Late Empire | Norse, 790–1100 | Magyar confederation → Kingdom of Hungary | Eastern Rome, 330–1200 | Phoenician-Punic world, 800–146 BC | Warring States → Tang |
| **Economy** | steady; strong from few well-held sites | raid-supplemented; profits from wrecking yours | low infrastructure early, settles late | slow, secure, stone-heavy | highest gather and the broadest use of gold | infrastructure-heavy, food-led |
| **Military** | heavy foot + disciplined missile; no light horse | cheap fast foot + skirmishers; no heavy foot | horse archers and light horse; poor foot, no siege | defensive foot, towers, engines | the broadest roster, most of it costing gold | massed crossbow; adequate foot, weak horse |
| **Best at** | winning even fights; holding a line | early tempo; raiding economy | map control; punishing overextension | holding ground *and* cracking it | out-scaling; adapting late | grinding down at distance |
| **Bad at** | reacting; map control | pitched battles; sieges | taking fortified ground | open field; early tempo | any specific fight before it is rich | being closed on |
| **Signature (epoch)** | *comitatenses* — highest morale in the game (E4) | Great Heathen Army — cap and tempo bonus (E2) | mounted missile at reach (E3) | the siege train (E4) | mercenaries — most archetypes, gold-priced (E3) | crossbow volley — earliest strong missile (E2) |

**Frame audit.** The two closest pairs, checked rather than assumed:
*Byzantines and Chinese* both defend prepared positions, but one holds
with structures and also **cracks** them, the other holds with fire and
cannot crack anything — one shared column. *Northmen and Magyars* both
raid, but one raids on foot with tempo and the other cannot be caught at
all — one shared column. Rule holds.

**Rationale for the specific factions — the arc test.** With five epochs
and replacement rosters (D-070), a faction needs **five believable
development stages**, not one iconic army. That constraint, not
recognisability, selected this set:

| Civ | settle → field → hold → break → decide |
|---|---|
| Legion | village → manipular Republic → Marian legion → Imperial → Late Roman *comitatenses* |
| Northmen | steading → raiding parties → Great Heathen Army → jarldoms and burhs → Norman-influenced heavy horse |
| Magyars | nomad clans → horse-archer confederation → raids on Europe → settled Kingdom → knights *and* horse archers |
| Byzantines | late Roman town → Justinianic reconquest → *thematic* system → Macedonian dynasty → Komnenian |
| Carthaginians | Phoenician colony → trading city → Punic mercantile empire → mercenary armies → Barcid Spain |
| Chinese | Warring States → Qin/Han crossbow volley → Three Kingdoms → Sui/Tang → Song-era massed missile |

**Scythians fail this outright** and were rejected for it despite being
the purest horse-archer culture available: nomadic throughout, with no
fortification phase to grow into, so epochs 3–5 would have to be invented
wholesale. Magyars genuinely settle, and that transition **is** their
epoch 4.

**The dates do not line up, and this entry does not pretend they do.**
Rome and the Northmen never met. Carthage is destroyed in 146 BC and has
no historical epoch 4 or 5 at all; its late rungs run through mercenary
armies and Barcid Spain. **The ladder is a game progression, not a shared
calendar** — each civ's five rungs are flavoured from that culture's own
arc, independent of absolute date. This is the AoE convention, adopted
deliberately and stated so nobody has to rediscover it in review.

**Known flavour redundancy, accepted with eyes open: Byzantines are
Rome.** Mechanically they are cleanly distinct from Legion — defensive
doctrine and engineering versus manipular quality — but two Roman civs in
a six-civ launch roster is something a reviewer will notice.
**Sassanids** are the alternate and avoid it entirely while giving Legion
a natural rival; the cost is that they pull hard toward cataphracts and
start colliding with the Magyars' cavalry column. Also verified clean:
Huns and Scythians (mobility), Assyrians (fortification), Kushites
(ranged).

**All six ids verified against `tests/test_civs.gd:43`** — a raw
substring match of each civ id against every non-test, non-addon `.gd`
file, comments included. `grep -ril <id> --include=*.gd .` returns
nothing for all six. This was checked *before* the names were chosen, not
after, because a late collision means renaming a civ everywhere.

**Rejected alternatives:** *English longbowmen for the ranged slot*
(rejected — the longbow is a 1300s+ weapon, past the chosen span, and
cannot carry epochs 1–3). *Venetians or Genoese for the mercantile slot*
(rejected — no antiquity end; they do not exist before ~700 AD).

**Consequences:** `tests/test_civs.gd:170` draws 4000 random civs and
expects an even split; at six civs the expectation moves to ~667 with a
±15% band. Tests that index `CivRoster.ids()[0]`/`[1]` compare a
different pair once the roster is sorted with six names in it. Both need
updating with the roster, and both are test-only changes.

**Revisit trigger:** the first civ whose identity cannot be expressed
through a knob every civ has (D-073). That is D-047's revisit trigger
inherited, and it is the line between six civs and six special cases.

---
