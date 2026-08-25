# Authored model budget and modelling technique

Two owner's calls, both made 2026-08-19, lifted verbatim out of
`docs/plans/unit-model-briefs.md` on branch `ao/my-edotmw-74/root`
(commits `306a3c0` and `61efdc6`). That branch's civ roster was
superseded by D-20260823 (#189) and its PR (#192) was closed unmerged;
these two rules are not about which civs get built, so they are kept
here rather than lost with it.

**Status: not yet a decision.** Both calls supersede parts of D-081
(its ~300-tri authored budget, and its "committed Python generators are
the source of truth" build method). D-081 has not been amended, and
amending it is an owner's call, not this document's. Nothing in the
build reads this file.

One half of the pipeline note below was answered after these commits were
written: D-20260821-game-assets-are-files moved unit and building sources
to authored `.blend` files, so "assets move to authored DCC sources" has
already happened on `main`. The triangle budget and the surfacing
technique are the parts still outstanding.

Unit names below (Corpse Levy) are from the superseded roster; the
TIERS are what carries, not the examples.

## The rules, as written


- **Budget: ~10,000 triangles per authored unit** (owner's call,
  2026-08-19 — supersedes D-081's ~300-tri authored budget). Tiers:
  foot soldiers **10k**; mounted units and centaurs **12k**; giants
  **14–15k**; engines with crew **16–18k**; the horde exception
  (Corpse Levy) **8k**, because there are 48 per squad.
  **Shipping caveat, stated so nobody rediscovers it in a profile:**
  the game draws up to 40,000 soldiers and was measured at ~54 ms/frame
  with 27,300 soldiers at ~300 tris each (D-085/D-086). 10k-tri models
  drawn raw at that scale will not hold — these are AUTHORING budgets;
  in-game meshes ship through decimated LOD tiers generated in the
  build (near/mid/far), and `bench-render` must be re-measured before
  any of this is called shippable.
- **Proper surface modelling, not primitive assembly** (owner's call,
  2026-08-19). Each logical part — body, cloak, weapon, shield, mount —
  is ONE continuous, welded, manifold surface: quad-dominant topology
  under subdivision, sculpted organic forms, detail carved and embossed
  IN the surface rather than floated over it. No intersecting-primitive
  kit-bash, no unwelded shell stacks, no boolean seams left visible.
  Edge loops follow muscle and cloth flow and sit at every joint so the
  vertex animation deforms cleanly. Normals face outward and every
  closed part has positive signed volume, checked at build — the M7
  inside-out-`box()` lesson survives the technique change.
  **Pipeline note:** D-081's committed generators compose primitives
  and cannot produce this as they stand; the generator layer must grow
  real sculpt/subdiv operations or assets move to authored DCC sources.
  Flagged in the proposed pivot decision entry — an owner call on the
  pipeline, not resolved in a brief.
- **Silhouette first, still.** 10k and real surfacing buy secondary
  forms and genuine gear detail, not a different philosophy: every
  brief lists silhouette priorities in order, and if budget runs out,
  cut from the bottom of that list, never the top. The far-LOD
  decimation strips detail anyway — a unit must survive it and still
  read at RTS zoom.
- **Scale baseline:** one human soldier = **1.0 H** (≈1.8 m). All
  heights below are in H. Big models change `formation_spacing` in
  data, not the mesh's origin: every model stands on y=0, origin at
  feet-centre.
- **Player colour:** ownership tint is applied per instance. Each brief
  names its **tint zones** (cloth, banners, shield faces — the parts
  that take player colour) and its **fixed zones** (skin, bone, wood,
  iron — authored material colours; remember the sRGB pre-compensation
  rule in `art/lib/bake.py`, D-100). Tint zones must be big enough to
  read at zoom: at least ~15% of the visible silhouette.
- **Animation:** vertex-animation texture, phase derived (D-082). Each
  unit needs **idle / walk / attack** loops; briefs give the attack
  beat only, since idle and walk follow the body type. No ragdolls, no
  transparency, no particles — anything "atmospheric" is geometry.
- **Engines:** one instance = one complete engine WITH its crew
  sculpted on. There is no crew-pushes-object mechanic; a "battery" is
  squad_size instances of the whole model.
