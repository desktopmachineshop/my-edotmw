### D-042 · 2026-08-01 · Accepted — transport stays reliable-ordered
**Decision:** Keep ENet reliable, ordered delivery for everything.
**Unreliable-with-resend is rejected**, and the M4 measurement it was
waiting on is taken.

**Measured** (20 players, 120 s, docker):

| | |
|---|---|
| peak RTT | 14.0 ms |
| peak packet loss | 0.978% |
| min ENet throttle | 0.69 of 1.00 |
| desyncs | 0 of 2,380 state-hash checks |
| bandwidth | 933 B/client/s, 0 budget overruns |

The loss figure is the interesting one: it is **not** zero even locally,
and ENet's congestion throttle backed off to 69%, so reliable delivery is
genuinely working rather than idling on a perfect link. It absorbed that
loss with zero desyncs. There is no measured problem to re-engineer.

**Rationale, and the part that actually decides it:** curve packets carry
**no sequence number**. `ClientState._handle_curve` installs whichever
curve arrived most recently, and curves are sent ONLY on change (D-003),
so there is no later message to correct a mistake. If two curves for one
squad arrive reversed, the client permanently installs the older one and
nothing detects it — the composition hash covers strength, not position.

So "unreliable with resend" is not a transport swap; it is a protocol
change requiring a version field on every curve, plus the ack/resend
machinery, to arrive at what ENet already does correctly. That is
reimplementing TCP's hard parts to save retransmissions on a link
carrying under 1 KB/s per client.

`test_curve_application_is_last_write_wins_so_order_is_load_bearing`
pins this dependency down so it is explicit rather than implicit, and
says in its own failure message that if it ever stops failing under
reordering, a sequence number has appeared and this decision can be
revisited.

**Rejected alternatives:** Unreliable curves with periodic full
resync (rejected — a periodic refresh is exactly the per-tick snapshot
D-003 exists to avoid; an idle squad must cost zero bandwidth). Splitting
curves onto their own ENet channel to avoid head-of-line blocking
(rejected *for now*, and noted as the cheap first move if loss ever
matters: it costs one constant, needs no protocol change, and ENet's
channels are already allocated — `CHANNELS := 2`, with channel 1 unused.
It was not done because doing it now would be an untested change
answering a problem no measurement shows).

**Consequences:** The wire protocol may continue to rely on ordering.
Anyone adding a message type may assume in-order delivery relative to
every other message, which is a real simplification and should be
understood as a deliberate commitment rather than an accident.

**Revisit trigger:** Real-network testing (not loopback, not docker)
showing loss high enough that ENet's throttle materially reduces
throughput, or a measured curve-delivery latency that hurts play. The
first response is channel separation, not a custom resend layer.

---
