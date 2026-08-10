"""The unit roster, as parameters (D-064).

Keyed by ARCHETYPE, never by civ. D-046 criterion 3 has a test asserting no
`.gd` file names a civ id, and the same discipline applies here even though
Python is outside that test's reach: a model keyed by civ would make civ three
an art task, exactly as a code branch would make it a programming task.

Civ-level visual difference is a later, declarative layer — a `CivDef` tint or
kit override that every civ has and one civ happens to set. It is deliberately
not built yet; see D-064's revisit trigger.

Each entry states only what makes that archetype different. Everything else
comes from `SoldierParams` defaults, so this file reads as a set of contrasts,
which is also how a player experiences the roster.
"""

from __future__ import annotations

from ..lib.soldier import SoldierParams

ROSTER: dict[str, SoldierParams] = {
    # The line. Cheap, plain, no crest — the baseline everything else reads
    # against.
    "militia": SoldierParams(
        helmet="cap",
        weapon="sword",
        shield=True,
        cloth=(0.46, 0.42, 0.36),
    ),

    # Long spear is the whole silhouette. At distance the shafts are what tells
    # a player this block counters cavalry.
    "spearmen": SoldierParams(
        helmet="cap",
        weapon="spear",
        shield=True,
        cloth=(0.40, 0.40, 0.44),
    ),

    # No shield, bow held across the body, lighter build.
    "archers": SoldierParams(
        helmet="none",
        weapon="bow",
        shield=False,
        bulk=0.9,
        cloth=(0.38, 0.42, 0.32),
    ),

    # Crest and bulk. Reads as heavier than anything else on foot, which is the
    # information a player needs before deciding to engage it.
    "heavy_infantry": SoldierParams(
        helmet="crested",
        weapon="sword",
        shield=True,
        bulk=1.18,
        scale=1.04,
        cloak=True,
        metal=(0.70, 0.72, 0.78),
    ),

    # Mounted. Height alone distinguishes it before any detail resolves.
    "cavalry": SoldierParams(
        helmet="horned",
        weapon="sword",
        shield=False,
        mount=True,
        cloak=True,
        cloth=(0.44, 0.34, 0.30),
    ),

    # Light, unarmoured, wide stance — a thrower rather than a line unit.
    "skirmishers": SoldierParams(
        helmet="none",
        weapon="axe",
        shield=False,
        bulk=0.88,
        stance=1.15,
        cloth=(0.48, 0.44, 0.30),
    ),

    # Civilians. No helmet, no shield, no weapon — the silhouette should say
    # "do not send these to fight" without a health bar.
    "gatherers": SoldierParams(
        helmet="none",
        weapon="none",
        shield=False,
        bulk=0.86,
        cloth=(0.52, 0.46, 0.36),
        tunic_mask=0.7,
    ),

    # The founding party (D-031): better than line infantry and the only unit
    # that can raise a town hall. Cloak and crest mark them as the thing a
    # player cannot afford to lose in the first two minutes.
    "founders": SoldierParams(
        helmet="crested",
        weapon="spear",
        shield=True,
        cloak=True,
        scale=1.02,
        cloth=(0.44, 0.36, 0.44),
    ),
}
