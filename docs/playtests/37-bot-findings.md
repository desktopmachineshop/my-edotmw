# #37 — production, costs, squad cap and rally points

Bot-observation pass, 2026-08-27, worktree `ao/my-edotmw-84/root`.

Everything here drives the **real server handlers** —
`server._handle_order_produce` and `server._handle_order_rally` — over a
`LoopbackPeer`, the pattern `tests/test_civ_knobs.gd` established: a Node
that is never added to the tree does not run `_ready()`, so no socket and
no scene tree are needed. That matters for this ticket specifically,
because **every regression #37 names was in the ORDER path, not the
arithmetic** — the D-038 ownership cache refused orders to produced
squads, and D-061's rally order was never sent at all. Refusal messages
are read back off the client's `last_notice`, i.e. off the wire.

**Ticket status: LEFT OPEN.** Every server-side criterion passes; the
three that are about pixels need the owner.

---

## Checklist, classified

| # | Ticket item | Class | Outcome |
|---|---|---|---|
| 1 | Produce every unit each building offers; roster matches your civ | bot-observable | **PASS**, all six civs |
| 2 | Set a rally point; marker draws on the ground | order **PASS** / **marker needs a human** | order path clean |
| 3 | Produced squads walk to the rally unprompted | bot-observable | **PASS** |
| 4 | Queue while poor; queue while at the cap | bot-observable | **PASS** |
| 5 | Watch the n/cap HUD readout | **needs a human** | inputs verified, readout not |
| P1 | Every listed unit producible; costs deducted exactly once | bot-observable | **PASS** |
| P2 | Rally can be SET while the building is selected | **needs a human** — this is the client-side unreachable branch | order handler clean; the D-061 bug was in `client.gd` |
| P3 | Produced squads obey the rally, including untouched ones | bot-observable | **PASS** |
| P4 | Cap and affordability refuse cleanly with feedback | bot-observable | **PASS** |
| P5 | n/cap readout always matches reality | **needs a human** | |

---

## 1 / P1. Every listed archetype is producible, for every civ

`playtest_obs/obs_production.gd`, log `docs/playtests/logs/obs37-production.log`.
Each civ's town centre and barracks, every archetype in their `produces`
lists, ordered through the real handler:

```
emberdeep    town_centre:gatherers=ok general=ok | barracks: levy heavy archers ram bombard
gildedreach  town_centre:gatherers=ok general=ok | barracks: levy spearmen archers cavalry sellswords engine
gravesworn   town_centre:gatherers=ok general=ok | barracks: levy spearmen shades engine
stoneblood   town_centre:gatherers=ok general=ok | barracks: levy heavy skirmishers breaker
thornwood    town_centre:gatherers=ok general=ok | barracks: levy archers cavalry greatbow
windmarch    town_centre:gatherers=ok general=ok | barracks: levy skirmishers cavalry bowriders
```

Every one accepted. The roster resolves per civ as D-047 requires — the
barracks lists the union of 14 archetypes and each civ resolves only its
own subset, which is the intended "a civ fields a subset" behaviour and
not a gap.

## P1. Costs deducted exactly once, and all-or-nothing

Wallet before/after one order, against the def's own costs; then a wallet
**one unit short** in the resource the unit needs:

```
civ           unit                   spent      want       exact | one short: refused wallet-untouched
emberdeep     emberdeep_levy         [48,0,0,0] [48,0,0,0] true  |   true    true   "Cannot afford Hearth Levy"
gildedreach   gildedreach_levy       [45,0,0,0] [45,0,0,0] true  |   true    true   "Cannot afford City Watch"
gravesworn    gravesworn_levy        [32,0,0,0] [32,0,0,0] true  |   true    true   "Cannot afford Corpse Levy"
stoneblood    stoneblood_levy        [50,0,0,0] [50,0,0,0] true  |   true    true   "Cannot afford Hillkin Clubs"
thornwood     thornwood_levy         [40,0,0,0] [40,0,0,0] true  |   true    true   "Cannot afford Glade Wardens"
windmarch     windmarch_levy         [38,0,0,0] [38,0,0,0] true  |   true    true   "Cannot afford Colt Levy"
```

Exact deduction, no partial spend, and the refusal names the unit by its
display name.

## 4 / P4. The squad cap refuses, and names the civ's OWN cap

Roster filled to exactly the effective cap, then one more order:

```
emberdeep    base 6 -> civ cap 6  (bonus 0) | accepted=false | "At the squad cap (6) — gatherers count too"
gravesworn   base 6 -> civ cap 10 (bonus 4) | accepted=false | "At the squad cap (10) — gatherers count too"
...four more civs at bonus 0
```

`gravesworn`'s `squad_cap_bonus = 4` is read by both the refusal and the
message, which is the property #158 was after — a HUD saying 40 while the
server refuses at 44 would be a rule the player cannot see.

## 2, 3 / P3. Rally, end to end

```
rally set through _handle_order_rally: stored=(20,3) wanted=(20,3) match=true
produced emberdeep_levy as squad 0 at (16,6), destination=(20,3) obeys=true
after walking: at (20,3), arrived=true
n/cap readout inputs: living_squad_count=1 squad_cap_for=400
```

The rally is stored by the real order handler, the produced squad — which
nothing ever selected or ordered — takes the rally as its destination and
walks there. Both named regressions (D-038's ownership cache refusing
orders to produced squads; D-061's rally order never being sent) are
absent from the server path.

**P2 is not discharged by this.** D-061's bug was *in `client.gd`*:
selecting a building cleared `_selected`, and the guard against ordering
an empty selection returned before the branch that sends the rally. That
branch is reachable only by a human clicking, and this pass proves only
that the order is honoured once it is sent.

---

## What still needs the owner

1. **P2 — can the rally actually be SET from the UI?** Select a producing
   building, right-click the ground, and confirm the order leaves. This
   is the exact branch D-061 found unreachable, and nothing but clicking
   can reach it.
2. **The rally MARKER on the ground** (step 2's second half).
3. **P5 — the n/cap readout.** `living_squad_count` and `squad_cap_for`
   are the two numbers it reads and both are correct here; whether the
   HUD prints them, and keeps printing them as squads die, is unrated.
   Worth doing as **gravesworn**, whose +4 bonus is the one case where a
   stale readout would differ visibly.
4. **Feedback legibility** — the refusal strings are correct on the wire;
   whether they reach the player's eye is a client question.

---

## Artifacts

| file | what |
|---|---|
| `docs/playtests/logs/obs37-production.log` | full run, all six civs |
| `playtest_obs/obs_production.gd` | the harness |

## Filed from this ticket

None. Every server-side criterion passed.

*(The harness prints `429 ObjectDB instances were leaked at exit` — that
is the harness never freeing the `server.gd` Node it constructs, not a
finding about the game.)*
