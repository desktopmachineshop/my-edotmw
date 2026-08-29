### D-20260828 · Accepted — a summary is shown, or it is deleted

**Decision:** Two `@export_multiline var summary` fields shipped with doc
comments saying they are "shown in the lobby so a player choosing X knows
what they are picking", and the lobby has never shown either (#214). Each
is resolved, in the direction its own claim can actually be honoured:

- **`CivDef.summary` gets its reader.** The lobby's per-seat civ picker
  carries the selected civ's pitch as its tooltip — the control a player
  chooses a civ WITH now says what the choice means. `client.gd`'s
  `_civ_summary()` sits beside the `_civ_label()`/`_civ_colour()` pair
  that were already there, and `tests/test_civs.gd` scans for the call,
  the D-106 caller-exists pattern.
- **`AiProfileDef.summary` is DELETED**, and its three pitches move into
  `docs/status/ai-opponent.md` so nothing written is lost. There is no
  control to attach it to and none is close: per-seat difficulty
  selection is the first unbuilt item on that page's own list, `MatchState`
  has no notion of a profile at all (profiles are dealt by `server.gd`
  from `--ai-profiles` at seating time), and the lobby wire carries
  nothing that could name one. A field kept "for the lobby" that the
  lobby has never shown is exactly what teaches the next reader to
  distrust the next comment.

The seven files carrying a raw **cp1252 `0x97`** in those fields (#231:
all six `civs/*.tres`, plus `ai/cautious.tres`) are re-encoded to UTF-8,
and `tests/test_data_encoding.gd` fails on any shipped `.tres`, `.gd`,
`.tscn` or `.gdshader` that is not valid UTF-8.

---

**Rationale.** Both halves of #214 are the same defect wearing two shapes,
and neither could be seen from the other:

- **Declared and unread** — the sixth instance, after `UnitDef.cost`,
  `BuildingDef.cost`, `BuildingSim.damage()` (D-055: no match could be won
  for two milestones), the three `CivDef` knobs (#158) and `client.gd`'s
  `_explored` set (D-106).
- **The corruption was invisible BECAUSE the field was unread.** Godot
  printed `Unicode parsing error … Invalid UTF-8 leading byte (97)`
  twelve times on every load of the roster — server, client, bot and test
  run alike — for as long as the six civs have existed. Nobody read it,
  because it is one line of noise in a log nothing gates on.

**A tooltip is a real reader, and the alternative was worse.** A blurb
label in the lobby's own preview column would be the more visible answer
and would move `LobbyLayout.DESIGN_HEIGHT`, which
D-20260817-lobby-fits-the-window pins with a test that BUILDS the lobby
and measures it — for good reason, since that page has already run off the
bottom of a window once. Spending that on flavour text is the wrong
trade; the tooltip costs no layout at all and hangs the text on the exact
control the choice is made with.

**The guard is a source scan, because that is the only thing that can see
this.** No behaviour fails on a corrupt byte and no behaviour fails on an
unread field, so the check has to be about the FILES and about the
CALLERS. Both were observed to fail before being trusted: putting the
`0x97` back reds the encoding test, and removing the tooltip assignment
reds the caller scan.

---

**Rejected alternatives:**

- *Fix the encoding and leave both fields unread.* #214 names this
  explicitly as acceptable-but-only-if-deliberate. Rejected: it fixes the
  symptom that shouted and leaves the defect that was silent, and the
  silent one is the one this project keeps paying for.
- *Delete `CivDef.summary` too.* Rejected — six civs whose whole design is
  six distinct identities (`docs/status/fantasy-civs.md`) and a lobby that
  tells a player nothing about any of them is a real gap, and the pitches
  are already written and good.
- *Keep `AiProfileDef.summary` "for when the lobby gets a difficulty
  picker".* Rejected, and this is the load-bearing half of the entry: that
  is the argument that has kept every previous member of this defect class
  alive. When per-seat selection lands it will need a seat field, a wire
  field and a control; adding one more `.tres` line at that point is the
  cheapest part of it.

---

**Consequences:**

- **`tests/test_ai_profiles.gd`'s `assert_ne(def.summary, "")` goes with
  the field.** Worth naming, because that assert is *why* this survived
  review: it asserted the field was non-empty and never looked at what was
  in it, so a test was green over a string containing a replacement
  character, describing a lobby that did not exist.
- **The encoding test covers a CLASS of files, not the seven that were
  wrong.** D-106's own caveat is that a caller-exists scan only covers the
  callers it names; the same applies here, so this scans every shipped
  text asset rather than the ones this issue found.
- **`ai/cautious.tres` loses two lines** (the field and its value) and the
  other two profiles lose nothing, because only `cautious` ever carried a
  corrupt byte — the other two summaries were plain ASCII and are moved to
  the status page with it.

**Revisit trigger:** per-seat AI difficulty selection landing
(`docs/status/ai-opponent.md`'s first unbuilt item). At that point
`AiProfileDef.summary` comes back **with its reader in the same commit**,
which is the whole rule this entry exists to state.

---
