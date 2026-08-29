**The client has a state in which it is NOT connected, and did not for
seven milestones** (`D-20260827-a-client-starts-before-it-connects`,
#180, 2026-08-27). `client.gd` opened its ENet socket in `_ready()` from
a CLI `--address`, and the **lobby** was the first thing a player ever
saw — reachable only because a socket already existed. Every human match
so far was launched by `just run-client` with arguments; a tester who
installs the build #178 produces had no way in at all.

There is a main menu now — address box, **Join**, **Host** (disabled),
**Quit** — and every way a session ends short of quitting lands back on
it with a message.

```
just menu-shot            # a picture of it, no server, no window
```

Seven things to know before touching the connection path:

- **The menu appears when a connection was NOT ASKED FOR**, never
  "when there is no default". `--address` has defaulted to `127.0.0.1`
  since this file existed, so a rule reading the RESOLVED value would
  autoconnect every launch and the menu would be unreachable — a feature
  entirely absent with every test green. `MainMenu.autoconnect` asks
  whether `--address`, `--port`, `--run-seconds` or
  `EDOTMW_SERVER_ADDRESS` was supplied, so `run-client` and `test-client`
  keep working unattended.
- **HOST is drawn and DISABLED on purpose.** D-088's host runs the
  authoritative server in the host's own PROCESS, and `server.gd` calls
  `get_tree().quit()` when the last client leaves (D-075) — hosting
  in-process is a lifecycle change, not a button, and it is **#182**. A
  control that silently does nothing is this project's oldest defect
  family (D-061); one that says what it is waiting for is not.
- **`_return_to_menu` clears D-030's ever-revealed building set**, along
  with the seat list, the player number and the chat. A new connection is
  a NEW SERVER whose ids start at 0, and `docs/status/sandbox.md` records
  exactly what carrying that set across a teardown costs: **106 building
  desyncs in 55,239 checks**. The session COUNTERS deliberately survive —
  `desync_summary()` prints when the process ends.
- **A connection gets a deadline (12 s).** ENet never reports "there is
  nothing at that address"; it stays silent. Without one, a typo is a
  client that sits forever showing nothing — which is exactly how #162
  was reported.
- **A typed port is refused, not `int()`-ed.** GDScript's `int()` strips
  non-digits, so `127.0.0.1:24395x` would be a plausible and entirely
  wrong port with nothing saying so (D-20260817's lesson through a text
  box). The colon is split only when what follows is a number, because an
  IPv6 literal is mostly colons and splitting from the right turns `::1`
  into host `::` port `1`.
- **#179's standalone refusal screen is gone**; a refusal lands on the
  menu with the address still in the box, which is what that decision
  said should happen and could not do.
- **`just menu-shot` is the instrument, and it found two defects on its
  first two runs.** Its first picture showed the menu carrying *"Could
  not reach server:4433"*: `--menu` was written as a bare flag,
  `CmdArgs.parse` records only `--key=value` and silently drops the rest,
  so the flag was ignored and the FAILURE path drew the menu. Every check
  passed and the picture was wrong. Its second showed the address box
  only LOOKING filled — a `LineEdit` draws its placeholder — so Join on a
  first launch would have answered "enter an address" at a player looking
  straight at one. **Both were found by looking, and neither was
  findable any other way.**

**#162 is deliberately untouched.** That bug — a client sitting with no
server after an in-match disconnect, saying nothing — is owned by another
worker. What this provides is the DESTINATION: `_return_to_menu(reason)`
exists and is tested, and closing #162 is a call to it, or a banner
offering it. The paths wired up here are a join that was refused, a join
that was never answered, and a socket that could not be opened.
