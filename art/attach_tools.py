"""Attach the axe and the pickaxe to a gatherer's back.

    tools/blender-venv/bin/python art/attach_tools.py
    just attach-tools

## What this is for

A gatherer crew works four kinds of node and looked identical at all four.
Giving the model the two tools a player expects — an axe for wood, a pickaxe
for ore — is what makes `chop`, `mine` and `forage` different clips rather
than three names for the same swing.

It is a MIGRATION like `import_glb_source.py` and `seed_source.py`, not part
of the build: it edits `art/source/gatherers.blend` in place, and
`just build-assets` bakes whatever the `.blend` says. It refuses to run twice
against the same file, because the second run would attach a second pair of
tools to a model that already has them.

## Why the tools become part of the SOLDIER MESH

They could not be anything else. A tool has to follow the hand through a
swing, and where the hand is at phase 0.4 of `chop` is a fact that exists
only in the VAT (D-082). Nothing on the CPU knows it — not the simulation,
not the renderer, not `Formation`. So a tool drawn from its own MultiMesh
could be placed at the soldier, and never in his fist.

Merged into the mesh, it costs nothing new: the same VAT column layout, the
same one draw call per squad, the same shader. The tool is simply more
vertices that the bake already knows how to move.

## The tool is weighted to a bone of its own, and that bone is the socket

Each tool gets one bone, parented to the chest, whose REST pose is the tool
stowed on the back. The tool's vertices are weighted 1.0 to it and nothing
else, so the bone IS the tool's transform:

- a clip that does not use the tool keys nothing, and the tool rides the
  back exactly as a scabbard would;
- a clip that does use it sets the bone's pose matrix from the HAND's, so
  the tool is in the fist by construction rather than by a hand-tuned offset
  that drifts the moment the swing is retimed.

The bone is built so that its head is the GRIP — the point the fist closes
on — and its Y axis runs up the handle toward the head of the tool. That is
the same convention Blender uses for every bone (local Y is head to tail),
which is what lets `author_clips.py` put a tool in a hand with one matrix
multiply instead of a table of offsets.

## Orientation is MEASURED, and every measurement is CHECKED

A supplied asset arrives at whatever angle its generator chose: the axe here
stands very nearly upright, the pickaxe leans about 30 degrees off vertical
in two axes at once. Hard-coding a correction per file is a magic angle that
is wrong the moment somebody supplies a different axe, so everything is
measured off the geometry — which took three attempts to get right, and none
of the wrong ones failed anything.

That is the lesson worth carrying, and `_handle_line` has the detail:
**every wrong answer here still produced a tool.** The right size, in a hand,
with a head on it. What it did not produce was a tool a player would
recognise, and the only instrument that could tell the difference was a
picture. So each step now asserts its own result —
`_assert_handle_is_the_long_axis`, `_assert_head_faces_x`,
`_assert_grip_on_the_handle` — in the units that step is about.

## One model, one texture, so the tools go into the gatherer's atlas

`D-20260824-a-textured-model-keeps-its-texture` gives a model exactly one
albedo image and the shader exactly one sampler. Three textures cannot
survive that, so the three are composited into one atlas and every UV is
remapped into its own rectangle. The composite is asserted against its
sources afterwards rather than trusted: a colour that crosses an asset
pipeline is not the colour that comes out (D-100), and this one crosses a
float buffer and a JPEG encoder on the way.

## The triangle budget here is a TEXTURE WIDTH, not a frame rate

The VAT is one column per flattened vertex (`art/lib/bake.py`), so a model's
triangle count is a texture WIDTH: 4,824 triangles is already 14,472 pixels
across. The tools arrive at ~4,795 triangles EACH, which would take the
gatherer past the 16,384-pixel limit every GPU this game targets shares —
and a texture that cannot be created does not render slowly, it does not
render. So each tool is decimated hard, and `art/build.py` refuses any model
whose VAT would exceed that width rather than leaving it to fail on
somebody's machine.
"""

from __future__ import annotations

import argparse
import math
import os
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from art.lib.blend_source import SOURCE_DIR, source_path     # noqa: E402


## The model these attach to. Keyed by ARCHETYPE like everything else under
## art/ — both civs' gatherers share one model (D-046 criterion 3), so a
## thrall and a colonus carry the same kit and neither file names a civ.
TARGET = "gatherers"

## Triangles each tool is decimated to.
##
## The ceiling is `MAX_VAT_WIDTH / 3 - <the model's own triangles>` — see the
## module docstring. At 4,824 for the gatherer that leaves 637 for both tools
## together, so 280 each keeps 112 pixels of headroom rather than landing on
## the limit exactly. They are held at arm's length on a soldier ~30 pixels
## tall; the silhouette that matters is "long handle, heavy head", and that
## survives the reduction (see docs/playtest for the picture).
TOOL_TRIANGLES = 280

## Each tool: the supplied `.glb`, how long it is in MESH-LOCAL units, and
## where along it the fist closes.
##
## Lengths are stated against a gatherer 0.795 local units tall (the object
## carries a x2 scale, so 1.59 in the game). A woodcutter's axe a little
## under half a man's height and a pickaxe slightly longer is what reads at
## this size; anything shorter disappears into the fist.
##
## `grip` is a FRACTION of the length measured from the butt. A quarter up
## the handle is where a hand actually sits for a swing, and it is what
## decides how much handle shows below the fist.
TOOLS = {
    "axe": {"source": "axe.glb", "bone": "Tool_Axe",
            "length": 0.34, "grip": 0.24},
    "pickaxe": {"source": "pickaxe.glb", "bone": "Tool_Pick",
                "length": 0.37, "grip": 0.24},
}

