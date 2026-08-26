"""Authored `.blend` files as the source of truth for units and buildings
(D-20260821-game-assets-are-files).

`art/source/<name>.blend` is a normal Blender file. You open it, model, rig,
animate and save it exactly as you would for any other game, and
`just build-assets` turns it into the `.glb` and VAT the client already
consumes. Nothing in the engine, the shader, the wire or the simulation knows
the difference — D-082's VAT stores final vertex positions and has never had an
opinion about how they were produced.

## What this module does, and the one thing it must not get wrong

It evaluates the file's animation frame by frame through Blender's dependency
graph and flattens each frame into the arrays `bake.write_glb` and
`bake.write_vat` already take. Whatever produced the deformation — an
armature, shape keys, parented objects, a lattice, a modifier stack — is the
artist's business and is invisible here, which is the whole point of baking.

**The vertex ORDER is the contract** between the mesh and the VAT column, and
it must be identical on every frame or a model animates into confetti. Two
things secure it:

- objects are visited in NAME order, not in whatever order Blender's
  collection happens to hold them, so adding an object cannot silently
  renumber the columns of the ones before it;
- the topology is asserted constant across frames (`_assert_stable`). A
  generative modifier whose output count varies with the pose — Remesh,
  Decimate on a driven ratio, Boolean against a moving object — breaks the
  contract, and it breaks it *quietly*: the bake would succeed and the model
  would come apart at one frame in sixty-four. So it is checked rather than
  hoped for, and the error names the frame and the modifier stack to look at.

## Blender is Z-up and the game is Y-up, and the FILE is Z-up

`geom.py` authors in Y-up to match Godot, and `bake.py` exports with
`export_yup=False` so the numbers reach the engine untouched. That was
unambiguously right while a Python generator wrote every vertex and no human
ever opened the result.

It is wrong for a file somebody MODELS in. A Y-up mesh in a Z-up application
lies on its back: the floor grid is a wall, front and side ortho views are
swapped, a mirror modifier reflects the wrong axis, gravity points sideways and
every rigging tool Blender has assumes Z-up. Measured on the first seeded
militia: 1.68 units "deep" along Y and 0.37 "tall" along Z.

So `art/source/*.blend` is **Z-up, Blender-native**, and the conversion happens
HERE, at the boundary, on the way out. That is what every glTF exporter does
and it is the reason `export_yup=False` can stay: by the time `write_glb` sees
these arrays they are already in the engine's space.

`_to_engine` is the whole conversion, and it is applied to positions and
normals alike. Getting it wrong is loud rather than subtle — the model arrives
in the game rotated a quarter turn — but `tests/test_authored_assets.gd` pins
the direction anyway, because "loud" still means somebody has to be looking.

## Rest pose

The `.glb` holds the mesh evaluated at `REST_FRAME`, and every VAT row stores
the offset from it. Row `REST_FRAME` is therefore all zeros, which is correct
rather than wasteful: the shader adds the offset to the mesh it already has.

## Flat shading, still

`flatten()` in `bake.py` splits one vertex per triangle corner because the look
is flat-shaded. This does the same, for the same reason, and because a split
vertex list is what makes every vertex uniquely addressable by a VAT column.
Smooth shading would need one column per *shared* vertex and a different
normal strategy; it is not what this project draws.

## Colour and the owner mask

Read from the mesh's `COLOR_0` attribute: rgb is the surface colour, ALPHA is
how much of it takes the owning player's colour (D-052). That is the same
convention the generated path uses, so a `.blend` seeded from a generator and
one modelled from scratch mean the same thing by it, and it is paintable in
Blender's vertex paint mode with no custom tooling.

A mesh with no `COLOR_0` layer is not an error — it bakes flat white with a
zero mask, which reads as "not yet coloured" rather than failing a build over
work in progress.
"""

from __future__ import annotations

import os

from .clips import FRAMES_PER_CLIP, clips_for

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(os.path.dirname(_HERE))

SOURCE_DIR = os.path.join(_ROOT, "art", "source")

# Frame 0 of `idle`. The clips are laid out along the timeline in CLIP_ORDER,
# FRAMES_PER_CLIP each, so this is a real authored pose rather than a synthetic
# T-pose nothing plays — which means an artist can see the rest pose by
# scrubbing to the start rather than having to know about a hidden convention.
REST_FRAME = 0


def total_frames(name: str) -> int:
    """How many frames `name`'s timeline is expected to hold.

    A function rather than the module constant it used to be, because a model
    bakes only ITS OWN clips now (`clips.clips_for`) — a gatherer's timeline
    is 112 frames where a militia's is 64, and a single constant would have
    baked 48 frames of frozen rout onto every soldier in the roster to serve
    the one unit that swings an axe.
    """
    return FRAMES_PER_CLIP * len(clips_for(name))


def source_path(name: str) -> str:
    return os.path.join(SOURCE_DIR, f"{name}.blend")


