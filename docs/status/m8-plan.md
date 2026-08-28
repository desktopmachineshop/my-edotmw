**M8 (Steam) is PLANNED but NOT BUILT** — the planning session ran on
2026-08-14 and produced **D-087 through D-094**, closing every question
in the old "Blocking M7 / product-level" block (Q3, Q5, Q10, Q11, Q13,
Q14). Everything in them is design; no code, no export preset, no
Steamworks anything exists in the repo. The shape:

- **M8 is Steam-ready, not launched** (D-087). Its output is a private
  depot branch and a repeatable playtest loop; the public launch waits
  on M9's content. "Seamless" closed by inspection: one contiguous
  wrapped map, true by construction since D-008.
- **Player-hosted first, official dedicated later** (D-088, owner's
  call). The host runs the authoritative sim **in-process** — the
  loopback peer D-051's AI clients already use connects the host's own
  client; remote players arrive over Steam relay. D-042's
  reliable-ordered contract is a hard requirement on the Steam path.
  ENet stays for LAN, docker, bots and the whole test estate.
  Host-quit kills the match and the host is trusted — both accepted
  with eyes open, both fixed by dedicated-later.
- **20 players is a design target** (D-089, owner's call): Steam lobby
  browser + invites, AI seat-fill, drop-in/drop-out. No matchmaking
  service.
- **Reconnection is repossession** (D-090): disconnect hands the seat
  to an AI immediately (no grace-period limbo, no timeout — the AI is
  the grace mechanism); rejoin reclaims by **SteamID, not connection**
  (the D-038 ownership-cache lesson); desync recovery is
  drop-and-rejoin, cheap because D-025's reveal semantics make every
  join cheap. Supersedes D-033's wipe-on-disconnect for humans.
- **The server IS the anti-cheat** (D-091): no kernel AC; fog gating
  means the maphack's memory isn't there. Ranked play is explicitly
  gated on dedicated servers.
- **No saves** (D-092): reconnection + replays cover the real need;
  revisit triggers named.
- **GodotSteam behind one script** (D-093): D-021 amended by exactly
  one category (platform integration). One boundary script names
  Steam, a grep-test enforces it (the D-046-criterion-3 pattern), and
  absent Steam costs Steam features, never the game — docker and every
  test recipe stay Steam-less by construction. Still no C#.
- **Exit criteria are D-094** — ten of them, written before the code.
  The load-bearing early ones: a protocol **version handshake** (none
  exists today, and Steam's rolling updates make mixed versions
  routine) carrying SteamID seat identity, and the export→depot→install
  loop, since the headline criterion (a 20-seat match with ≥3 real
  remote humans over the real internet) needs playtesters on installed
  builds. Criterion 9 finally takes the discrete-GPU `bench-render`
  number Q15 has been waiting on. Criterion 10 is a human playing
  end-to-end through the Steam build — the D-085-criterion-14 lesson,
  applied from day one.

**Host-quit was revisited and left standing
(`D-20260828-host-quit-is-priced-against-a-match-length-nobody-has-measured`,
#289, 2026-08-28).** D-088 accepts host-quit-kills-the-match and D-092
accepts no-saves; #289 argued D-056's 1–2 hour target changes the loss.
It does not, on its own — **D-056, D-088 and D-092 were all taken on
2026-08-14, against the same target**, so the length was never the new
information.

What IS new, and neither entry could have anticipated it, is **who is in
the room**: #183's alpha loop puts a stranger hosting for strangers, and
the same PR stack notes a tester has no way to send a log back — so a
match killed by a host quitting and one killed by a bug produce the same
report, which is none.

Three things worth carrying:

- **Match length is now UNMEASURED, which is worse than either answer.**
  D-056 records matches deciding at ~200–230 s; measured 2026-08-28,
  **four of five all-AI matches did not decide at 200–300 s**, and none
  was run to a natural conclusion. The RTW programme, the map ladder and
  D-067 have each lengthened matches and nothing re-measured. The
  decision names the one number that settles this: an UNCAPPED match,
  after #159 and #206 land.
- **Migration is expensive, not dangerous, and D-088's wording implied
  the opposite.** Its "whoever inherits the server inherits omniscience"
  ground is weaker than it reads — the host already has omniscience
  (D-088 says so, D-091 accepts it for unranked), so migration widens the
  set of people who could abuse it rather than creating the surface. Its
  other ground — that authoritative-state handoff is a milestone of its
  own — stands. That reordering moves the question from "never, on
  principle" to "not yet, on cost".
- **D-092 is not an argument against migration**, and reading the two
  entries together invites treating it as one. D-092 rejected saves for
  the CEREMONY — all N agree to stop, all N return. Migration has no
  ceremony: everyone is already connected and already wants to continue.

Also rejected, and recorded because it is the idea a reader has next: a
**rejoinable replay checkpoint** is not free. The curve log is what was
SENT, not what the simulation IS — morale, fatigue, wallets, build
queues, node stocks and no-build claims are in none of it, so resuming
from a replay means adding the state snapshot D-092 already rejected.