## Where each tool rides when it is not in use, in the armature's space.
##
## Crossed diagonally over the pack, grips low and heads up by the shoulders.
## The pack's own outer surface measures y = 0.185-0.190 across the whole
## trunk, so 0.235 clears it without floating. Which is worth stating: this
## model is a miner with a full backpack, and a tool laid flat against the
## SPINE would be buried inside it — the reason these sit proud of the back
## rather than on it.
##
## Heads up by the shoulders is also the only placement the game's camera can
## see. It looks down 59 degrees (`RenderCull.PITCH_RUN`), from where a
## soldier is mostly helmet and pack; a tool slung at the hip would be
## correct, invisible, and therefore pointless.
STOW = {
    "Tool_Axe":  {"grip": (0.140, 0.235, 0.345), "head": (-0.060, 0.235, 0.650)},
    "Tool_Pick": {"grip": (-0.140, 0.235, 0.345), "head": (0.060, 0.235, 0.680)},
}

## The hands, and the finger joints this adds to them.
##
## The supplied rig ends at `R_Hand` / `L_Hand`: one bone each, no fingers, so
## the mitts are rigid and stay flat open beside whatever the soldier is
## supposed to be holding. Two hinges per hand is what closes them.
##
## Two rather than one, because a single knuckle hinge folds the fingers as a
## rigid flap: at 90 degrees the tips stick out past the far side of a haft
## 0.03 across, which reads as a hand clamped shut NEXT to the tool rather
## than around it. Two joints let the fingers come round it.
##
## Three or more would be finger-by-finger animation on a soldier that is
## thirty pixels tall, which is not a thing this project is short of ways to
## spend triangles on.
HANDS = ("R_Hand", "L_Hand")
GRIP_BONES = {
    "R_Hand": ("R_Fingers", "R_FingerTips"),
    "L_Hand": ("L_Fingers", "L_FingerTips"),
}

## How far past the wrist the knuckles are, as a fraction of the hand bone's
## own length — so 1.0 is the bone's TAIL.
##
## The tail is where the rigger put it, and measuring the hand agrees: its
## width across the palm peaks at 0.137-0.140 in the band t = 0.08-0.11 on a
## bone 0.091 long, which is the knuckle line. Fingers run on to t = 0.181,
## about as long again as the palm.
KNUCKLE_AT = 1.0

## Where the fingers fold a second time, as a fraction of the way from the
## knuckles to the fingertips.
MID_JOINT_AT = 0.5

## How wide a band the weighting blends over, in fractions of finger length.
## A hard cut creases the knuckle to a point; this rounds it for nothing.
JOINT_BLEND = 0.35

## Bone the sockets hang from. The chest, so a tool follows the trunk's
## twist — which is most of what the overhead camera sees moving during a
## walk (see `author_clips.py`'s TRUNK_YAW note).
STOW_PARENT = "Spine02"

## How big a ball around the butt tip counts as "definitely handle", as a
## fraction of the tool's overall extent.
##
## It has to reach far enough up the haft to fit a line to, and stop well
## short of the head. A third of the whole tool does both on anything shaped
## like a hand tool, and `_assert_handle_is_the_long_axis` catches it if a
## stranger model defeats that.
HANDLE_BALL = 0.33

## How much of the far end is definitely head, for measuring which way the
## head faces. Used to fit geometry rather than to place anything, so it only
## has to be safely inside the real head.
HEAD_SHARE = 0.33

## How far the grip may sit from the nearest part of the tool, as a multiple
## of THAT TOOL'S OWN measured handle radius.
##
## A multiple rather than a fraction of the tool's length, because the number
## being tested is a handle thickness and every tool has its own. The first
## version guessed 0.06 x length and failed the axe at 0.022 against 0.020 —
## a hair over, on a grip that was correctly inside the handle. A guessed
## constant that red-flags a good model is worse than no check, because the
## next person raises it until it passes.
##
## The separation it has to make is wide, so it does not need to be tight: a
## grip on the handle measures 1.0-1.5 handle radii (the nearest vertex of a
## decimated tube is a flat between two rings, not a point on the surface),
## and the pickaxe's floating grip measured SEVEN.
MAX_GRIP_RADII = 3.0

## How far off broadside a tool's head may sit after the roll, in degrees. A
## decimated head is lumpy and its principal direction wobbles a degree or
## two; anything past this is a rotation going the wrong way.
MAX_HEAD_SKEW_DEGREES = 8.0

## How much of the handle, either side of grip height, counts as "beside the
## fist" when checking that there is haft to hold. A band rather than a plane,
## because a decimated handle has very few rings and the grip lands between
## two of them more often than on one.
GRIP_BAND = 0.15

## The atlas the three source textures are composited into, and where each
## one lands in it. Rectangles are (x, y, width, height) in pixels, y up,
## which is the convention both Blender's pixel buffer and UV space use — so
## the remap below is a scale and an offset with no flip anywhere.
##
## The gatherer keeps a full 2048x2048 and its own UVs are only halved in u.
## The tools are each given 2048x1024, which is far more than 280 triangles
## can spend and costs nothing to hand them, since the alternative was an
## empty quadrant.
ATLAS_SIZE = (4096, 2048)
ATLAS_RECTS = {
    TARGET:    (0, 0, 2048, 2048),
    "axe":     (2048, 1024, 2048, 1024),
    "pickaxe": (2048, 0, 2048, 1024),
}

## How closely the composited atlas must reproduce its sources, per channel,
## on a 0-1 scale. JPEG is lossy and the buffer is float, so this cannot be
## exact — but it can be tight enough that a colour-management mistake
## (which moves whole regions by tenths, per D-100) cannot hide under it.
ATLAS_TOLERANCE = 0.02


# --- Blender plumbing ----------------------------------------------------

def _clear_selection(bpy) -> None:
    bpy.ops.object.select_all(action="DESELECT")