def has_source(name: str) -> bool:
    """Whether this archetype is authored rather than generated.

    The two paths coexist on purpose: migrating the roster one model at a time
    is the only way to do it without a flag day, and props and the terrain
    atlas are staying generated because generation is genuinely right for
    them (see the decision entry).
    """
    return os.path.exists(source_path(name))


def _to_engine(v) -> tuple[float, float, float]:
    """Blender Z-up -> engine Y-up. The inverse of `seed_source._to_blender`.

    A -90 degrees rotation about X: (x, y, z) -> (x, z, -y). Written as an
    explicit tuple rather than a matrix multiply because it runs once per
    vertex per frame — 396 x 64 for one militia — and because the whole
    conversion being three named components is what makes it checkable by eye
    against its inverse.
    """
    return (v[0], v[2], -v[1])


def _mesh_objects(bpy):
    """Every renderable mesh, in NAME order. See the module docstring."""
    return sorted((o for o in bpy.context.scene.objects
                   if o.type == "MESH" and not o.hide_render),
                  key=lambda o: o.name)


def _evaluate(bpy, frame: int) -> tuple[list, list, list, list, list, dict]:
    """Flatten the whole scene at `frame` into split, flat-shaded arrays."""
    bpy.context.scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()

    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    colours: list[tuple[float, float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    owners: list[str] = []
    origins: dict[str, tuple[float, float, float]] = {}

    for obj in _mesh_objects(bpy):
        evaluated = obj.evaluated_get(depsgraph)
        # The object's ORIGIN is what a Part calls its pivot, and what
        # `door_hinge_uv` reads to swing a gate leaf about its hinge.
        t = evaluated.matrix_world.translation
        origins[obj.name] = _to_engine((t.x, t.y, t.z))
        mesh = evaluated.to_mesh()
        try:
            mesh.calc_loop_triangles()
            # World space: the object's own transform is part of the pose. A
            # rigid part animated by rotating the OBJECT carries all of its
            # motion here and none in its vertices, which is exactly how the
            # seeded files are built.
            matrix = evaluated.matrix_world
            rotation = matrix.to_3x3().inverted_safe().transposed()

            layer = mesh.color_attributes.get("COLOR_0")
            # The model's OWN texture coordinates, when it has any. A
            # generated part has none and gets (0, 0), which is what UV0
            # has always been for this roster; a model that arrived with a
            # texture keeps the coordinates that make that texture mean
            # something (D-20260824-a-textured-model-keeps-its-texture).
            uv_layer = mesh.uv_layers.active
            for tri in mesh.loop_triangles:
                # The face normal, transformed — flat shading means every
                # corner of a triangle shares it.
                n = (rotation @ tri.normal).normalized()
                for corner, vertex_index in zip(tri.loops, tri.vertices):
                    co = matrix @ mesh.vertices[vertex_index].co
                    positions.append(_to_engine((co.x, co.y, co.z)))
                    normals.append(_to_engine((n.x, n.y, n.z)))
                    colours.append(_colour_at(layer, mesh, corner, vertex_index))
                    if uv_layer is None:
                        uvs.append((0.0, 0.0))
                    else:
                        uv = uv_layer.data[corner].uv
                        uvs.append((uv[0], uv[1]))
                    owners.append(obj.name)
        finally:
            evaluated.to_mesh_clear()

    return positions, normals, colours, uvs, owners, origins


def _colour_at(layer, mesh, corner: int, vertex_index: int):
    """COLOR_0 for one corner, whichever domain the artist's layer uses.

    Blender stores a colour attribute on either CORNER or POINT, and vertex
    paint produces both depending on how the layer was made. Handling only one
    would silently drop an artist's colours for a file authored the other way,
    with nothing failing — so both are read.
    """
    if layer is None:
        return (1.0, 1.0, 1.0, 0.0)
    index = corner if layer.domain == "CORNER" else vertex_index
    c = layer.data[index].color
    return (c[0], c[1], c[2], c[3])


def _save_basecolor(bpy, name: str, texture_dir: str | None) -> str:
    """Write this model's basecolor image out, and return its repo path.

    Empty string when the model has no texture, which is every GENERATED
    model in the roster — they carry their colour on vertices and always
    have. A model that arrived with one keeps it
    (D-20260824-a-textured-model-keeps-its-texture): vertex colour cannot
    be mipmapped, so a dense textured model reduced to per-vertex colour
    aliases into noise at soldier scale, which is exactly what it did.
    """
    if texture_dir is None:
        return ""
    image = None
    for obj in _mesh_objects(bpy):
        for slot in obj.material_slots:
            material = slot.material
            if material is None or not material.use_nodes:
                continue
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is not None:
                    image = node.image
                    break
    if image is None:
        return ""

    os.makedirs(texture_dir, exist_ok=True)

    # THE PACKED BYTES ARE WRITTEN VERBATIM, and the extension follows what
    # they actually ARE.
    #
    # `image.file_format = "PNG"; image.save()` does not re-encode a packed
    # image — it writes the source bytes and ignores the format. That put a
    # JPEG on disk called `.png`, Godot's importer marked it `valid=false`,
    # and the only symptom anywhere was a "Failed loading resource" line in
    # a render log while the model kept drawing with its fallback colours.
    # Naming a file after a format it is not is the whole bug.
    #
    # Writing the bytes through is also better than re-encoding: no second
    # lossy pass, no colour-space round trip (the D-100 family), and two
    # builds are byte-identical for free, which D-081 requires.
    data = bytes(image.packed_file.data) if image.packed_file else b""
    # Magic numbers as byte VALUES rather than escape sequences: this file
    # is edited by tooling as well as by people, and an escape that does
    # not survive a round trip is a syntax error at best.
    png_magic = bytes([137, 80, 78, 71, 13, 10, 26, 10])
    if data[:8] == png_magic:
        suffix = ".png"
    elif data[:2] == bytes([255, 216]):
        suffix = ".jpg"
    else:
        # Not packed, or a format not recognised here. Re-encode through a
        # COPY: a fresh image is not packed, so `save()` honours its format.
        copy = bpy.data.images.new(f"{name}_albedo", width=image.size[0],
                                   height=image.size[1], alpha=True)
        copy.colorspace_settings.name = image.colorspace_settings.name
        copy.pixels = list(image.pixels)
        copy.file_format = "PNG"
        out = os.path.join(texture_dir, f"{name}.png")
        copy.filepath_raw = out
        copy.save()
        bpy.data.images.remove(copy)
        return os.path.relpath(out, _ROOT).replace(os.sep, "/")

    out = os.path.join(texture_dir, f"{name}{suffix}")
    with open(out, "wb") as handle:
        handle.write(data)
    return os.path.relpath(out, _ROOT).replace(os.sep, "/")


def bake(name: str, texture_dir: str | None = None) -> tuple[dict, tuple[list, list]]:
    """Open `art/source/<name>.blend` and bake it.

    Returns `(flat, (positions_per_frame, normals_per_frame))` — exactly the
    shapes `bake.write_glb` and `bake.write_vat` take, so an authored model and
    a generated one go through the same writers and cannot drift in layout.
    """
    import bpy

    path = source_path(name)
    if not os.path.exists(path):
        raise SystemExit(f"{name}: no authored source at {path}")

    # `load_ui=False` so the file's saved window layout does not follow it into
    # a headless build; the geometry is what is wanted, not the workspace.
    bpy.ops.wm.open_mainfile(filepath=path, load_ui=False)

    rest_positions, rest_normals, rest_colours, rest_uvs, owners, origins =         _evaluate(bpy, REST_FRAME)
    if not rest_positions:
        raise SystemExit(
            f"{name}: {os.path.relpath(path, _ROOT)} has no visible mesh at frame "
            f"{REST_FRAME}. An empty bake would write a valid, invisible model.")

    positions_per_frame: list[list] = []
    normals_per_frame: list[list] = []
    for frame in range(total_frames(name)):
        if frame == REST_FRAME:
            positions_per_frame.append(rest_positions)
            normals_per_frame.append(rest_normals)
            continue
        positions, normals, _colours, _uvs, frame_owners, _origins =             _evaluate(bpy, frame)
        _assert_stable(name, frame, owners, frame_owners, len(rest_positions),
                       len(positions))
        positions_per_frame.append(positions)
        normals_per_frame.append(normals)

    flat = {
        "positions": rest_positions,
        "normals": rest_normals,
        "colours": rest_colours,
        "uvs": rest_uvs,
        "texture": _save_basecolor(bpy, name, texture_dir),
        "triangles": [(i, i + 1, i + 2)
                      for i in range(0, len(rest_positions), 3)],
        "owners": owners,
        "origins": origins,
    }
    return flat, (positions_per_frame, normals_per_frame)


def _assert_stable(name: str, frame: int, rest_owners: list, frame_owners: list,
                   rest_count: int, frame_count: int) -> None:
    """Refuse a source whose topology moves with the pose.

    See the module docstring: this is the failure that would otherwise be
    silent. A count mismatch is checked first because it is the cheap test;
    the owner list catches the nastier case where a modifier adds as many
    vertices to one object as it removes from another and the total is
    unchanged.
    """
    if frame_count != rest_count:
        raise SystemExit(
            f"{name}: frame {frame} has {frame_count} vertices against "
            f"{rest_count} at the rest frame. The VAT addresses vertices by "
            f"column, so the topology must not change with the pose — look for "
            f"a generative modifier (Remesh, Decimate, Boolean, Build) driven "
            f"by the animation.")
    if frame_owners != rest_owners:
        raise SystemExit(
            f"{name}: frame {frame} has the same vertex COUNT but a different "
            f"distribution across objects, so column N is a different vertex "
            f"than it is at rest. Same cause as a count mismatch, and the same "
            f"fix: no modifier whose output depends on the pose.")
