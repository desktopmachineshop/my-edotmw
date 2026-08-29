extends RefCounted
class_name PlayerIdentity

## WHO a seat belongs to, independently of any connection (#186, D-090).
##
## All-static and pure. The interesting property is not the format of the
## token but that it is **not a connection** — D-038's ownership cache is
## this project's own precedent, and it cost a whole 20-player run:
## ownership was read from a per-connection list written once at join, so
## every squad a player PRODUCED was refused as one they did not own.
## 2,700 refusals in the log, reported as "zero movement".
##
## D-090 makes the same mistake structurally impossible for seats: a seat
## is bound to an identity, and a connection merely presents one.
##
## ## The Steam boundary
##
## D-093 confines every mention of Steam to ONE script. This file does
## not name Steam and must not: it takes a token that has already been
## resolved, so the platform half can be dropped in at #181's boundary
## without this file, `MatchState` or the server learning that Steam
## exists. `local_token()` is what the Steam-less path uses today and is
## what every test and every bot uses — which is why the whole mechanism
## is exercisable now rather than after the platform work lands.
##
## An identity is OPAQUE. Nothing may parse it, compare parts of it, or
## infer a platform from it: a token that could be read would eventually
## be read, and then the seat table would depend on which platform a
## player joined from.

## The longest token accepted on the wire. Generous for a 64-bit platform
## id in decimal (20 digits) and for a UUID (36), and bounded because
## this arrives from an untrusted client (D-002) and is stored per seat.
const MAX_LENGTH := 64

## What an absent or unusable identity resolves to. A seat holding this
## is bound to nothing and can never be reclaimed by anybody — which is
## the correct outcome for a client that declined to identify, and is
## deliberately NOT an error: the load-test bots do not identify, and a
## match of anonymous peers must still work exactly as it did before
## identity existed.
const ANONYMOUS := ""


## Normalise a token as it arrives from a client.
##
## Untrusted input, so this is a gate rather than a formality: length is
## bounded and the character set is restricted, because the token is
## echoed into logs and compared against every seat.
static func normalise(raw: String) -> String:
	var trimmed := raw.strip_edges()
	if trimmed.is_empty() or trimmed.length() > MAX_LENGTH:
		return ANONYMOUS
	# Conservative on purpose. A platform id is digits; a local token is
	# hex. Anything else is either a mistake or somebody probing, and
	# neither should reach the seat table.
	for i in range(trimmed.length()):
		var c := trimmed[i]
		if not (c.is_valid_identifier() or c.is_valid_int() or c == "-" or c == "_"):
			return ANONYMOUS
	return trimmed


static func is_anonymous(token: String) -> bool:
	return normalise(token) == ANONYMOUS


## A stable local identity for the Steam-less path.
##
## Derived from a caller-supplied seed rather than generated here, so a
## client can persist one across runs and a TEST can pin one. Hashed so
## the token carries nothing about the machine that made it — an identity
## is opaque, and a token that embedded a username would leak one.
static func local_token(seed_text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(("edotmw-identity:" + seed_text).to_utf8_buffer())
	# 32 hex characters is 128 bits — far past collision territory for a
	# 24-seat lobby, and short enough to read in a log line.
	return context.finish().hex_encode().substr(0, 32)


## Whether two tokens are the same player.
##
## A function rather than `==` at each site, for the reason the D-038
## amendment gives about copies of a check: there is one definition of
## "same player", and an anonymous token is never equal to anything —
## including another anonymous one. Two clients that both declined to
## identify are two different people, and treating them as one would hand
## a stranger somebody's army.
static func same(a: String, b: String) -> bool:
	var left := normalise(a)
	var right := normalise(b)
	if left == ANONYMOUS or right == ANONYMOUS:
		return false
	return left == right