def _activate(bpy, obj) -> None:
    _clear_selection(bpy)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def _apply(bpy, obj) -> None:
    _activate(bpy, obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def _vertices(numpy, obj):
    """This object's vertices as an (n, 3) array in its own space."""
    flat = numpy.empty(len(obj.data.vertices) * 3, dtype=numpy.float64)
    obj.data.vertices.foreach_get("co", flat)
    return flat.reshape(-1, 3)


# --- working out which way a supplied tool is pointing --------------------

def _principal_axis(numpy, points):
    """A coarse long axis, and which end carries the head.

    Returns `(axis, flip)` where `axis` is a unit vector and `flip` is True
    when the head is at the axis's NEGATIVE end.

    This is only good enough to get the head pointing UP, which is all
    `_handle_line` needs from it. It is NOT the handle: a principal axis is
    the best-fit line through every vertex, and a head that sticks out
    sideways drags it off the haft.

    Which end is the head is decided by thickness measured PERPENDICULAR to
    the axis, so it survives the axis being off by a fair angle. On the two
    supplied tools the margin is not close: mean perpendicular radius 0.044
    at the butt against 0.124 at the head.
    """
    centred = points - points.mean(axis=0)
    _u, _s, vt = numpy.linalg.svd(centred, full_matrices=False)
    axis = vt[0]

    along = centred @ axis
    perpendicular = centred - numpy.outer(along, axis)
    radius = numpy.linalg.norm(perpendicular, axis=1)

    third = (along.max() - along.min()) / 3.0
    low = radius[along < along.min() + third].mean()
    high = radius[along > along.max() - third].mean()
    return axis, bool(low > high)


def _butt_tip(numpy, points):
    """The free end of the handle, given points already laid out head-UP.

    A small cluster rather than the single lowest vertex, because one vertex
    of a decimated mesh can be a stray.
    """
    along = points[:, 1]
    cut = numpy.quantile(along, 0.02)
    return points[along <= cut].mean(axis=0)


def _handle_line(numpy, points, butt):
    """Fit a line to the tool's HANDLE. Returns `(direction, through, radius)`.

    `butt` is a point on the handle's free end — see `_butt_tip`.

    ## Why the handle is picked out by DISTANCE FROM THE BUTT

    Three things were tried here, and the first two were wrong in the same
    way: they selected the handle using an axis that was itself the thing in
    doubt.

    1. The tool's principal axis, used directly as the handle. A pickaxe's
       wide double head drags that line off the haft — the grip landed 0.103
       from the fist, on a handle 0.011 thick, and the tool hung in mid-air
       beside the hand for the whole stroke.
    2. A thin slab of geometry at grip height, measured ALONG that axis. Took
       it to 0.046 — still four handle radii out — because at 280 triangles
       the handle is too coarse a tube for a thin slab's centroid to mean
       much.
    3. The lower third, again measured along that axis. For the pickaxe that
       third was not handle at all, so the fit returned a direction roughly
       ACROSS the tool, and the model came out with its head along the
       handle's axis and its handle sticking out sideways.

    The fix is to stop projecting onto the doubtful axis. A ball around the
    butt tip contains handle and nothing else, because the head is at the
    other end — and a distance from a point does not depend on any axis being
    right.

    **Every one of those wrong answers still produced a tool**: right size, in
    a hand, with a head on it, passing every other check. That is why each
    step here asserts its own result.

    Measured on the two supplied tools, as the distance from the fist to the
    nearest tool vertex over a whole stroke: axe 0.033 -> 0.002, pickaxe
    0.103 -> 0.009.
    """
    extent = float(numpy.linalg.norm(points.max(axis=0) - points.min(axis=0)))
    reach = extent * HANDLE_BALL
    near = points[:0]
    for grow in (1.0, 1.4, 2.0):
        near = points[numpy.linalg.norm(points - butt, axis=1) <= reach * grow]
        if len(near) >= 8:
            break
    if len(near) < 8:
        raise SystemExit(
            f"only {len(near)} vertices within {reach * 2.0:.3f} of this "
            "tool's butt, which is not enough to find a handle in. Check that "
            "the model is a handled tool.")

    through = near.mean(axis=0)
    centred = near - through
    _u, _s, vt = numpy.linalg.svd(centred, full_matrices=False)
    direction = vt[0]
    # Point it AWAY from the butt, i.e. up the handle toward the head.
    if float(numpy.dot(direction, through - butt)) < 0.0:
        direction = -direction

    perpendicular = centred - numpy.outer(centred @ direction, direction)
    radius = float(numpy.linalg.norm(perpendicular, axis=1).mean())
    return direction, through, radius


def _head_angle(numpy, points) -> float:
    """The angle of the HEAD's broadest direction in the XZ plane, from +X.

    Measured on the head alone. Over the whole tool it would be dominated by
    the long thin handle, whose cross-section is a circle with no broad
    direction in it at all, so the answer would be noise.
    """
    along = points[:, 1]
    low, high = float(along.min()), float(along.max())
    head = points[along >= high - (high - low) * HEAD_SHARE]
    cross_section = numpy.stack([head[:, 0], head[:, 2]], axis=1)
    cross_section = cross_section - cross_section.mean(axis=0)
    _u, _s, vt = numpy.linalg.svd(cross_section, full_matrices=False)
    return float(numpy.arctan2(vt[0][1], vt[0][0]))


# --- what each step has to have achieved ---------------------------------

def _assert_handle_is_the_long_axis(numpy, obj, name: str) -> None:
    """Refuse a tool laid out across its own handle.

    After alignment the handle runs along Y, so Y must be the tool's LONGEST
    dimension — a hand tool is longer than it is wide. When the fit locked
    onto the head instead, the pickaxe came out 0.370 along Y and 0.580
    across X while every other check still passed: right size, grip on
    something, head broadside. Only a picture showed a pickaxe with its
    handle out of the side.
    """
    spans = _vertices(numpy, obj).ptp(axis=0)
    if spans[1] < max(spans[0], spans[2]):
        raise SystemExit(
            f"{name}: after alignment this tool measures {spans[0]:.3f} x "
            f"{spans[1]:.3f} x {spans[2]:.3f}, so its longest dimension is not "
            "the handle. The handle fit has locked onto the head — see "
            "`_handle_line`.")


def _assert_head_faces_x(numpy, obj, name: str) -> None:
    """Refuse a tool whose head did not end up broadside to X.

    The roll is the one step whose result is invisible downstream: a head at
    the wrong angle is still a tool, still the right size, still in the fist,
    and still passes every other check — it simply faces a direction nobody
    chose. That is how a sign error in the rotation survived to be found by
    looking at a picture of a dwarf with a pickaxe growing out of his back.

    Near zero, not exact: a decimated head is lumpy and its principal
    direction wobbles a degree or two. And +/-180 is the same orientation as
    0, because a head is a bar rather than an arrow — its principal direction
    has no sign.
    """
    residual = math.degrees(_head_angle(numpy, _vertices(numpy, obj)))
    folded = abs((residual + 90.0) % 180.0 - 90.0)
    if folded > MAX_HEAD_SKEW_DEGREES:
        raise SystemExit(
            f"{name}: after rolling, the head still lies {folded:.1f} degrees "
            f"off broadside, past the {MAX_HEAD_SKEW_DEGREES} allowed. The "
            "roll is applied about the handle, so a residual this large means "
            "the rotation is going the wrong way, not that the model is "
            "unusual.")
    print(f"  {name:9s} head broadside within {folded:.1f} degrees")


def _assert_grip_on_the_handle(numpy, obj, name: str, handle_radius: float) -> None:
    """Refuse a tool whose grip is not INSIDE the tool.

    The whole arrangement rests on one assumption — that the origin of the
    tool's own space is a point a hand could close on — and nothing
    downstream can notice when it is false. The socket bone is placed
    correctly, the weighting is correct, the clip is correct, and the tool
    hangs in the air beside the fist.

    So it is checked here, on the far side of the placement, in the units it
    matters in. That is this project's standing rule about asserting a value
    on the far side of a boundary (D-100), applied to geometry.
    """
    points = _vertices(numpy, obj)
    length = float(points[:, 1].ptp())
    # ACROSS the handle, over a band of it around grip height — not the
    # distance to the nearest vertex anywhere.
    #
    # The grip sits at the origin and the handle runs up Y, so the question is
    # whether there is haft beside the fist, and a straight nearest-vertex
    # distance answers a different one: at 280 triangles a handle is a tube of
    # very few rings, and a grip squarely inside it still measures 0.046 away
    # if the nearest ring happens to be half a band higher. That failed the
    # pickaxe on a placement that was correct.
    band = points[numpy.abs(points[:, 1]) <= length * GRIP_BAND]
    if len(band) < 3:
        raise SystemExit(
            f"{name}: no geometry within {length * GRIP_BAND:.3f} of grip "
            "height, so there is no handle where the hand goes.")
    nearest = float(numpy.linalg.norm(band[:, [0, 2]], axis=1).min())
    limit = handle_radius * MAX_GRIP_RADII
    if nearest > limit:
        raise SystemExit(
            f"{name}: at grip height the nearest haft is {nearest:.3f} to the "
            f"side, against a handle {handle_radius:.3f} thick — that is "
            f"{nearest / max(handle_radius, 1e-6):.1f} handle radii, and the "
            "hand would close on empty air. See `_handle_line`.")
    print(f"  {name:9s} haft {nearest:.3f} from the grip across the handle "
          f"({nearest / max(handle_radius, 1e-6):.1f} radii, limit "
          f"{MAX_GRIP_RADII:.1f})")


# --- one supplied tool, laid out in bone space ---------------------------

def _import_tool(bpy, numpy, name: str, spec: dict):
    """One supplied `.glb`, decimated and laid out in BONE space.

    Bone space here means: the grip at the origin, the handle running along
    +Y toward the head of the tool, and the head's broadest face spread along
    X. That is the frame the socket bone is built in, so placing the tool is
    `matrix_local @ vertex` with nothing else to remember.
    """
    from mathutils import Matrix, Vector

    glb = os.path.join(SOURCE_DIR, spec["source"])
    if not os.path.exists(glb):
        raise SystemExit(
            f"{name}: no supplied model at {os.path.relpath(glb, _ROOT)}. "
            "Drop the .glb there — it is hashed as a source (see "
            "art/build.py's SOURCE_SUFFIXES), so the game cannot draw a "
            "tool this repo does not carry.")

    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    imported = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    if len(imported) != 1:
        raise SystemExit(
            f"{name}: expected one mesh in {spec['source']}, got "
            f"{[o.name for o in imported]}. This script joins the tool into the "
            "soldier as a single weighted part; several parts would each need a "
            "socket, which is a decision rather than a loop.")
    obj = imported[0]
    obj.name = name
    obj.data.name = name
    _apply(bpy, obj)

    # Decimate FIRST, so every measurement below is taken on the geometry
    # that actually ships rather than on 17x of it.
    obj.data.calc_loop_triangles()
    source_tris = len(obj.data.loop_triangles)
    if source_tris > TOOL_TRIANGLES:
        modifier = obj.modifiers.new("decimate", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = TOOL_TRIANGLES / float(source_tris)
        bpy.ops.object.modifier_apply(modifier="decimate")
    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)

    # 1. Head UP. Coarse, and all the handle fit needs from it.
    axis, flip = _principal_axis(numpy, _vertices(numpy, obj))
    coarse = Vector(tuple(-axis if flip else axis)).normalized()
    obj.matrix_world = coarse.rotation_difference(
        Vector((0.0, 1.0, 0.0))).to_matrix().to_4x4() @ obj.matrix_world
    _apply(bpy, obj)

    # 2. HANDLE up +Y. This, not the coarse axis, is what decides where the
    #    fist closes.
    points = _vertices(numpy, obj)
    handle_dir, _through, _radius = _handle_line(
        numpy, points, _butt_tip(numpy, points))
    obj.matrix_world = Vector(tuple(handle_dir)).rotation_difference(
        Vector((0.0, 1.0, 0.0))).to_matrix().to_4x4() @ obj.matrix_world
    _apply(bpy, obj)
    _assert_handle_is_the_long_axis(numpy, obj, name)

    # 3. Handle's centre line onto the Y axis, so every rotation about Y from
    #    here spins the tool about its own haft rather than swinging it.
    points = _vertices(numpy, obj)
    _dir, through, handle_radius = _handle_line(
        numpy, points, _butt_tip(numpy, points))
    obj.matrix_world = Matrix.Translation(
        Vector((-through[0], 0.0, -through[2]))) @ obj.matrix_world
    _apply(bpy, obj)

    # 4. Roll the head broadside to X: an axe's blade across the back rather
    #    than edge-on into it.
    #
    #    POSITIVE, and that sign is not a detail. `Matrix.Rotation(a, 4, "Y")`
    #    takes a direction at angle phi in the XZ plane to phi - a, so
    #    cancelling phi needs a = +phi. Negating it takes phi to 2*phi —
    #    still "an orientation", so nothing failed and the head faced
    #    somewhere arbitrary until a picture showed it.
    roll = _head_angle(numpy, _vertices(numpy, obj))
    obj.matrix_world = Matrix.Rotation(roll, 4, "Y") @ obj.matrix_world
    _apply(bpy, obj)
    _assert_head_faces_x(numpy, obj, name)

    # 5. Scale to the stated length and drop the grip height onto the origin.
    #    The handle is the Y axis by now, so this is one number.
    points = _vertices(numpy, obj)
    span = float(points[:, 1].max() - points[:, 1].min())
    scale = spec["length"] / span
    grip = (float(points[:, 1].min()) + span * spec["grip"]) * scale
    obj.matrix_world = (
        Matrix.Translation(Vector((0.0, -grip, 0.0)))
        @ Matrix.Diagonal(Vector((scale, scale, scale, 1.0))))
    _apply(bpy, obj)
    _assert_grip_on_the_handle(numpy, obj, name, handle_radius * scale)

    spans = _vertices(numpy, obj).ptp(axis=0)
    print(f"  {name:9s} {source_tris:5d} -> {tris:3d} tris, handle "
          f"({handle_dir[0]:+.3f},{handle_dir[1]:+.3f},{handle_dir[2]:+.3f})"
          f" -> +Y, {spans[0]:.3f} x {spans[1]:.3f} x {spans[2]:.3f}, "
          f"grip {spec['grip']:.0%} up the handle")
    return obj, tris


# --- one model, one texture ----------------------------------------------

def _image_of(obj):
    """The Base Color image feeding this object's first material."""
    for slot in obj.material_slots:
        material = slot.material
        if material is None or not material.use_nodes:
            continue
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                return node.image
    return None


def _read_pixels(numpy, image):
    """An image as a (height, width, 4) float array, bottom row first."""
    buffer = numpy.empty(image.size[0] * image.size[1] * 4, dtype=numpy.float32)
    image.pixels.foreach_get(buffer)
    return buffer.reshape(image.size[1], image.size[0], 4)


def _resize(numpy, pixels, width: int, height: int):
    """Box-filter `pixels` down to (width, height).

    Integer ratios only, which every rectangle in ATLAS_RECTS is. A general
    resampler would be a bigger thing to get right than this needs — and a
    box filter over an exact integer ratio is the correct answer rather than
    an approximation of one.
    """
    source_height, source_width = pixels.shape[0], pixels.shape[1]
    if (source_width, source_height) == (width, height):
        return pixels
    if source_width % width or source_height % height:
        raise SystemExit(
            f"atlas: {source_width}x{source_height} does not divide evenly into "
            f"{width}x{height}. Choose an atlas rectangle that is an integer "
            "fraction of its source, or write a real resampler.")
    fx, fy = source_width // width, source_height // height
    return pixels.reshape(height, fy, width, fx, 4).mean(axis=(1, 3))


def _build_atlas(bpy, numpy, sources: dict):
    """Composite every source texture into one image, PACKED as JPEG.

    Packed, and packed as JPEG specifically, because `blend_source`'s
    `_save_basecolor` writes a packed image's bytes through verbatim and
    re-encodes anything else by copying `image.pixels` through a Python list
    — which for a 4096x2048 atlas is 33 million floats on every single
    build. The fast path is also the deterministic one (D-081 wants two
    builds byte-identical), so it is the only one worth being on.
    """
    width, height = ATLAS_SIZE
    canvas = numpy.zeros((height, width, 4), dtype=numpy.float32)
    canvas[:, :, 3] = 1.0

    for key, image in sources.items():
        x, y, rect_w, rect_h = ATLAS_RECTS[key]
        canvas[y:y + rect_h, x:x + rect_w] = _resize(
            numpy, _read_pixels(numpy, image), rect_w, rect_h)

    atlas = bpy.data.images.new(f"{TARGET}_atlas", width=width, height=height,
                                alpha=False)
    atlas.colorspace_settings.name = "sRGB"
    atlas.pixels.foreach_set(canvas.reshape(-1))
    atlas.file_format = "JPEG"
    atlas.update()

    staging_dir = tempfile.mkdtemp(prefix="edotmw-atlas-")
    staging = os.path.join(staging_dir, f"{TARGET}_atlas.jpg")
    atlas.filepath_raw = staging
    atlas.save()
    bpy.data.images.remove(atlas)

    # Load the SAVED file back and pack that, rather than packing the buffer
    # we just built: what ships is the encoded bytes, so what is checked has
    # to be the encoded bytes.
    packed = bpy.data.images.load(staging)
    packed.name = f"{TARGET}_atlas"
    packed.colorspace_settings.name = "sRGB"
    packed.pack()
    packed.filepath_raw = ""
    _assert_atlas(numpy, packed, sources)
    os.remove(staging)
    os.rmdir(staging_dir)
    return packed


def _assert_atlas(numpy, atlas, sources: dict) -> None:
    """Compare the round-tripped atlas against the images it was built from.

    D-100's rule, applied to a boundary this build had not crossed before: a
    colour that goes through a float buffer, a colour-space conversion and a
    JPEG encoder is not obviously the colour that comes out, and the failure
    mode is a whole model reading a shade wrong with nothing failing.

    Sampled rather than exhaustive — a colour-management error is a
    systematic shift over every pixel, not a speckle, and 4,096 probes per
    source will not miss one.
    """
    baked = _read_pixels(numpy, atlas)
    for key, image in sources.items():
        x, y, rect_w, rect_h = ATLAS_RECTS[key]
        want = _resize(numpy, _read_pixels(numpy, image), rect_w, rect_h)
        got = baked[y:y + rect_h, x:x + rect_w]
        step_y, step_x = max(1, rect_h // 64), max(1, rect_w // 64)
        probe_want = want[::step_y, ::step_x, :3]
        probe_got = got[::step_y, ::step_x, :3]
        drift = float(numpy.abs(probe_want - probe_got).mean())
        worst = float(numpy.abs(probe_want - probe_got).max())
        if drift > ATLAS_TOLERANCE:
            raise SystemExit(
                f"atlas: {key} reads back {drift:.4f} away from its source on "
                f"average (worst {worst:.4f}), past the {ATLAS_TOLERANCE} "
                "tolerance. That is a colour-management difference, not JPEG "
                "loss — check the atlas image's colorspace against the "
                "sources' (D-100).")
        print(f"  atlas {key:9s} rect {rect_w}x{rect_h} at ({x},{y})  "
              f"drift {drift:.4f} mean / {worst:.4f} worst")


def _remap_uvs(obj, key: str) -> None:
    """Move one object's UVs into its own rectangle of the atlas."""
    x, y, rect_w, rect_h = ATLAS_RECTS[key]
    width, height = ATLAS_SIZE
    scale_u, scale_v = rect_w / width, rect_h / height
    offset_u, offset_v = x / width, y / height

    layer = obj.data.uv_layers.active
    if layer is None:
        raise SystemExit(
            f"{obj.name}: no UV layer, so its share of the atlas cannot be "
            "addressed. A textured model without UVs samples one arbitrary "
            "texel over its whole surface.")
    for datum in layer.data:
        datum.uv = (offset_u + datum.uv[0] * scale_u,
                    offset_v + datum.uv[1] * scale_v)


# --- putting it on the soldier -------------------------------------------

def _add_socket(bpy, armature, bone_name: str, tool) -> None:
    """Add the socket bone, and move the tool onto its rest pose.

    The bone is built from STOW: head at the grip, tail at the head of the
    tool. `bone.matrix_local` then maps the tool's own bone space — grip at
    the origin, handle along +Y — straight into the armature's, so the tool
    is placed by one multiply and its rest pose IS the stowed pose.
    """
    from mathutils import Vector

    stow = STOW[bone_name]
    _activate(bpy, armature)
    bpy.ops.object.mode_set(mode="EDIT")
    try:
        edit = armature.data.edit_bones
        if bone_name in edit:
            raise SystemExit(
                f"{TARGET}: {bone_name} already exists. This script attaches "
                "tools to a model that has none; run it against a source "
                "restored from git rather than onto its own output.")
        bone = edit.new(bone_name)
        bone.head = Vector(stow["grip"])
        bone.tail = Vector(stow["head"])
        bone.parent = edit[STOW_PARENT]
        bone.use_connect = False
        # Lay the tool's HEAD flat against the pack rather than edge-on out of
        # it. The head's broad face is along the tool's local X, and a bone's
        # local X is decided by its roll — so pointing the bone's Z outward
        # (world +Y is away from this model's back) leaves X lying in the
        # plane of the back, which is where a slung axe's blade goes.
        bone.align_roll(Vector((0.0, 1.0, 0.0)))
    finally:
        bpy.ops.object.mode_set(mode="OBJECT")

    rest = armature.data.bones[bone_name].matrix_local
    tool.matrix_world = armature.matrix_world @ rest
    _apply(bpy, tool)


def _add_grip_bones(bpy, numpy, armature, body) -> None:
    """Give each hand two finger joints, so it can close around a haft.

    ## Why the hands could not grip before

    The supplied rig has one bone per hand and no fingers. The mitts are
    modelled open, four fingers straight and splayed, and nothing in the rig
    can bend them — so a tool placed correctly in the fist still had an open
    hand lying flat beside it.

    ## Why the haft runs along the hand and the fingers still wrap it

    `author_clips` puts the tool's handle along the hand's OWN axis, which is
    also the direction the straight fingers point — so at first glance the
    haft is parallel to the fingers and could never be gripped. That is what a
    real hand looks like too, with the fingers straight: gripping is precisely
    what folding them at the knuckles achieves, and after a right-angle curl
    the fingers cross the haft rather than lying along it.

    The haft is collinear with the hand bone's axis, so it passes through the
    middle of the closing fist and either curl direction encircles it. The
    sign below therefore decides which way the knuckles face, not whether the
    grip works.

    ## The joints are placed from the geometry

    The knuckle line is the hand bone's TAIL, which is where the rigger put it
    and where the hand measures widest (0.137-0.140 across, in the band
    t = 0.08-0.11 on a bone 0.091 long). The fingers run on to t = 0.181, and
    the second joint splits what is left in half.
    """
    from mathutils import Vector

    groups = {g.name: g.index for g in body.vertex_groups}
    plan = {}
    for hand in HANDS:
        if hand not in armature.data.bones or hand not in groups:
            raise SystemExit(
                f"{TARGET}: no '{hand}' bone or vertex group to hang fingers "
                f"off. The rig has {[b.name for b in armature.data.bones]}.")
        gi = groups[hand]
        owned = [v.index for v in body.data.vertices
                 if any(g.group == gi and g.weight > 0.4 for g in v.groups)]
        if len(owned) < 24:
            raise SystemExit(
                f"{TARGET}: only {len(owned)} vertices on {hand}, which is not "
                "a hand to split into fingers.")

        points = numpy.array([list(body.data.vertices[i].co) for i in owned])
        bone = armature.data.bones[hand]
        head = numpy.array(list(bone.head_local))
        span = numpy.array(list(bone.tail_local)) - head
        length = float(numpy.linalg.norm(span))
        axis = span / length

        # The palm plane: a hand is a flat slab, so its THINNEST principal
        # direction is the palm normal, and the knuckle hinge runs across it.
        centred = points - points.mean(axis=0)
        _u, _s, vt = numpy.linalg.svd(centred, full_matrices=False)
        palm_normal = vt[2] / numpy.linalg.norm(vt[2])

        along = (points - head) @ axis
        knuckle = length * KNUCKLE_AT
        reach = float(along.max())
        if reach <= knuckle:
            raise SystemExit(
                f"{TARGET}: {hand} has no geometry past its own bone tail, so "
                "there are no fingers here to bend.")
        mid = knuckle + (reach - knuckle) * MID_JOINT_AT
        plan[hand] = {
            "indices": owned, "along": along, "head": head, "axis": axis,
            "palm": palm_normal, "knuckle": knuckle, "mid": mid, "reach": reach,
        }

    _activate(bpy, armature)
    bpy.ops.object.mode_set(mode="EDIT")
    try:
        edit = armature.data.edit_bones
        for hand in HANDS:
            spec = plan[hand]
            fingers, tips = GRIP_BONES[hand]
            if fingers in edit:
                raise SystemExit(
                    f"{TARGET}: {fingers} already exists — run this against a "
                    "source restored from git, not onto its own output.")
            head = Vector(tuple(spec["head"]))
            axis = Vector(tuple(spec["axis"]))
            palm = Vector(tuple(spec["palm"]))

            first = edit.new(fingers)
            first.head = head + axis * spec["knuckle"]
            first.tail = head + axis * spec["mid"]
            first.parent = edit[hand]
            first.use_connect = False
            # Bone Z along the palm normal, so bone X ends up ACROSS the
            # knuckles — which is the axis a finger folds about, and is what
            # `author_clips` rotates these by.
            first.align_roll(palm)

            second = edit.new(tips)
            second.head = head + axis * spec["mid"]
            second.tail = head + axis * spec["reach"]
            second.parent = first
            second.use_connect = True
            second.align_roll(palm)
    finally:
        bpy.ops.object.mode_set(mode="OBJECT")

    for hand in HANDS:
        spec = plan[hand]
        fingers, tips = GRIP_BONES[hand]
        finger_group = body.vertex_groups.new(name=fingers)
        tip_group = body.vertex_groups.new(name=tips)
        hand_group = body.vertex_groups[hand]
        band = (spec["reach"] - spec["knuckle"]) * JOINT_BLEND

        moved = 0
        for slot, index in enumerate(spec["indices"]):
            t = float(spec["along"][slot])
            # Blended over a band at each joint rather than cut hard: a hard
            # cut creases the knuckle to a point, and the blend costs nothing.
            to_fingers = _ramp(t, spec["knuckle"], band)
            to_tips = _ramp(t, spec["mid"], band)
            finger_share = to_fingers * (1.0 - to_tips)
            if finger_share <= 0.001 and to_tips <= 0.001:
                continue
            moved += 1
            hand_group.add([index], max(0.0, 1.0 - to_fingers), "REPLACE")
            if finger_share > 0.001:
                finger_group.add([index], finger_share, "REPLACE")
            if to_tips > 0.001:
                tip_group.add([index], to_tips, "REPLACE")
        print(f"  {hand:9s} -> {fingers} + {tips}, {moved} of "
              f"{len(spec['indices'])} vertices bend")


def _ramp(t: float, at: float, band: float) -> float:
    """A 0..1 blend crossing 0.5 at `at`, over a band `band` wide."""
    if band <= 1e-6:
        return 1.0 if t >= at else 0.0
    return min(1.0, max(0.0, (t - at) / band + 0.5))


def _join_and_weight(bpy, body, tools: dict) -> dict:
    """Join every tool into the soldier mesh, weighted 1.0 to its socket.

    Whole-vertex weighting, deliberately: a tool is rigid, and a vertex
    shared with the chest would stretch the handle every time the trunk
    twisted. It is also what makes the socket bone the tool's transform
    outright, which is the property `author_clips.py` relies on to put the
    thing in a fist.
    """
    counts = {name: len(entry["object"].data.vertices)
              for name, entry in tools.items()}

    _clear_selection(bpy)
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    for entry in tools.values():
        entry["object"].select_set(True)
    first = len(body.data.vertices)
    bpy.ops.object.join()

    # Join appends in the order the objects were selected, which is not a
    # promise worth relying on — so the ranges are taken from the joined
    # mesh by matching vertex counts in the order `tools` states, and the
    # total is checked below.
    cursor = first
    ranges = {}
    for name, entry in tools.items():
        ranges[name] = (cursor, counts[name])
        group = body.vertex_groups.new(name=entry["bone"])
        indices = list(range(cursor, cursor + counts[name]))
        group.add(indices, 1.0, "REPLACE")
        # Anything the body already claimed must let go, or a hand's weights
        # would drag the handle when the arm swings.
        for other in body.vertex_groups:
            if other.name != entry["bone"]:
                other.remove(indices)
        cursor += counts[name]
        print(f"  {name:9s} -> bone {entry['bone']}, "
              f"{counts[name]} vertices weighted 1.0")

    if cursor != len(body.data.vertices):
        raise SystemExit(
            f"{TARGET}: joined mesh has {len(body.data.vertices)} vertices, "
            f"expected {cursor}. The tool vertex ranges are guesses now, so "
            "the weighting above cannot be trusted.")
    return ranges


def _clear_owner_mask(body, ranges: dict) -> None:
    """Take the owner-colour mask off the tools' vertices.

    COLOR_0's ALPHA is how much of a vertex takes the owning player's colour
    (D-052), and `bpy.ops.object.join` fills the incoming mesh's missing
    attribute with **opaque white** — alpha 1.0, which is "paint this entirely
    in the player's colour". The first in-engine shot came back with a bright
    red axe and a bright red pickaxe on a brown dwarf.

    Worth stating plainly because nothing could have caught it but the
    picture: the geometry was right, the weighting was right, the atlas was
    right, the clips were right, and every count in the build agreed. Same
    family as `art/lib/bake.py`'s note about a MultiMesh overriding COLOR, and
    D-100's about a colour that crosses an asset pipeline.

    A tool is wood and steel and belongs to nobody, so the mask goes to zero
    and the rgb to white: white is what a texture lookup multiplies cleanly,
    and it is the least alarming thing to see if the texture ever fails.
    """
    layer = body.data.color_attributes.get("COLOR_0")
    if layer is None:
        return
    indices = set()
    for start, count in ranges.values():
        indices.update(range(start, start + count))

    if layer.domain == "POINT":
        for index in indices:
            layer.data[index].color = (1.0, 1.0, 1.0, 0.0)
        return
    # CORNER domain: one entry per loop, so the tools' loops are the ones
    # whose vertex falls in the joined range.
    for polygon in body.data.polygons:
        for loop in polygon.loop_indices:
            if body.data.loops[loop].vertex_index in indices:
                layer.data[loop].color = (1.0, 1.0, 1.0, 0.0)


def _single_material(bpy, body, atlas) -> None:
    """Collapse the joined mesh onto one material carrying the atlas.

    A model gets one albedo image and the shader one sampler
    (D-20260824-a-textured-model-keeps-its-texture). Leaving the tools'
    original materials in place would leave `blend_source._save_basecolor`
    picking whichever it walked into last — the gatherer drawn in the
    pickaxe's texture is a perfectly plausible way for that to fail.
    """
    keep = body.material_slots[0].material
    for node in keep.node_tree.nodes:
        if node.type == "TEX_IMAGE":
            node.image = atlas
    for polygon in body.data.polygons:
        polygon.material_index = 0
    while len(body.material_slots) > 1:
        body.data.materials.pop(index=1)


def attach() -> None:
    import bpy
    import numpy

    path = source_path(TARGET)
    if not os.path.exists(path):
        raise SystemExit(f"{TARGET}: no authored source at {path}")

    bpy.ops.wm.open_mainfile(filepath=path, load_ui=False)
    body = bpy.data.objects.get(TARGET)
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if body is None or not armatures:
        raise SystemExit(
            f"{TARGET}: expected a mesh named '{TARGET}' and an armature in "
            f"{os.path.relpath(path, _ROOT)}; found "
            f"{[(o.name, o.type) for o in bpy.data.objects]}.")
    armature = armatures[0]
    if STOW_PARENT not in armature.data.bones:
        raise SystemExit(
            f"{TARGET}: this rig has no '{STOW_PARENT}' bone to hang a tool "
            f"from. It has: {[b.name for b in armature.data.bones]}")

    body.data.calc_loop_triangles()
    body_tris = len(body.data.loop_triangles)
    print(f"attaching tools to {os.path.relpath(path, _ROOT)} "
          f"({body_tris} tris):")

    tools = {}
    total_tris = body_tris
    for name in sorted(TOOLS):
        obj, tris = _import_tool(bpy, numpy, name, TOOLS[name])
        tools[name] = {"object": obj, "bone": TOOLS[name]["bone"], "tris": tris}
        total_tris += tris

    sources = {TARGET: _image_of(body)}
    for name, entry in tools.items():
        sources[name] = _image_of(entry["object"])
    missing = [k for k, v in sources.items() if v is None]
    if missing:
        raise SystemExit(
            f"{TARGET}: no Base Color image on {missing}. Every part of a "
            "textured model has to be in the atlas; a part with no texture "
            "would sample whatever its UVs happened to land on.")

    atlas = _build_atlas(bpy, numpy, sources)
    _remap_uvs(body, TARGET)
    for name, entry in tools.items():
        _remap_uvs(entry["object"], name)

    for name, entry in tools.items():
        _add_socket(bpy, armature, entry["bone"], entry["object"])

    ranges = _join_and_weight(bpy, body, tools)
    _clear_owner_mask(body, ranges)
    _add_grip_bones(bpy, numpy, armature, body)
    _single_material(bpy, body, atlas)

    bpy.ops.wm.save_mainfile()
    print(f"  {TARGET} is now {total_tris} tris "
          f"({total_tris * 3} VAT columns) with {len(TOOLS)} tool sockets")
    print(f"  wrote {os.path.relpath(path, _ROOT)} — "
          "re-run art/author_clips.py to animate the sockets")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    attach()


if __name__ == "__main__":
    main()
