# D-20260828 · 2026-08-28 · Accepted — a report is made, not sent

**Decision:** an alpha tester who hits a problem presses one button and
gets one file (#288). Five clauses:

1. **The bundle is CREATED and never TRANSMITTED.** Nothing in
   `report_bundle.gd` can open a socket, and a test asserts that by
   name. The file is written to disk, the player is told the OS path,
   and they decide whether to attach it.
2. **The bundle says what is in it.** A generated `MANIFEST.txt` lists
   every file and what each one holds — including the two things a
   player would not guess: a log carries the address of the server they
   joined, and on Windows their user name, because it sits inside every
   path the engine prints.
3. **The system report is hardware and build, never identity.** OS, CPU,
   memory, adapter, engine and build version. No user name, no machine
   name, no network address; a test tries the four environment variables
   those would come from and fails if any appears.
4. **Both menus reach it through one handler.** The in-match menu and the
   pre-connect menu, `_on_report_a_problem_pressed` defined once. The
   pre-connect one matters as much: the reports hardest to act on come
   from somebody who never got INTO a match, and they have no other
   screen.
5. **`just report-bundle` is the same thing for whoever runs the
   session**, with `LIST=1` answering "what would you send" without
   writing anything.

## Rationale

`testers.md` promises "no telemetry, no account, and no analytics", and
the runbook gets a build installed and then leaves a tester with no
channel at all — they have to find a log directory by hand, know that
replays exist, and remember to say what GPU they have. Most of that does
not happen and the report that arrives is "it broke".

**Clause 1 is the whole design.** An automatic upload would be a better
feedback channel and a broken promise, and at this stage the promise is
worth more than the reports: this is a game asking strangers to run an
unsigned binary from a zip. Keeping it literally true — nothing here can
transmit — is what lets `testers.md` say so plainly rather than in the
hedged language every privacy policy uses.

Clause 2 follows from clause 1. "You decide whether to attach it" is
only a real decision if the non-obvious contents are named, so the
manifest is written for the person deciding, and it is the file a
maintainer should read first when one arrives.

## Rejected alternatives

- **Uploading to an endpoint**, or offering to. See above. It also needs
  a service, a retention policy and a privacy notice — three things this
  project does not have and should not acquire to serve an alpha.
- **Taking a screenshot into the bundle.** The frame at the moment a
  player presses the button is rarely the frame that shows the problem,
  a player who wants one has a key for it, and it is the single most
  invasive thing that could be added without anybody noticing.
- **Including the whole artifacts directory.** In a checkout that is
  every load-test log and preview render ever produced. The bundle is an
  attachment, not an archive.
- **A free-text box in the game to type what happened.** Tempting, and
  the wrong place: what a tester writes belongs in the report they are
  already writing, where it can be replied to. The manifest asks for it
  instead.
- **Reading the log path from a setting.** There is one, it is Godot's
  (`debug/file_logging/log_path`), and a second name for it here would
  be a second thing to keep in step.

## Consequences

- **`ReplayLog.SUFFIX` exists**, and `server.gd`'s two format strings use
  it. "Which files are replays" is that file's question — it already
  owns `MAGIC` — and a third reader arriving is what made the duplication
  cost something.
- **`ReportBundle.sources()` takes its two directories as arguments.**
  Not tidiness: see the defects below.
- **18 tests, every one observed to fail.** The privacy clauses are
  asserted rather than trusted, because they are the properties a
  reviewer cannot check by using the feature — a silent upload looks
  exactly like no upload, and a user name in a system report looks
  exactly like a system report.

## Three defects found by RUNNING it, and one shape they share

The first run of `just report-bundle` produced a bundle that looked
correct and was not:

1. **The replays were console logs.** The picker asked for `.log` in the
   artifacts directory; replays are `.edmw`, and a checkout's artifacts
   directory is full of `test-load` logs. The bundle packed two of those
   under `replays/` and reported success.
2. **`--list` wrote the bundle it was asked to preview.**
   `CmdArgs.parse` only recognises `--key=value` and drops a lone flag
   silently, so the flag was never seen. `--list=1` now.
3. **`String(facts[key])` is not a valid constructor call**, so the
   system report errored while the zip was still produced — a bundle
   with a broken `system.txt` and a cheerful success line.

**And the shape, which is the part worth carrying:** two of the tests
written for this feature could not have caught the bug that shipped,
because they **supplied the input they then asserted on**. The replay
test drove the file-picking helper with an extension it passed in, while
the defect was the *call site* passing a different one; the disclosure
test handed `manifest_text` an entry carrying the warning it checked for.
Both stayed green with the defect reintroduced. `sources()` takes its
directories as arguments now so the call site is under test, and the
disclosure test reads the real note.

That is the third time in this session's work that a test named the
value it expected instead of reading the value the code produces — the
others being a Steam depot id (#185) and a gate container id (#153). It
generalises: **a test that constructs its own input is testing the
constructor, and a test that names the value it expects to be missing
cannot see a wrong value under another name.**

## Revisit trigger

The first alpha session that produces reports. If testers press the
button and the bundles are not what a maintainer needs — or if they do
not press it at all — the answer is a change here, not a quiet upload.
Clause 1 is the one that must be re-decided in the open rather than
softened.
