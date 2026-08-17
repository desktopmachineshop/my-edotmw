#!/usr/bin/env bash
# THE one check for a value a recipe was handed
# (D-20260817-recipe-args-are-positional).
#
# `just` takes recipe arguments POSITIONALLY. An argument written
# `NAME=value` after a recipe name does NOT set NAME — it binds to that
# recipe's FIRST parameter, whatever that is. Every consumer downstream
# then reads it with `int()`, which STRIPS the non-digits rather than
# failing (measured: int("SANDBOX=1") == 1), so the run continues on a
# plausible small number nobody questions and nothing says a word:
#
#   just quick-test SANDBOX=1   ->  --seed=SANDBOX=1  (world seed 1, not
#                                   1337, and sandbox stays OFF)
#   just run-server LOBBY=1     ->  --ai=LOBBY=1      (one AI, no lobby)
#
# The first is an invocation the project's own docs prescribed (#89).
# The justfile's `lobby` recipe has carried a comment describing this
# exact trap since D-048 and worked around it by growing a SECOND recipe
# — a workaround for one instance of a class. This script is the general
# answer instead: a recipe validates what it was handed, and a value it
# cannot use fails LOUDLY, naming the trap.
#
# It is a plain script rather than a justfile helper for the same reason
# instance-id.sh is: a GUT test can execute it and watch it reject a bad
# value, where a `just` recipe is unreachable from the test estate.
#
#   bash recipe-arg.sh int  SEED    "$SEED"            # signed integer
#   bash recipe-arg.sh num  SECONDS "$SECONDS"         # integer or decimal
#   bash recipe-arg.sh enum SANDBOX "$SANDBOX" 0 1 auto
#
# Exit 0 and print nothing when the value is usable; exit 1 with an
# explanation when it is not; exit 2 on a misuse of this script itself.
set -euo pipefail

usage() {
    echo "usage: recipe-arg.sh int|num|enum NAME VALUE [ALLOWED...]" >&2
    exit 2
}

[ "$#" -ge 3 ] || usage
kind="$1"
name="$2"
value="$3"
shift 3

fail() {
    echo "FAIL: $name must be $1, got \"$value\"." >&2
    case "$value" in
        *=*)
            # The overwhelmingly likely cause, and the one that used to
            # be silent: someone wrote NAME=value after the recipe name.
            echo "" >&2
            echo "      just takes recipe arguments POSITIONALLY. Writing NAME=value" >&2
            echo "      after a recipe name does not set NAME — it binds to the first" >&2
            echo "      parameter, which is what you are looking at. Pass the values" >&2
            echo "      in order instead (see: just --list, or the recipe's comment)." >&2
            ;;
    esac
    exit 1
}

case "$kind" in
    int)
        digits="${value#-}"
        case "$digits" in
            ''|*[!0-9]*) fail "an integer" ;;
        esac
        ;;
    num)
        digits="${value#-}"
        case "$digits" in
            ''|.|*[!0-9.]*|*.*.*) fail "a number" ;;
        esac
        ;;
    enum)
        [ "$#" -ge 1 ] || usage
        ok=0
        for allowed in "$@"; do
            if [ "$value" = "$allowed" ]; then
                ok=1
            fi
        done
        if [ "$ok" != 1 ]; then
            fail "one of: $*"
        fi
        ;;
    *)
        usage
        ;;
esac
