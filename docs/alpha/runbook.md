# Alpha runbook — hosting a server testers can reach

The pre-Steam alpha channel (#183, D-087). Everything here is for the
person **running** a session; `testers.md` is the one-page thing you send
to the people playing, and it also travels inside every package.

Two ways to host, and they are for different sessions:

| | what it is | when |
|---|---|---|
| **In-game Host** (#182) | the server runs inside a player's own client | a session you are playing in, on a network your friends can reach |
| **Hosted headless server** (below) | the docker image on a machine with a public address | a session with people on the open internet, or one that outlives you |

---

## 1. A hosted headless server

### What to run it on

The measured shape (D-088, #111): **~half a core and ~52–72 MB** of
tracked memory at 20 players, and **871 B/client/s** of bandwidth
measured on a 4-client run — call it ~20 KB/s of upload at twenty. The
smallest VPS anybody sells is enough. What it needs is a **public UDP
port**, which is the part that rules out most home connections.

### Bring it up

```bash
git clone <repo> && cd my-edotmw
./bootstrap.ps1            # or: curl the just release for your platform
./tools/just up            # builds the pinned Godot image and starts the server
```

`just up` publishes **this checkout's** UDP port (D-095 derives it from
the branch), which is fine on a machine running one server and is not
what you want here — testers need a number you can tell them. Pin it:

```bash
EDOTMW_PORT=4433 ./tools/just up
```

Read the port back with `./tools/just instance` before you tell anybody.

### Which map, which seed

- **Map:** the shipped default, unless the session is about something
  else. `EDOTMW_MAP=res://maps/ladder.tres just up` for a small map where
  four players meet quickly, which is what you want for a one-hour
  session with three testers.
- **Seed:** leave it rolling. `MapSettings.seed` is rolled per match
  (D-100), so every match is a new world, and that is what you want from
  a playtest. **Pin it only when you are reproducing a report** —
  `--seed=N` on the server — and say in the invite that you have,
  because a pinned seed is a different kind of session.

### Read the log remotely

```bash
./tools/just status                                    # is it up
docker compose -p edotmw-<instance> logs -f server     # follow it
docker compose -p edotmw-<instance> logs server > session.log
```

What to look for, in the order it matters:

- `server: HANDSHAKE accepted=N refused=M` — **M > 0 means somebody was
  on the wrong build** and was turned away with a message. That is the
  system working, and it is also your cue to send them a newer zip.
- `desync` — should never appear. If it does, keep the whole log and the
  replay; that is the most valuable artifact this project can receive.
- `server: player N left (M connected)` — who dropped, and when.
- `server: final` — the totals. Per-squad cost quoted **with its squad
  count**, worst tick, dropped ticks.
- `server: MEMORY` — with its conditions attached (players, squads,
  cells), per #111.

The server writes a **replay** (`artifacts/replay-<port>.edmw`, D-016)
which is byte-identical to the wire format. Keep it for any session that
produced a report. `just replay-info <file>` reads it back.

### Shut down

```bash
./tools/just down
```

D-075 also ends the server on its own when the last human client leaves,
so an abandoned session does not hold the port.

---

## 2. Getting the build to testers

```bash
./tools/just bootstrap-export-templates   # ~1.3 GB, once
./tools/just export windows-client
./tools/just package windows-client       # -> build/packages/my-edotmw-windows-client-<version>.zip
```

The zip is named for the version inside it and carries `testers.md` as
its `README.txt`, because a tester with a six-week-old download has no
repo to look anything up in.

Then either hand over the zip, or push it to a **private** itch.io
channel:

```bash
butler login                              # once, personal
export EDOTMW_ITCH_PROJECT=yourname/my-edotmw
./tools/just publish-itch windows-client
```

> **`publish-itch` has never been run against a real target.** It needs
> an account, a project and an API key that do not exist in a repo, so
> what has been exercised is its refusal path. Expect to debug the first
> real push, and treat it as the rehearsal for steamcmd (#185) that it
> is.

**Never ship a build without #179's version handshake in it.** Testers
self-updating from zips are worse at staying current than Steam is, and
a stale client meeting a new server used to produce desync reports that
all ended in "you were on last week's build". Every build from this
commit onward refuses that join and says so.

---

## 3. Running the session

**Before:** send `testers.md` and the address:port. Say which build, and
say what you are hoping to learn from this one — "does it feel bad when
armies meet" is a better brief than "test it".

**During:** watch the server log rather than the game. The things worth
catching happen there — a refused handshake, a drop, a desync — and a
player will not report the first two because from their chair they look
like their own connection.

**After:** collect the log, the replay, and whatever the testers wrote
down. `docs/playtest/` is where the pictures and findings from previous
sessions live; a session that produced findings should leave a file
there.

### Report a problem — the channel testers actually have (#288)

**Tell them the button exists.** Menu → *Report a problem*, on the
pre-connect screen and in the in-game menu. It writes one file holding
their recent logs, their recent replays and their system details, says
where it is, and sends nothing. `testers.md` explains it; saying it out
loud at the start of a session is what makes it get used.

**Ask for the bundle AND the sentence.** The bundle is what makes a
report reproducible; the sentence is what makes it findable. "It broke"
with a perfect bundle attached still needs somebody to guess which of
four hundred log lines matters.

You have the same thing from a checkout:

```bash
./tools/just report-bundle 1     # what would go in, writes nothing
./tools/just report-bundle       # write it
```

Three things worth knowing when the bundles start arriving:

- **The manifest is the first thing to read.** Every bundle lists its own
  contents and which of them carry the tester's user name and the server
  address. If somebody asks you what they just sent you, the answer is
  in the file.
- **A bundle with no replay in it is a signal, not a fault.** It means
  that client never recorded one, which for a *host* is worth chasing
  and for a joining player is normal — the replay is the server's
  (D-016).
- **Nothing arrives automatically.** There is no telemetry and no
  endpoint; a report exists only if a person chose to send it. Budget
  for chasing people, and read the server log yourself (above) for the
  things they will never report.

### What to tell testers up front, every time

These are in `testers.md` too, and repeating them saves reports:

- **Disconnecting is losing** (D-033) — reconnection is designed and not
  built.
- **Matches decide in three or four minutes** (D-056) — no progression
  yet, so they are testing netcode, performance and feel.
- **The host quitting ends the match** (D-088, accepted with eyes open).

---

## What this runbook cannot do for you

**The criterion #183 is measured against is a human**: at least one
remote person, on a machine that has never seen the repo, installing a
build and finishing a match against a hosted server, with the state-hash
machinery reporting the result. Everything above is the apparatus for
that. Nobody has yet done it, and the first session is also the first
real test of D-042's transport claims on a network that is not a
loopback, a LAN or a docker bridge — so expect the RTT and loss numbers
to be worth recording properly, beside the originals and with their
conditions.
