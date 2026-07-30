#!/bin/sh
# Entrypoint for the `gui` image target: bring up a virtual X server, then
# run Godot against it. Used by `just test-client`.
#
# This replaces an `xvfb-run` ENTRYPOINT, which silently produced no
# output at all when Docker passed it a --server-args value containing
# spaces — the same command worked verbatim from a shell. Starting Xvfb
# explicitly is a few more lines and removes a layer of argument parsing
# that could not be debugged from outside the container.
set -e

: "${XVFB_DISPLAY:=:99}"
: "${XVFB_SCREEN:=1280x720x24}"

Xvfb "$XVFB_DISPLAY" -screen 0 "$XVFB_SCREEN" -nolisten tcp >/tmp/xvfb.log 2>&1 &
xvfb_pid=$!

# Kill the X server on every exit path, including failure and signals.
# Nothing this project starts may outlive it (D-014).
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT INT TERM

export DISPLAY="$XVFB_DISPLAY"

# Wait for the server to actually accept connections rather than sleeping
# a guessed interval — Godot fails immediately if it starts first.
i=0
while [ "$i" -lt 100 ]; do
    if xdpyinfo -display "$XVFB_DISPLAY" >/dev/null 2>&1; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done

if ! xdpyinfo -display "$XVFB_DISPLAY" >/dev/null 2>&1; then
    echo "gui_entrypoint: Xvfb failed to start on $XVFB_DISPLAY" >&2
    cat /tmp/xvfb.log >&2 || true
    exit 1
fi

godot "$@"
status=$?
exit "$status"
