"""Attach a fighting unit's KIT — weapon, shield, banner — to its body.

    tools/blender-venv/bin/python art/attach_kit.py --name militia
    just attach-kit militia

`art/attach_tools.py`'s sibling for the rest of the dwarf roster
(D-20260826-the-dwarf-roster-wears-supplied-models). A MIGRATION like it:
edits `art/source/<name>.blend` in place, is re-runnable only against a
source restored from git, and `just build-assets` bakes whatever the
`.blend` says.

## Why this is SIMPLER than the gatherer's tools

A gatherer's axe moves between his back and his fist, so it needed its own
bone whose rest pose is the stowed position, keyed from the hand's matrix
per clip. A soldier's kit never stows: the axe lives in his fist, the
shield on his forearm, the banner on his back, through every clip he has.
So every item here is weighted 1.0 to an EXISTING bone (`R_Hand`,
`L_Forearm`, `Spine02`) and placed once, at the rest pose — it follows
whatever `author_clips.py` does to that bone with no new machinery and no
clip edits. No sockets, no second pass, no depsgraph trap.

## What is reused rather than rewritten

The handle-fitting geometry (`_butt_tip`'s ball, `_handle_line`,
`_head_angle`) and its assertions come straight from `attach_tools` —
including the lesson they encode: a principal axis is dragged off the haft
by a wide head, so the handle is found from the butt tip, and every step
asserts its own result. The atlas machinery is re-parameterised here
because `attach_tools` bakes its rectangles as module constants.

## Modes

- `hand`: a hafted weapon, normalised exactly like a tool (grip at the
  origin, haft +Y toward the head, head broadside X), then laid along the
  hand bone's own axis — which is the direction the closed fingers point,
  so the haft crosses the palm. `grip` says where along the weapon the
  fist closes; `at` where along the hand bone the grip sits.
- `crossbow`: a stocked weapon. The bow's spread defeats the butt-ball
  handle fit (the pickaxe lesson at a larger scale), so it is normalised
  by extents instead: thinnest span vertical, stock along the hand.
- `shield`: a slab. Its thinnest principal direction is its face normal;
  the face turns to the body's measured FORWARD, the long axis lies along
  the forearm, and the plate floats a stated clearance off the arm.
- `back`: a standard. Pole vertical behind the spine, proud of the
  trunk's own measured depth — the same reason the gatherer's tools sit
  proud of his pack.
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from art.lib.blend_source import SOURCE_DIR, source_path     # noqa: E402
from art.attach_tools import (                                # noqa: E402
    _activate, _apply, _assert_handle_is_the_long_axis, _assert_head_faces_x,
    _butt_tip, _clear_selection, _handle_line, _head_angle, _image_of,
    _principal_axis, _read_pixels, _resize, _vertices)
from art.author_clips import _forward_sign, _map_roles        # noqa: E402


## Triangles each kit item is decimated to. Same ceiling arithmetic as
## TOOL_TRIANGLES: the VAT allows 5,461 triangles for the WHOLE model
## (art/build.py's MAX_VAT_WIDTH / 3), the bodies are imported at ~4,300,
## and two items at 300 leave ~500 of headroom.
KIT_TRIANGLES = 300

## Every model's kit. Lengths and diameters are ENGINE units — the bodies
## are imported at a stated height (import_glb_source), so kit is sized
## against the soldier it hangs on, not against whatever scale the item's
## generator chose.
##
## `at` is where along the hand bone the grip sits (fraction of the bone's
## own length past the wrist) and `palm` how far off the bone's axis
## toward the palm, as a fraction of the same length — the gatherer's
## measured grip sat at 0.83 along and 0.15 off, and those are the
## defaults here; they are per-item because a two-minute render is the
## instrument that tunes them (LOOK AT THE PICTURE).
KITS = {
    "militia": {
        "hand_axe": {"source": "hand_axe.glb", "mode": "hand",
                     "length": 0.42, "grip": 0.22, "roll": 90.0},
        "round_shield": {"source": "round_shield.glb", "mode": "shield",
                         "arm": "L_Forearm", "size": 0.58,
                         "clearance": 0.10},
    },
    "archers": {
        "crossbow": {"source": "crossbow.glb", "mode": "crossbow",
                     "length": 0.44, "grip": 0.30},
    },
    "general": {
        "runed_axe": {"source": "runed_axe.glb", "mode": "hand",
                      "length": 0.52, "grip": 0.20, "roll": 90.0},
        "banner": {"source": "banner.glb", "mode": "back",
                   "length": 1.25, "grip": 0.06, "base": 0.42},
    },
    "spearmen": {
        "spear": {"source": "spear.glb", "mode": "polearm",
                  "length": 1.15, "grip": 0.45, "roll": 90.0},
        "kite_shield": {"source": "kite_shield.glb", "mode": "shield",
                        "arm": "L_Forearm", "size": 0.62,
                        "clearance": 0.10},
    },
}

## Where a held item's grip sits in the hand, as fractions of the hand
## bone's own length (see KITS' doc). Measured on the gatherer and carried
## as the default for the family — every one of these rigs is the same
## 41-bone Tripo skeleton.
GRIP_ALONG = 0.83
GRIP_PALM = -0.15

## The bone a held weapon lives in. The lead hand, same as the tools.
WEAPON_BONE = "R_Hand"
## The bone a standard rides on — the chest, so it follows the trunk's
## twist, which is most of what the overhead camera sees (author_clips'
## TRUNK_YAW note).
BACK_BONE = "Spine02"

## The atlas each kitted model's textures are composited into. Same layout
## as the gatherer's: the body keeps a full 2048 square, each item gets a
## 2048x1024 strip it cannot spend a tenth of.
ATLAS_SIZE = (4096, 2048)
BODY_RECT = (0, 0, 2048, 2048)
ITEM_RECTS = [(2048, 1024, 2048, 1024), (2048, 0, 2048, 1024)]
ATLAS_TOLERANCE = 0.02


def _decimate(bpy, obj, budget: int) -> int:
    obj.data.calc_loop_triangles()
    source = len(obj.data.loop_triangles)
    if source > budget:
        _activate(bpy, obj)
        modifier = obj.modifiers.new("decimate", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = budget / float(source)
        bpy.ops.object.modifier_apply(modifier="decimate")
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _import_item(bpy, name: str, spec: dict):
    glb = os.path.join(SOURCE_DIR, spec["source"])
    if not os.path.exists(glb):
        raise SystemExit(
            f"{name}: no supplied model at {os.path.relpath(glb, _ROOT)}. "
            "Drop the .glb there — it is hashed as a source (art/build.py's "
            "SOURCE_SUFFIXES), so the game cannot draw kit this repo does "
            "not carry.")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    imported = [o for o in bpy.data.objects
                if o not in before and o.type == "MESH"]
    # Tripo files often carry a helper Icosphere the file never declared —
    # the converter's own lesson: take the largest, say what is dropped.
    imported.sort(key=lambda o: len(o.data.vertices), reverse=True)
    for extra in imported[1:]:
        print(f"  {name}: ignoring '{extra.name}' "
              f"({len(extra.data.vertices)} vertices)")
        bpy.data.objects.remove(extra, do_unlink=True)
    for other in bpy.data.objects:
        if other in before or other.type == "MESH" or other == imported[0]:
            continue
        if other.type in ("EMPTY", "ARMATURE"):
            bpy.data.objects.remove(other, do_unlink=True)
    obj = imported[0]
    obj.name = name
    obj.data.name = name
    obj.parent = None
    _apply(bpy, obj)
    return obj


def _normalise_hafted(bpy, numpy, obj, name: str, spec: dict) -> None:
    """Grip at the origin, haft +Y toward the head, head broadside X.

    The exact sequence `attach_tools._import_tool` runs, sharing its
    geometry helpers and its assertions — see that file for why each step
    exists and what each one shipped wrong the first time.
    """
    from mathutils import Matrix, Vector

    axis, flip = _principal_axis(numpy, _vertices(numpy, obj))
    coarse = Vector(tuple(-axis if flip else axis)).normalized()
    obj.matrix_world = coarse.rotation_difference(
        Vector((0.0, 1.0, 0.0))).to_matrix().to_4x4() @ obj.matrix_world
    _apply(bpy, obj)

    points = _vertices(numpy, obj)
    handle_dir, _through, _radius = _handle_line(
        numpy, points, _butt_tip(numpy, points))
    obj.matrix_world = Vector(tuple(handle_dir)).rotation_difference(
        Vector((0.0, 1.0, 0.0))).to_matrix().to_4x4() @ obj.matrix_world
    _apply(bpy, obj)
    _assert_handle_is_the_long_axis(numpy, obj, name)

    points = _vertices(numpy, obj)
    _dir, through, _handle_radius = _handle_line(
        numpy, points, _butt_tip(numpy, points))
    obj.matrix_world = Matrix.Translation(
        Vector((-through[0], 0.0, -through[2]))) @ obj.matrix_world
    _apply(bpy, obj)

    roll = _head_angle(numpy, _vertices(numpy, obj))
    obj.matrix_world = Matrix.Rotation(roll, 4, "Y") @ obj.matrix_world
    _apply(bpy, obj)
    _assert_head_faces_x(numpy, obj, name)

    _scale_and_grip(bpy, numpy, obj, spec)


def _scale_and_grip(bpy, numpy, obj, spec: dict) -> None:
    """Scale to the stated length and drop the grip height onto the origin."""
    from mathutils import Matrix, Vector

    points = _vertices(numpy, obj)
    span = float(points[:, 1].max() - points[:, 1].min())
    scale = spec["length"] / span
    grip = (float(points[:, 1].min()) + span * spec["grip"]) * scale
    obj.matrix_world = (
        Matrix.Translation(Vector((0.0, -grip, 0.0)))
        @ Matrix.Diagonal(Vector((scale, scale, scale, 1.0))))
    _apply(bpy, obj)


def _normalise_pole(bpy, numpy, obj, spec: dict) -> None:
    """Pole +Y, flag broadside X — a STANDARD, not a weapon.

    The hafted fit refuses a banner, correctly: its cloth is nearly as
    large as its pole (0.735 across against 0.776 long after alignment),
    so the butt-ball locks onto the flag and the "handle is the long
    axis" assertion fires. But a banner has no head to swing and no fist
    to close around a measured grip — the coarse principal axis IS its
    pole, and that is all this needs.
    """
    from mathutils import Matrix, Vector

    axis, flip = _principal_axis(numpy, _vertices(numpy, obj))
    coarse = Vector(tuple(-axis if flip else axis)).normalized()
    obj.matrix_world = coarse.rotation_difference(
        Vector((0.0, 1.0, 0.0))).to_matrix().to_4x4() @ obj.matrix_world
    _apply(bpy, obj)

    # The FLAG goes up, decided by measuring which end carries the cloth
    # rather than by `_principal_axis`'s head guess — which put this
    # banner's flag at the bottom and hung the standard below the
    # general's feet. The cloth end is the end with the wider off-axis
    # footprint; a bare pole butt has almost none.
    points = _vertices(numpy, obj)
    lo = float(points[:, 1].min())
    span = float(points[:, 1].max()) - lo
    bottom = points[points[:, 1] <= lo + span / 3.0]
    top = points[points[:, 1] >= lo + span * 2.0 / 3.0]

    def _footprint(part):
        return float(part[:, 0].ptp()) + float(part[:, 2].ptp())

    if _footprint(bottom) > _footprint(top):
        obj.matrix_world = (
            Matrix.Rotation(3.141592653589793, 4, "X") @ obj.matrix_world)
        _apply(bpy, obj)

    # Flag broadside X, same roll the weapons use — no skew assertion,
    # because a flag's spread is exactly the "head" shape the assertion
    # exists to distrust.
    roll = _head_angle(numpy, _vertices(numpy, obj))
    obj.matrix_world = Matrix.Rotation(roll, 4, "Y") @ obj.matrix_world
    _apply(bpy, obj)

    # Centre the POLE (not the cloth) on the Y axis, from the butt third's
    # own footprint: a flag hangs to one side, and centring on the whole
    # mesh would push the pole off-axis by half the cloth.
    points = _vertices(numpy, obj)
    lo = float(points[:, 1].min())
    span = float(points[:, 1].max()) - lo
    butt = points[points[:, 1] <= lo + span * 0.2]
    obj.matrix_world = Matrix.Translation(Vector((
        -float(numpy.median(butt[:, 0])), 0.0,
        -float(numpy.median(butt[:, 2]))))) @ obj.matrix_world
    _apply(bpy, obj)

    _scale_and_grip(bpy, numpy, obj, spec)


def _normalise_crossbow(bpy, numpy, obj, spec: dict) -> None:
    """Stock along +Y, bow spread along X, flat side down.

    A crossbow's widest span is its BOW, not its stock, so the butt-ball
    handle fit that serves every hafted weapon would lie down the bow —
    the pickaxe's principal-axis failure at a larger scale. Extents are
    unambiguous here instead: the spread is the widest span, the stock the
    middle one, and the weapon's flat is the thinnest.
    """
    from mathutils import Matrix, Vector

    points = _vertices(numpy, obj)
    centred = points - points.mean(axis=0)
    _u, _s, vt = numpy.linalg.svd(centred, full_matrices=False)
    spread = Vector(tuple(vt[0])).normalized()      # widest: the bow
    stock = Vector(tuple(vt[1])).normalized()       # middle: the stock
    flat = spread.cross(stock)                      # thinnest: the flat

    basis = Matrix((
        (spread.x, stock.x, flat.x, 0.0),
        (spread.y, stock.y, flat.y, 0.0),
        (spread.z, stock.z, flat.z, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    ))
    obj.matrix_world = basis.inverted() @ obj.matrix_world
    _apply(bpy, obj)

    # Muzzle end (+Y) is the end nearer the BOW: the bow rides at the
    # front of the stock, so the half of the stock axis holding the widest
    # X-spread is forward. Measured, not guessed — the model gives no
    # other clue which way it faces down its own stock.
    points = _vertices(numpy, obj)
    mid = float(numpy.median(points[:, 1]))
    front = points[points[:, 1] >= mid]
    back = points[points[:, 1] < mid]
    if float(front[:, 0].ptp()) < float(back[:, 0].ptp()):
        obj.matrix_world = (
            Matrix.Rotation(3.141592653589793, 4, "Z") @ obj.matrix_world)
        _apply(bpy, obj)

    _scale_and_grip(bpy, numpy, obj, spec)


def _normalise_shield(bpy, numpy, obj, spec: dict) -> None:
    """Face normal +Y, long axis +Z, centred on the origin.

    A shield is a slab: its thinnest principal direction IS its face
    normal, its longest the way it stands. The boss decides which side is
    the front — the face bulges away from the arm — so +Y is the side the
    geometry leans toward.
    """
    from mathutils import Matrix, Vector

    points = _vertices(numpy, obj)
    centre = points.mean(axis=0)
    centred = points - centre
    _u, _s, vt = numpy.linalg.svd(centred, full_matrices=False)
    long_axis = Vector(tuple(vt[0])).normalized()
    across = Vector(tuple(vt[1])).normalized()
    normal = long_axis.cross(across)

    basis = Matrix((
        (across.x, normal.x, long_axis.x, 0.0),
        (across.y, normal.y, long_axis.y, 0.0),
        (across.z, normal.z, long_axis.z, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    ))
    obj.matrix_world = (
        basis.inverted() @ Matrix.Translation(Vector(tuple(-centre)))
        @ obj.matrix_world)
    _apply(bpy, obj)

    # The boss faces +Y: a shield's front carries more geometry off the
    # median plane than its strapped back does.
    points = _vertices(numpy, obj)
    ys = points[:, 1]
    if abs(float(ys.min())) > abs(float(ys.max())):
        obj.matrix_world = (
            Matrix.Rotation(3.141592653589793, 4, "Z") @ obj.matrix_world)
        _apply(bpy, obj)

    points = _vertices(numpy, obj)
    span = float(points[:, 2].max() - points[:, 2].min())
    scale = spec["size"] / span
    from mathutils import Matrix as M
    obj.matrix_world = M.Diagonal(
        Vector((scale, scale, scale, 1.0))) @ obj.matrix_world
    _apply(bpy, obj)


def _body_forward(armature) -> float:
    """Which way down Y this body faces, +1 or -1 — author_clips' own
    measurement, from the toes."""
    return _forward_sign(armature, _map_roles(armature))


def _hand_centroid(numpy, body, bone_name: str):
    """Where the MESH's hand actually is: the weighted centroid of the
    vertices bound to `bone_name`, in world space — or None when the body
    has no such group yet.

    The bone's own endpoints are not that: on a TRANSPLANTED rig
    (art/transplant_rig.py) the donor skeleton is height-matched but its
    arm proportions are the donor's, so the hand bone can end past the
    fingertips — and a weapon anchored there floats detached beyond the
    fist, which is exactly what the first spearman render showed.
    """
    group = body.vertex_groups.get(bone_name)
    if group is None:
        return None
    gi = group.index
    total = 0.0
    accum = None
    points = _world_vertices(numpy, body)
    for v in body.data.vertices:
        for g in v.groups:
            if g.group == gi and g.weight > 0.4:
                p = points[v.index]
                accum = p * g.weight if accum is None else accum + p * g.weight
                total += g.weight
    if accum is None or total <= 0.0:
        return None
    from mathutils import Vector
    return Vector(tuple(accum / total))


def _place_in_hand(bpy, numpy, armature, body, obj, spec: dict) -> str:
    """Lay a normalised weapon along the lead hand's own axis, gripped at
    the MESH's own fist.

    The basis is NORMALISED before it is used: the armature carries the
    body's import scale unapplied (import_glb_source corrects on the ROOT,
    deliberately), and a raw `matrix_world @ matrix_local` would scale the
    weapon by it — a 0.42 axe silently becoming 0.83. Kit lengths are
    stated in ENGINE units and must stay them; only the grip's position is
    scaled, because it is a position.
    """
    from mathutils import Matrix

    bone = armature.data.bones[WEAPON_BONE]
    frame = (armature.matrix_world @ bone.matrix_local).normalized()
    head = armature.matrix_world @ bone.head_local
    tail = armature.matrix_world @ bone.tail_local
    length = (tail - head).length

    at = _hand_centroid(numpy, body, WEAPON_BONE)
    if at is None:
        # No hand-weighted vertices to measure. On a transplanted rig that
        # is the NORM, not an edge case: the donor's hand bones end past
        # this body's fingertips, so bone heat deals the whole mitt to the
        # forearm and R_Hand binds nothing — and anchoring on the bone is
        # exactly the detached floating spear the first render showed. The
        # mesh's own arm tip is the honest measurement: the outermost slab
        # of vertices on the weapon side, pulled a fist's width inboard.
        from mathutils import Vector
        points = _world_vertices(numpy, body)
        arm_band = points[points[:, 2] > float(points[:, 2].max()) * 0.55]
        x_min = float(arm_band[:, 0].min())
        slab = arm_band[arm_band[:, 0] < x_min + 0.10]
        at = Vector((float(slab[:, 0].mean()) + 0.06,
                     float(slab[:, 1].mean()),
                     float(slab[:, 2].mean())))
        print("  weapon hand measured from the MESH (rig binds no hand): "
              "(%.2f, %.2f, %.2f)" % (at.x, at.y, at.z))
    offset = Matrix.Identity(4)
    frame.translation = at
    roll = Matrix.Rotation(
        3.141592653589793 / 180.0 * spec.get("roll", 0.0), 4, "Y")
    obj.matrix_world = frame @ offset @ roll
    _apply(bpy, obj)
    return WEAPON_BONE


def _place_on_forearm(bpy, numpy, armature, body, obj, spec: dict) -> str:
    """Strap a normalised shield to the outside of an arm."""
    from mathutils import Matrix, Vector

    arm_name = spec["arm"]
    if arm_name not in armature.data.bones:
        raise SystemExit(f"shield: no '{arm_name}' bone on this rig")
    bone = armature.data.bones[arm_name]
    head = armature.matrix_world @ bone.head_local
    tail = armature.matrix_world @ bone.tail_local
    mid = (head + tail) * 0.5
    along = (tail - head).normalized()
    # Anchor on the MESH's forearm when it has weights to measure — the
    # same transplanted-proportions reasoning as `_hand_centroid`.
    measured = _hand_centroid(numpy, body, arm_name)
    if measured is not None:
        mid = measured

    forward = Vector((0.0, _body_forward(armature), 0.0))

    # The shield's +Z (long axis) lies along the arm, its +Y (face) to the
    # body's forward — so when the base pose drops the arm to the side the
    # plate hangs upright and still faces the enemy.
    z_axis = along
    y_axis = forward.normalized()
    x_axis = y_axis.cross(z_axis).normalized()
    y_axis = z_axis.cross(x_axis).normalized()
    basis = Matrix((
        (x_axis.x, y_axis.x, z_axis.x, 0.0),
        (x_axis.y, y_axis.y, z_axis.y, 0.0),
        (x_axis.z, y_axis.z, z_axis.z, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    ))
    at = mid + forward * spec["clearance"]
    obj.matrix_world = Matrix.Translation(at) @ basis
    _apply(bpy, obj)
    return arm_name


def _world_vertices(numpy, obj):
    """An object's vertices in WORLD space. `_vertices` is object-local —
    which is the same thing for a kit item (its transforms are applied at
    every step) and is NOT for the body, whose scale and placement live
    unapplied on the armature root (import_glb_source's own rule: mutating
    a skinned mesh's vertices slides it off its bones)."""
    local = _vertices(numpy, obj)
    matrix = numpy.array(obj.matrix_world)
    return local @ matrix[:3, :3].T + matrix[:3, 3]


def _place_on_back(bpy, numpy, armature, body, obj, spec: dict) -> str:
    """Stand a normalised standard proud of the trunk's own measured depth."""
    from mathutils import Matrix, Vector

    forward = _body_forward(armature)
    bone = armature.data.bones[BACK_BONE]
    anchor = armature.matrix_world @ bone.head_local

    # The trunk's real depth, measured like the gatherer's pack was: the
    # deepest body vertex in the trunk band, plus a margin, so the pole is
    # proud of a backpack rather than buried in one.
    points = _world_vertices(numpy, body)
    band = points[(points[:, 2] > anchor.z - 0.25)
                  & (points[:, 2] < anchor.z + 0.25)]
    if forward > 0.0:
        depth = float(band[:, 1].min()) - 0.05
    else:
        depth = float(band[:, 1].max()) + 0.05

    # The pole's GRIP (near its butt) stands at a fraction of the BODY's own
    # height, so the flag at the pole's far end clears the helmet — a
    # standard buried in the torso with its butt poking out below the cape
    # is what the first placement produced, anchored to a spine bone that
    # sits most of the way up a model whose pole then ran on past its head.
    height = float(points[:, 2].max())
    at = Vector((anchor.x, depth, height * spec.get("base", 0.42)))
    # Pole up: the item's +Y (pole toward the flag) turns to world +Z, its
    # flag broadside X stays across the shoulders where the overhead
    # camera reads it. POSITIVE ninety: Rx(-90) maps +Y to -Z, which
    # planted the first standard flag-down under the general's feet —
    # attach_tools' roll-sign lesson, on a different axis.
    up = Matrix.Rotation(3.141592653589793 / 2.0, 4, "X")
    obj.matrix_world = Matrix.Translation(at) @ up
    _apply(bpy, obj)
    return BACK_BONE


# --- atlas ----------------------------------------------------------------

def _build_atlas(bpy, numpy, target: str, sources: dict, rects: dict):
    """attach_tools' atlas, re-parameterised: composite, save as JPEG, load
    back and PACK the encoded bytes (blend_source writes packed bytes
    through verbatim, which is both the fast path and the deterministic
    one — D-081)."""
    width, height = ATLAS_SIZE
    canvas = numpy.zeros((height, width, 4), dtype=numpy.float32)
    canvas[:, :, 3] = 1.0
    for key, image in sources.items():
        x, y, rect_w, rect_h = rects[key]
        canvas[y:y + rect_h, x:x + rect_w] = _resize(
            numpy, _read_pixels(numpy, image), rect_w, rect_h)

    atlas = bpy.data.images.new(f"{target}_atlas", width=width, height=height,
                                alpha=False)
    atlas.colorspace_settings.name = "sRGB"
    atlas.pixels.foreach_set(canvas.reshape(-1))
    atlas.file_format = "JPEG"
    atlas.update()

    staging_dir = tempfile.mkdtemp(prefix="edotmw-atlas-")
    staging = os.path.join(staging_dir, f"{target}_atlas.jpg")
    atlas.filepath_raw = staging
    atlas.save()
    bpy.data.images.remove(atlas)

    packed = bpy.data.images.load(staging)
    packed.name = f"{target}_atlas"
    packed.colorspace_settings.name = "sRGB"
    packed.pack()
    packed.filepath_raw = ""
    _assert_atlas(numpy, packed, sources, rects)
    os.remove(staging)
    os.rmdir(staging_dir)
    return packed


def _assert_atlas(numpy, atlas, sources: dict, rects: dict) -> None:
    """Assert the value on the far side of the boundary (D-100): the
    round-tripped atlas must reproduce its sources within JPEG loss."""
    baked = _read_pixels(numpy, atlas)
    for key, image in sources.items():
        x, y, rect_w, rect_h = rects[key]
        want = _resize(numpy, _read_pixels(numpy, image), rect_w, rect_h)
        got = baked[y:y + rect_h, x:x + rect_w]
        step_y, step_x = max(1, rect_h // 64), max(1, rect_w // 64)
        drift = float(numpy.abs(
            want[::step_y, ::step_x, :3] - got[::step_y, ::step_x, :3]).mean())
        if drift > ATLAS_TOLERANCE:
            raise SystemExit(
                f"atlas: {key} reads back {drift:.4f} from its source, past "
                f"{ATLAS_TOLERANCE}. A colour-management difference, not "
                "JPEG loss — check the colorspaces (D-100).")
        print(f"  atlas {key:14s} drift {drift:.4f}")


def _remap_uvs(obj, rect) -> None:
    x, y, rect_w, rect_h = rect
    width, height = ATLAS_SIZE
    layer = obj.data.uv_layers.active
    if layer is None:
        raise SystemExit(
            f"{obj.name}: no UV layer, so its share of the atlas cannot be "
            "addressed.")
    for datum in layer.data:
        datum.uv = (x / width + datum.uv[0] * rect_w / width,
                    y / height + datum.uv[1] * rect_h / height)


# --- joining --------------------------------------------------------------

def _join_and_weight(bpy, body, items: dict) -> dict:
    """Join every item into the body, weighted 1.0 to its carrying bone.

    Whole-vertex weighting for the same reason the tools use it: kit is
    rigid, and a vertex shared with the chest would stretch a haft every
    time the trunk twisted."""
    counts = {name: len(entry["object"].data.vertices)
              for name, entry in items.items()}

    _clear_selection(bpy)
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    for entry in items.values():
        entry["object"].select_set(True)
    first = len(body.data.vertices)
    bpy.ops.object.join()

    cursor = first
    ranges = {}
    for name, entry in items.items():
        ranges[name] = (cursor, counts[name])
        bone = entry["bone"]
        if bone in body.vertex_groups:
            group = body.vertex_groups[bone]
        else:
            group = body.vertex_groups.new(name=bone)
        indices = list(range(cursor, cursor + counts[name]))
        group.add(indices, 1.0, "REPLACE")
        for other in body.vertex_groups:
            if other.name != bone:
                other.remove(indices)
        cursor += counts[name]
        print(f"  {name:14s} -> bone {bone}, {counts[name]} vertices at 1.0")

    if cursor != len(body.data.vertices):
        raise SystemExit(
            f"joined mesh has {len(body.data.vertices)} vertices, expected "
            f"{cursor} — the item ranges are guesses now.")
    return ranges


def _clear_owner_mask(body, ranges: dict) -> None:
    """`bpy.ops.object.join` fills a missing COLOR_0 with opaque WHITE, and
    COLOR_0's alpha is the owner-colour mask (D-052) — which is how the
    gatherer's tools shipped bright red once already. Kit is wood and
    steel and belongs to nobody."""
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
    for polygon in body.data.polygons:
        for loop in polygon.loop_indices:
            if body.data.loops[loop].vertex_index in indices:
                layer.data[loop].color = (1.0, 1.0, 1.0, 0.0)


def _single_material(body, atlas) -> None:
    keep = body.material_slots[0].material
    for node in keep.node_tree.nodes:
        if node.type == "TEX_IMAGE":
            node.image = atlas
    for polygon in body.data.polygons:
        polygon.material_index = 0
    while len(body.material_slots) > 1:
        body.data.materials.pop(index=1)


def attach(target: str) -> None:
    import bpy
    import numpy

    if target not in KITS:
        raise SystemExit(
            f"{target}: no kit defined. KITS covers {sorted(KITS)}.")
    kit = KITS[target]
    if len(kit) > len(ITEM_RECTS):
        raise SystemExit(
            f"{target}: {len(kit)} items but only {len(ITEM_RECTS)} atlas "
            "strips. Add a rectangle deliberately, with the resize maths.")

    path = source_path(target)
    if not os.path.exists(path):
        raise SystemExit(f"{target}: no authored source at {path}")

    bpy.ops.wm.open_mainfile(filepath=path, load_ui=False)
    body = bpy.data.objects.get(target)
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if body is None or not armatures:
        raise SystemExit(
            f"{target}: expected a mesh named '{target}' and an armature in "
            f"{os.path.relpath(path, _ROOT)}; found "
            f"{[(o.name, o.type) for o in bpy.data.objects]}.")
    armature = armatures[0]
    for bone in (WEAPON_BONE, BACK_BONE):
        if bone not in armature.data.bones:
            raise SystemExit(
                f"{target}: this rig has no '{bone}' bone. It has: "
                f"{[b.name for b in armature.data.bones]}")

    body.data.calc_loop_triangles()
    body_tris = len(body.data.loop_triangles)
    print(f"attaching kit to {os.path.relpath(path, _ROOT)} "
          f"({body_tris} tris):")

    items = {}
    total = body_tris
    for name in sorted(kit):
        spec = kit[name]
        obj = _import_item(bpy, name, spec)
        source_tris = len(obj.data.loop_triangles) \
            if obj.data.loop_triangles else 0
        tris = _decimate(bpy, obj, KIT_TRIANGLES)
        mode = spec["mode"]
        if mode == "hand":
            _normalise_hafted(bpy, numpy, obj, name, spec)
            bone = _place_in_hand(bpy, numpy, armature, body, obj, spec)
        elif mode == "polearm":
            # A spear's broad blade and crossguard defeat the butt-ball
            # handle fit exactly the way a banner's cloth does — the pole
            # normalisation is the honest one for anything head-heavy on a
            # very long shaft, and a fist around a spear grips mid-shaft
            # where no head can confuse the line.
            _normalise_pole(bpy, numpy, obj, spec)
            bone = _place_in_hand(bpy, numpy, armature, body, obj, spec)
        elif mode == "crossbow":
            _normalise_crossbow(bpy, numpy, obj, spec)
            bone = _place_in_hand(bpy, numpy, armature, body, obj, spec)
        elif mode == "shield":
            _normalise_shield(bpy, numpy, obj, spec)
            bone = _place_on_forearm(bpy, numpy, armature, body, obj, spec)
        elif mode == "back":
            _normalise_pole(bpy, numpy, obj, spec)
            bone = _place_on_back(bpy, numpy, armature, body, obj, spec)
        else:
            raise SystemExit(f"{name}: unknown mode '{mode}'")
        items[name] = {"object": obj, "bone": bone, "tris": tris}
        total += tris
        print(f"  {name:14s} {tris} tris [{mode}] -> {bone}")

    sources = {target: _image_of(body)}
    rects = {target: BODY_RECT}
    for slot, name in enumerate(sorted(items)):
        image = _image_of(items[name]["object"])
        if image is None:
            raise SystemExit(
                f"{name}: no Base Color image. Every part of a textured "
                "model has to be in the atlas.")
        sources[name] = image
        rects[name] = ITEM_RECTS[slot]
    if sources[target] is None:
        raise SystemExit(f"{target}: the body has no Base Color image.")

    atlas = _build_atlas(bpy, numpy, target, sources, rects)
    _remap_uvs(body, rects[target])
    for name in sorted(items):
        _remap_uvs(items[name]["object"], rects[name])

    ranges = _join_and_weight(bpy, body, items)
    _clear_owner_mask(body, ranges)
    _single_material(body, atlas)

    bpy.ops.wm.save_mainfile()
    print(f"  {target} is now {total} tris ({total * 3} VAT columns) "
          f"with {len(items)} kit items")
    print(f"  wrote {os.path.relpath(path, _ROOT)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True,
                        help="archetype whose kit to attach (see KITS)")
    args = parser.parse_args()
    attach(args.name)


if __name__ == "__main__":
    main()
