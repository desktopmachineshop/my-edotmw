# eDotMW alpha — how to play, and what you are testing

Thanks for testing. This is an **early alpha**: it is a working
multiplayer real-time strategy game with no progression in it yet. What
we need from you is whether the **networking, the performance and the
feel** hold up, not whether the game is fun to finish.

Read the **Known limits** at the bottom before you start. Two of them
will look like bugs and are not.

---

## Install

1. Unzip anywhere. There is no installer and nothing is written outside
   the folder you unzip into, except your own settings (Windows keeps
   those in `%APPDATA%\Godot\app_userdata\my-edotmw\`).
2. Run `my-edotmw.exe`.

Windows will probably warn you that it does not recognise the publisher.
The build is not code-signed yet. If you are not comfortable with that,
say so — it is a real thing to be uncomfortable about, and we would
rather know than have you click through it.

## Join a match

The game opens on a menu with an address box.

1. Type the **address and port** you were given — it looks like
   `203.0.113.10:4433`.
2. Press **Join**.
3. You land in a lobby. Pick a civilisation, or leave it on Random. The
   host presses start.

**Host a match instead** if you are playing with someone on your own
network: press **Host a match** and tell them your address. Everyone else
joins it the same way. Note that if the host quits, the match ends for
everyone — that is a known limitation, not a crash.

## Play

- **WASD** pans, **mouse wheel** zooms, **Q/E** or **Ctrl+wheel** turns.
  The compass in the corner snaps back to north.
- **Left-click** selects, **drag** box-selects, **shift-click** adds.
  **Ctrl+1–9** stores a group, the number recalls it.
- **Right-click** orders the selection. **Right-click and drag** forms a
  battle line along the stroke — that is the one control worth trying
  deliberately, because it sets position, facing and width in one motion.
- **ESC** opens the menu.

## What we need to hear about

In rough order of usefulness:

1. **Anything that looked wrong on screen.** Soldiers standing inside
   trees or rocks, a squad in the wrong place, the ground looking odd,
   units sliding rather than walking. Screenshots are gold.
2. **Anything that felt bad.** Orders that did not seem to arrive,
   turning that looked wrong, a fight that resolved in a way that
   surprised you.
3. **Performance**, with your machine: what CPU and GPU, and what
   happened as armies got bigger.
4. **Anything you could not work out how to do.**

**Please say which build you are on.** It is on the menu screen and on
the first line of the log, and every zip's filename carries it. If your
build and the server's do not match, the game will now refuse the join
and tell you so rather than letting you play a subtly different game —
if that happens, you need a newer zip.

## Report a problem — one button, one file

**Menu → Report a problem.** It is on the first screen you see and in the
in-game menu (Esc). It writes **one file** holding your recent logs, your
recent replays and your system details, tells you where it is, and you
attach that to your report.

**Nothing is sent.** The button makes a file on your disk and stops. This
game has no telemetry and no account (see Privacy below), so whether any
of it reaches us is entirely your decision — which is why the bundle
carries a `MANIFEST.txt` listing every file in it and what each one
holds. Open it before you send it if you like; it is written to be read.

Two things in there worth knowing about, and they are in the manifest
too:

- the **logs** contain the address of the server you joined, and on
  Windows your user name, because it appears inside the file paths the
  game prints;
- the **replay** is the match itself — positions and orders — and nothing
  about you.

**Please still say what happened.** What you were doing and what you
expected is worth more than any file in the bundle.

### If you cannot reach the button

If the game will not start far enough to show a menu, send the log on its
own:

- Windows: `%APPDATA%\Godot\app_userdata\my-edotmw\logs\`
- Or run `my-edotmw.exe` from a terminal and copy what it prints.

The bundle, when you can make one, lands in
`%APPDATA%\Godot\app_userdata\my-edotmw\artifacts\` — but the game tells
you the full path on screen, so you should not need this.

---

## Known limits — please do not report these

- **Disconnecting means losing.** If your connection drops, your army is
  removed and you are eliminated. Rejoining does not give it back.
  Reconnection is designed and not built.
- **Matches decide fast** — often in three or four minutes. There is no
  age advancement, no tech and no upgrades yet, so once armies meet there
  is nothing else to do. That is the game being early, not the balance
  being broken.
- **The host quitting ends the match** for everybody in it. There is no
  host migration.
- **The host is trusted.** Do not play ranked matches against strangers,
  because there is no such thing yet and the host machine decides
  everything.
- **No sound.**
- **Windows only** for now. There is a Linux server build but no Linux
  client build.
- **Chat is not moderated or logged** anywhere; it exists so you can
  coordinate a test.

## Privacy

The game sends your orders to whoever is hosting and nothing else. There
is no telemetry, no account, and no analytics. Whoever hosts sees the
address you connect from, exactly as any server does.

**"Report a problem" does not change that.** It writes a file and stops;
nothing is transmitted, and the file lists its own contents so you can
see what you would be sending before you send it.

**The main menu checks for updates.** Once per launch, from the menu
only, it asks GitHub whether a newer release exists — an anonymous
request that sends nothing about you (GitHub sees the request itself, as
any website does). If there is one, a button appears; it opens the
release page in your browser and nothing downloads by itself.
