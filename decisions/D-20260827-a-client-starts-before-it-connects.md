### D-20260827 · Accepted — a client starts before it connects, and every way a session ends lands on a menu

**Decision (M8, issue #180):** the client has a state in which it is **not
connected**. A launch with no connection argument opens a **main menu** —
address box, **Join**, **Host** (disabled, see below), **Quit** — and a
failed join, a refused join or a lost server returns there with a message
a player can read.

#180 asked for this as a new decision rather than a silent pick, because
D-089/D-094 imply the screen (criterion 4 requires joining "via the lobby
browser" with nobody touching an IP) and no entry names it.

**The problem, precisely.** `client.gd` had no pre-connection state at
all: `_ready()` opened an ENet socket from a CLI `--address` (default
127.0.0.1), and the **lobby** was the first thing a player ever saw —
reachable only because a socket already existed. Every human match so far
was launched by `just run-client` with arguments. A tester who installs
the build #178 now produces has no command line to type into, and no way
in.

Six calls:

**1. The menu appears when a connection was NOT ASKED FOR, never when
there is no default.** `--address` has defaulted to `127.0.0.1` since
this file existed, so a rule reading the *resolved* value would
autoconnect every launch and the menu would be unreachable — a feature
entirely absent with every test green, which is this project's
most-repeated defect. `MainMenu.autoconnect` therefore asks whether
`--address`, `--port`, `--run-seconds` or `EDOTMW_SERVER_ADDRESS` was
supplied. `just run-client` and `just test-client` pass the first two, so
they keep working unattended, which is #180's own condition. Capture mode
counts on its own: a headless screenshot has nobody to press Join, and a
menu drawn in front of it would photograph itself.

**2. HOST is drawn and DISABLED, and that is a decision rather than an
unfinished edge.** D-088's host runs the authoritative server *in the
host's own process*, and `server.gd` currently calls
`get_tree().quit()` when the last client leaves (D-075) — so hosting
in-process is a lifecycle change, not a button. It is **#182**. A control
that silently does nothing is this project's oldest defect family
(D-061's unreachable rally orders); one that says what it is waiting for
is not, so the button is disabled and a line under it says to run a
server and join it.

**3. `_return_to_menu` is THE destination, and it is deliberately full.**
A new connection is a **new server**, so everything the last one said has
to go — `ClientState.disconnected()` clears the seat list, this client's
player number, the chat, and D-030's **ever-revealed building set**. That
last one is not hypothetical: `docs/status/sandbox.md` records
`_return_to_lobby` dropping the visible baseline and not
`known_buildings`, and a playtest reporting **106 building desyncs in
55,239 checks**. Same trap, one door further out. The session COUNTERS
survive on purpose, because `desync_summary()` is printed when the
PROCESS ends and a session that played on two servers should report what
the session did.

**4. A connection gets a deadline.** ENet never reports "there is nothing
at that address" — it stays silent — so without one a typo is a client
that sits forever showing nothing, which is exactly how **#162** was
reported. Twelve seconds, generous because a first connection also pays
for the server generating a 32,592-cell world if it was only just
started.

**5. The address is parsed by a pure function, and the port is not
`int()`-ed at it.** GDScript's `int()` STRIPS non-digits, so
`127.0.0.1:24395x` would otherwise be a plausible and entirely wrong port
with nothing saying so — D-20260817's whole lesson arriving through a
text box. `MainMenu.parse_endpoint` refuses it and says why. It also
splits the colon **only when what follows is a number**, because an IPv6
literal is mostly colons: splitting from the right unconditionally turns
`::1` into host `::` port `1`.

**6. #179's refusal screen is deleted and lands here instead.** That
entry said the menu was where a refusal belonged and could not put it
there. Now the address is still in the box, so acting on "update and join
again" is one click rather than a relaunch.

**`just menu-shot` is the instrument, and it earned its keep on its first
run.** Every other rendered check this project has is aimed at a
*connected* client — `test-client` needs a server, `lobby-shot`
photographs a screen only reachable once a socket exists — so nothing
could look at the menu. It renders through the docker software-GL image
like `lobby-shot`, starts **no server** (the menu is the one screen that
must render with nothing running) and opens no window on anybody's
desktop.

Its first picture showed a menu carrying **"Could not reach
server:4433"**. The `--menu` flag was written as a bare flag, and
`CmdArgs.parse` records only `--key=value` and silently drops the rest —
so the flag was ignored, the container's `EDOTMW_SERVER_ADDRESS` was
used, the connection failed, and the *failure path* put the menu on
screen anyway. **Every check passed and the picture was wrong**, which is
the oldest lesson here (M7's black soldiers, M7's inside-out boxes,
D-097's honeycomb ground). It is `--menu=1` now and the client refuses a
`--menu` that is not a number, like every other numeric flag. The second
picture found a smaller one: the address box only *looked* filled,
because a `LineEdit` draws its placeholder — so Join on a first launch
would have answered "enter an address" at a player looking straight at
one.

**Rejected alternatives:** *a third layout module* — the menu is four
controls and is laid out by `LobbyLayout`'s own scale and margins,
because it is the same kind of screen (a full-page document fitted to its
content, not an overlay magnified over a world). *Keeping the socket open
across a return to the menu* — a menu that is secretly still connected is
not a state, it is an overlay, and the `_host == null` early return in
`_process` is what makes it real. *Making Host spawn the exported server
as a child process* — that is not D-088's in-process host, it needs a
built binary a checkout does not have, and it would have to be undone by
#182.

**Consequences:** `client.gd` gains a genuine lifecycle, and
`tests/test_main_menu.gd` drives it by instantiating the real script and
never adding it to the tree — the technique D-075's 2026-08-16 amendment
established, which exists because that is precisely where this file
breaks quietly. The last endpoint is remembered in `user://settings.cfg`.
`_process` returns early with no socket, and the capture path is
explicitly kept alive through that return, because a headless run whose
server refused it would otherwise hang its recipe forever.

**Deliberately NOT here: #162.** That bug — a client that sits running
with no server after an in-match disconnect, saying nothing — is owned by
another worker, and this change does not touch the in-match
`EVENT_DISCONNECT` branch. What it provides is the **destination**:
`_return_to_menu(reason)` exists, is tested, and closing #162 is a call
to it (or a banner offering it, which is that worker's call to make). The
paths wired up here are the ones unambiguously in #180's scope — a join
that was refused, a join that was never answered, and a socket that could
not be opened.

**Revisit trigger:** #182 landing (Host stops being disabled and the
screen gains a real second verb); #187's Steam lobby browser and invites,
which grow into this same screen and must degrade to exactly what is here
when Steam is absent (D-093); or the first time somebody wants the menu
to remember more than one server, at which point the single
`last_endpoint` becomes a list and that is a change to what is
persisted rather than to any of the above.
