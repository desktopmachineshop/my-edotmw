**There is a way to put a build in a tester's hands**
(`D-20260828-the-alpha-loop-is-a-zip-and-a-runbook`, #183, D-087,
2026-08-28). The pre-Steam alpha channel: a versioned zip, a runbook for
hosting a server testers can reach, and the one page a tester gets.

```
just export windows-client
just package windows-client     # -> build/packages/my-edotmw-windows-client-<version>.zip
just publish-itch windows-client   # needs butler + a key; see below
```

`docs/alpha/runbook.md` is for whoever runs a session;
`docs/alpha/testers.md` is what you send, and it also travels **inside**
every package as `README.txt` — a tester with a six-week-old download has
no repo to look anything up in.

Five things to know:

- **The zip is packed by GODOT, not `zip`.** `zip` is not on Git Bash's
  PATH on Windows and `Compress-Archive` is PowerShell-only; either as a
  dependency breaks the promise that a fresh clone needs nothing but
  `./bootstrap.ps1`. The engine is already pinned (D-001) and is the same
  binary that produced the build. Entries are written SORTED, for the
  reason `art/build.py` iterates sorted.
- **Byte-identity is NOT claimed.** A zip stores mtimes and two runs
  differ. That is why the recipe prints a sha256: the checksum you quote
  is the checksum of the file you send, not of a rebuild. D-081's
  determinism rule is about `generated/`; implying it here would be a
  claim to retract later.
- **The version is in the filename**, from the one place it is written
  down (D-20260827). A Downloads folder is where mixed builds are born —
  two `my-edotmw.zip` become `my-edotmw (1).zip` and the report ends in
  "you were on last week's build". #179's handshake catches that at the
  join; this stops it happening.
- **`publish-itch` has never been run against a real target**, and that
  is stated rather than hidden. It needs an account, a project and an API
  key that do not exist in a repo, so what is verified is its refusal
  path — the state every automated context is in. It exists as a recipe
  rather than prose because the invocation is the easy part to get wrong
  (the channel is the product identity on itch; `--userversion` is what
  lets a client say which build it has), and because it is the cheap
  rehearsal for steamcmd (#185).
- **The runbook pins `EDOTMW_PORT`.** D-095's per-worktree port is
  exactly wrong for a machine whose whole job is to be reachable at a
  number you can tell people.

**Verified by using the artifact, not by inspecting it.** Exported,
packaged (119 MB, three files), extracted with `Expand-Archive` into a
directory that has never seen the repo, and **run from there** — hosting
a match: `0 of 400 ticks over D-020's budget, worst 11.4 ms`, and
`0 desyncs in 40 checks`. That exercises #178's export, #180's menu,
#179's handshake and #182's hosting from a package rather than a
checkout, which is the only configuration a tester is ever in.

**It also reproduced #201** — an exported build cannot write `res://`, so
a shipped build records **no replays** (D-016). Being fixed in PR #237.
The runbook tells a session host to keep the replay, so that wants to
land before the first session that produces a report worth diagnosing.

**What none of this can do, and it is the criterion:** #183 is measured
by a **human** — a remote person, on a machine that has never seen the
repo, installing a build and finishing a match against a hosted server.
Everything here is the apparatus. The first session is also the first
real test of D-042's transport claims on a network that is not a
loopback, a LAN or a docker bridge, so its RTT and loss numbers want
recording beside the originals with their conditions.

**And a tester has a way to send back what happened
(D-20260828-a-report-is-made-not-sent, #288).** The runbook got a build
installed and then left somebody who hit a bug with no channel: find a
log directory by hand, know that replays exist, remember to say what GPU
you have. **Menu -> Report a problem** — on the pre-connect screen and in
the in-game menu — writes one file holding recent logs, recent replays
and a system report, and says where it is. `just report-bundle` is the
same thing for whoever is running the session (`LIST=1` previews without
writing).

**It CREATES and never SENDS, and that is the design rather than a
limitation.** `testers.md` promises no telemetry and no account; nothing
in `report_bundle.gd` can open a socket and a test asserts that by name.
An automatic upload would be a better feedback channel and a broken
promise, and at this stage — a game asking strangers to run an unsigned
binary from a zip — the promise is worth more.

Three things worth knowing:

- **The bundle carries a MANIFEST naming every file and what is in it**,
  including the two a player would not guess: a log holds the address of
  the server they joined and, on Windows, their user name from inside
  every path the engine prints. "You decide whether to attach it" is
  only a real decision if the contents are named.
- **The system report is hardware and build, never identity.** A test
  tries the four environment variables a user name or machine name would
  arrive from and fails if any of them appears in the text.
- **Three defects were found by RUNNING it**, and two of the tests
  written for it could not have caught the one that shipped — they
  supplied the input they then asserted on. `ReportBundle.sources()`
  takes its directories as arguments now so the CALL SITE is under test.
  That is the third instance of the same shape in one session's work;
  the decision entry generalises it.

