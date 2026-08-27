**M8's first rung is BUILT as of 2026-08-27** — `just export`
produces the shipping builds (D-094 criterion 1, #178); see
`docs/status/m8-export.md`. Everything else below is still planning.

**M8 (Steam) is otherwise PLANNED but NOT BUILT** — the planning session ran on
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
