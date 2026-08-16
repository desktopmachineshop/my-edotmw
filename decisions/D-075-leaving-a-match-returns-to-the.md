### D-075 · 2026-08-11 · Accepted — leaving a match returns to the lobby, and no humans means no server
**Decision:** Two rules, both about the end of a session rather than the
end of a match.

**1. "Leave match" returns to the lobby.** It sends a new
`C2S_LEAVE_MATCH` and stays connected. The server ends the match, drops
the world, and re-broadcasts the seats; `MatchState` gains
`return_to_lobby()`, the one backwards edge in a phase machine that had
run `LOBBY → RUNNING → FINISHED` only. Seats survive so the next match is
one click away; everything a match *wrote* on them does not.

**2. No humans, no server.** When the last socket client disconnects, the
server shuts down and exits. AI seats explicitly do not count — they have
no socket (D-051), and a match of nothing but computers would otherwise
hold the port forever.

**Rationale:** the old "leave" was a disconnect, and its doc comment
already claimed it went "back to the lobby screen". It could not: a
disconnect tears the seat down, so there was nothing to return TO and the
player sat looking at a dead match until they closed the window. This is
D-061's shape again — a rule fully written, with a caller, whose
destination did not exist — and again only *using it* found it.

Rule 2 is not hypothetical. This session opened by clearing a server that
had been ticking an empty world **for six hours** with `clients=0`,
launched by `just run-server AI=1` — which `just` parses positionally
into `--ai=AI=1`, so `int()` read 0 and it never had an opponent either.
`_on_disconnect` already printed a summary when the last client left and
then went right on ticking.

Putting the return in `MatchState` rather than the client is what makes
the client change almost nothing: `ClientState.in_lobby()` already reads
the phase off the wire, so the lobby screen comes back on its own. A
client that could end a match locally would be a client deciding for
everybody (D-002).

**What a match writes on the lobby, and must be undone.** Each of these
is silent when wrong — a second match with the first one's civs looks
entirely normal:

- **A `Random` seat is resolved IN PLACE at start** (D-048). Without
  restoring the choice, "Random" would mean "random once, ever".
- **Registration carries an `eliminated` flag.** Kept, whoever lost match
  one would begin match two already defeated, and the victory rule would
  end it before anyone moved. It is cleared, and `_on_match_started` now
  registers every seat — humans as well as AI, which it had not done,
  because `_on_connect` was the only human registration path.
- **`_build_world` guards on `_sim != null`** and would otherwise return
  without building, leaving match two running on match one's terrain,
  spawn points, resource nodes and combat seed.
- **Entity ids restart.** Both sims mint from an array length, so match
  two's squad 0 would find match one's MultiMesh under its id.
- **The replay is the match's** (D-016), so it is closed and the next one
  opens its own file rather than truncating it.

**Rejected alternatives:**
- *Client-side only — show a disconnected lobby* (rejected: the lobby is
  server-driven, so seats, chat and settings would be inert and nothing
  could start a second match).
- *Tear down and relaunch from the `just` recipe* (rejected: a visible
  relaunch pause, and it only works for sessions started that way, not a
  client connected to a remote server).
- *Ending the server the moment the match is left* (rejected: it makes
  "return to the lobby" a dead screen in exactly the solo-versus-AI
  session this exists to serve).

**Consequences:** one human leaving returns the **whole match** to the
lobby, evicting everyone. That is right for solo-versus-AI and wrong for
several humans, and it is the known limit of "for now" — a per-player
leave needs a spectator-or-seated state that does not exist.

`just lobby` and `quick-test` dropped `--rm`, because a server that exits
by itself would take its own log with it; the trap's `just down` still
removes the container by project label.

Two adjacent defects fixed in passing, both on the path being changed:
`_on_disconnect` called `_sim.replicator` unconditionally and would have
crashed on a lobby disconnect, which was survivable only while leaving
always meant leaving a RUNNING match; and `remove_human_seat` had no
caller outside its own test — the **fifth** declared-and-unread member
after `UnitDef.cost`, `BuildingDef.cost`, `BuildingSim.damage()` and the
three `CivDef` knobs — so a human who dropped from a lobby kept their
seat forever and the admin role never passed on.

**Revisit trigger:** the first match with two humans in it. At that point
"leave" has to become per-player and this entry is reopened, not patched.

**Amendment, 2026-08-16 — the second match had no ground** (issue #57,
found in the #29 lobby playtest). Everything above about what a match
writes on the lobby was about *state*; this was about a *node*.
`_teardown_match()` freed `_terrain_root` — correctly, for the reason
given there: the lobby can change size, seed and preset between matches
(D-049), so a kept mesh is only correct until somebody moves a slider.
But the root was constructed exactly once, in `client.gd`'s `_ready()`,
and nothing rebuilt it. Every match after a return to the lobby parented
its chunk meshes to a null instance and drew squads and forests standing
on nothing.

Two things worth carrying:

- **It was invisible to every number**, in the way D-096 and M7 both
  were. The meshes really were built; the capture verdict's
  `terrain=true` is set by the *caller* of `_build_terrain()` and stays
  true whether or not the function got past its first `add_child`. Only a
  picture of a SECOND match shows it.
- **The fix is ownership, not a null check placed anywhere.**
  `_build_terrain()` now mints the root as well as the chunks, and
  `_ready()` no longer touches it, so the builder is self-sufficient
  rather than depending on an initialisation that ran an unknown number
  of matches ago. That is the same shape as the teardown's own rule:
  whoever frees a thing and whoever builds it have to agree about what
  "a thing" is.

`client.gd` is native-only (D-014) and this file and CLAUDE.md both say
the client is unreachable from GUT — which was read as "all of it" and is
only true of what it DRAWS. Its node LIFETIME needs neither a GPU nor a
window: `_build_terrain()` and `_teardown_match()` null-guard every node
they touch, so `tests/test_return_to_lobby.gd` now instantiates the real
script (never adding it to the tree, so `_ready()` does not run) and
plays match → lobby → match against it. Both new tests were observed to
fail before the fix.

---
