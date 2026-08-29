### D-20260828 · Accepted — the alpha loop is a zip, a runbook and one honestly-unrun recipe

**Decision (M8, issue #183, D-087):** the pre-Steam alpha channel is
**`just package`** (a versioned zip of an exported build, with the tester
document inside it), **`docs/alpha/runbook.md`** (how to host a server
testers can reach) and **`docs/alpha/testers.md`** (the one page a tester
gets). `just publish-itch` exists for whoever has an itch.io key.

D-094's headline criterion needs playtesters on installed builds, and
waiting for the whole Steam loop to get the first remote humans in is
backwards. This is what puts a build in somebody's hands now.

Four calls:

**1. The zip is packed by GODOT, not by `zip`.** The obvious tool is not
available: `zip` is not on Git Bash's PATH on Windows, `Compress-Archive`
is PowerShell-only, and either as a dependency breaks the standing
promise that a fresh clone needs nothing but `./bootstrap.ps1`. The
engine is already pinned (D-001) and is the same binary that produced the
build being packed, so `package_zip.gd` uses `ZIPPacker`. Entries are
written in **sorted** order, for the reason `art/build.py` iterates
sorted: an archive whose order depends on the filesystem has a checksum
that moves for no reason anybody can see.

**Byte-identity is NOT claimed** — a zip stores mtimes, and two runs an
hour apart produced different digests. That is why the recipe prints a
sha256: the checksum you quote is the checksum of the file you send, not
of a rebuild. Saying so is the point; D-081's determinism rule is about
`generated/`, and quietly implying it here would be the kind of claim
this project keeps having to retract.

**2. The version is in the FILENAME.** A tester's Downloads folder is
where mixed builds are born: two files called `my-edotmw.zip` become
`my-edotmw (1).zip`, and the resulting report ends in "you were on last
week's build". #179's handshake catches that at the join; this stops it
happening. The version comes from the one place it is written down
(D-20260827) rather than from whoever is typing.

**3. `testers.md` travels INSIDE the package**, as `README.txt`. A tester
with a six-week-old download has no repo to look anything up in, and the
instructions have to be in the same folder as the thing they are about.
Copied at package time from the one source, so it cannot go stale
independently.

**4. `publish-itch` ships having never been run against a real target,
and that is a deliberate exception worth naming.** This repo's rule is
that a recipe must never report success for something that did not run,
and the adjacent rule — that a recipe nobody can run should not be
written — is why #181 has no `bootstrap-steam`. The difference is that
butler is a real tool with a real API this invocation is correct for; the
only missing thing is an account. So what is *verified* is the half that
can be: it refuses, loudly and specifically, when butler or the key or
the project is missing, which is the state every automated context is in.
The push itself is the human remainder, marked as such in the recipe, in
the runbook and in the PR.

It is a recipe rather than a line of prose because the invocation is the
part that is easy to get wrong — the channel name is the product identity
on itch, and `--userversion` is what lets a tester's client say which
build it has. Both are derived rather than typed. It is also a rehearsal
for steamcmd (#185): same shape, same versioning question, cheaper to get
wrong.

**Verified end to end, 2026-08-28**, which for a distribution loop means
the artifact was actually used: `just export windows-client` →
`just package windows-client` (119 MB, three files, sha printed) →
extracted with `Expand-Archive` into a directory that has never seen the
repo → **run from there**, hosting a match:

```
server: listening on 0.0.0.0:24777 — map default, tick 10 Hz (lobby)
client: hosting on port 24777 — the server is in this process (D-088)
server: ticks over D-020's 100ms budget: 0 of 400, worst 11.4ms at tick 300
client: state sync — squads 0 desyncs in 40 checks, buildings 0 desyncs in 40 checks
```

That exercises the whole chain — #178's export, #182's hosting, #180's
menu, #179's handshake — from a package rather than a checkout, which is
the only configuration a tester will ever be in.

**It also reproduced #201** (`ReplayLog: could not open
res://artifacts/… error 7`): an exported build cannot write `res://`, so
**a shipped build records no replays**. Filed from #178 and being fixed
in PR #237; the runbook tells a session host to keep the replay, so this
wants to land before the first session that produces a report worth
diagnosing.

**Rejected alternatives:** *shipping a plain folder rather than a zip* —
Windows extracts a zip and does not extract a folder, and a tester with
loose files beside their Downloads is a tester who will run the wrong
one. *An installer* — code signing is not solved (the runbook and the
tester doc both say the SmartScreen warning is real and why), and an
unsigned installer is worse than an unsigned zip. *Building the itch
upload into `package`* — publishing is a decision a human takes, and a
recipe that packaged and pushed in one breath is one typo away from
publishing something.

**Consequences:** `build/packages/` is gitignored with the rest of
`build/`. The runbook's hosting half is written against `just up` with
`EDOTMW_PORT` pinned, because D-095's per-worktree port is exactly wrong
for a machine whose whole job is to be reachable at a number you can tell
people.

**What this cannot do, and it is the criterion:** #183 is measured by a
**human** — at least one remote person, on a machine that has never seen
the repo, installing a build and finishing a match against a hosted
server, with the state-hash machinery reporting the result. Everything
here is the apparatus for that session; nobody has yet held it. The first
one is also the first real test of D-042's transport claims on a network
that is not a loopback, a LAN or a docker bridge, so its RTT and loss
numbers want recording properly, beside the originals and with their
conditions.

**Revisit trigger:** the first real session (whatever it finds about the
apparatus, and D-042's numbers on a real network); the first `publish-itch`
push, which will find whatever is wrong with an invocation nobody has
run; or code signing becoming worth doing, which changes what a package
IS rather than how it is made.
