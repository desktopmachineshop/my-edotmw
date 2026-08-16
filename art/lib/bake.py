"""Flat-shading split, glTF export and VAT baking (D-064, D-065).

The only module that imports `bpy`. Everything upstream is plain arithmetic so
it can be iterated on without Blender in the loop; this is where the result
becomes files Godot can import.

## The split-vertex list is the contract

`flatten()` expands the model into one vertex per triangle corner, which is what
flat shading needs and what makes every vertex unique. Its ORDER is the contract
between the mesh and the VAT: vertex `i` of the mesh is column `i` of the
texture.

That contract is not defended by hoping the glTF exporter preserves order — it
is carried in the mesh. Each vertex stores its own index in `UV2.x`, so however
the exporter reorders or re-emits vertices, every one still points at its own
column. This is also why `VERTEX_ID` is not used: D-065 wants the shader to run
under GL Compatibility, and an attribute the mesh carries is portable in a way a
built-in may not be.

## Texture layout

    width  = vertex count
    height = total_frames * 2 + 1

    rows [0, total_frames)              position OFFSET from the rest pose
    rows [total_frames, total_frames*2) animated normal
    row  total_frames*2                 rgb = part colour, a = owner mask

## Why colour lives in the texture rather than in the mesh

The model carries COLOR_0 too, and it survives the glTF round trip — but a
MultiMesh overrides the shader's `COLOR` with its own per-instance colour, so a
vertex colour attribute never reaches the fragment stage on the path this game
actually renders through. That was observed, not assumed: a diagnostic render
showed UV2 arriving correctly and COLOR arriving as a flat zero, which is why
every soldier came out black.

Putting colour in the VAT costs one more texel fetch and removes the dependency
entirely — the same column index already in hand addresses position, normal and
colour alike. The mesh keeps COLOR_0 because `art/preview.py` and any external
tool still read it.

Offsets rather than absolute positions: the rest pose is already in the mesh, so
storing the delta keeps values small and centred on zero, which matters for
precision and matters a great deal if the RGBA8 fallback is ever needed.

Half-float EXR, nearest-filtered, no mipmaps. Filtering or mipmapping a VAT
blends unrelated vertices together, which shows up as a model that melts.
"""

from __future__ import annotations

import math
import os

from .clips import CLIP_ORDER, FRAMES_PER_CLIP, GROUP_OF, pose_at
from .geom import Model, Vec3, pose_part


def _face_normal(a: Vec3, b: Vec3, c: Vec3) -> Vec3:
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length < 1e-12:
        return (0.0, 1.0, 0.0)
    return (nx / length, ny / length, nz / length)


def flatten(model: Model) -> dict:
    """Expand a model into flat-shaded, per-corner vertices.

    Returns the canonical arrays plus, for each vertex, which part it came from
    and that part's index — the bake needs both to pose a vertex.
    """
    positions: list[Vec3] = []
    normals: list[Vec3] = []
    colours: list[tuple[float, float, float, float]] = []
    part_index: list[int] = []
    local_index: list[int] = []

    for pi, part in enumerate(model.parts):
        for tri in part.faces:
            a, b, c = (part.verts[tri[0]], part.verts[tri[1]], part.verts[tri[2]])
            n = _face_normal(a, b, c)
            for corner, vert in zip(tri, (a, b, c)):
                positions.append(vert)
                normals.append(n)
                colours.append((part.rgb[0], part.rgb[1], part.rgb[2], part.mask))
                part_index.append(pi)
                local_index.append(corner)

    triangles = [(i, i + 1, i + 2) for i in range(0, len(positions), 3)]
    return {
        "positions": positions,
        "normals": normals,
        "colours": colours,
        "triangles": triangles,
        "part_index": part_index,
        "local_index": local_index,
    }


def bake_frames(model: Model, flat: dict) -> tuple[list[list[Vec3]], list[list[Vec3]]]:
    """Evaluate every frame of every clip.

    Returns (positions_per_frame, normals_per_frame), each a list of
    `total_frames` lists of `vertex_count` vectors. Frames are independent by
    construction — see the module docstring in `clips.py`.
    """
    positions_per_frame: list[list[Vec3]] = []
    normals_per_frame: list[list[Vec3]] = []

    for clip in CLIP_ORDER:
        for f in range(FRAMES_PER_CLIP):
            phase = f / FRAMES_PER_CLIP
            pose = pose_at(clip, phase)

            # Pose each part once, then read vertices out of it, rather than
            # posing per vertex: a part is up to 24 triangles and the rotation
            # maths is the expensive half.
            posed_parts: list[list[Vec3]] = []
            for part in model.parts:
                group = GROUP_OF.get(part.name)
                rotations = pose.rotations.get(group, []) if group else []
                posed_parts.append(pose_part(part, rotations, pose.offset))

            frame_positions: list[Vec3] = []
            for pi, li in zip(flat["part_index"], flat["local_index"]):
                frame_positions.append(posed_parts[pi][li])

            frame_normals: list[Vec3] = []
            for t in range(0, len(frame_positions), 3):
                n = _face_normal(frame_positions[t], frame_positions[t + 1],
                                 frame_positions[t + 2])
                frame_normals.extend((n, n, n))

            positions_per_frame.append(frame_positions)
            normals_per_frame.append(frame_normals)

    return positions_per_frame, normals_per_frame


# --- Blender-side output ------------------------------------------------


def door_hinge_uv(model: Model, flat: dict) -> list[tuple[float, float]]:
    """Per-vertex (is_door_leaf, hinge_x) for a building with a hinged gate
    leaf (D-076 playtest amendment).

    Buildings carry no VAT (D-064's "a town hall does not walk"), so UV1 —
    everywhere else the VAT column index — is otherwise unused on them.
    `building_static.gdshader` reads it to swing exactly the tagged part
    open about its own hinge edge, driven by the `gate_open` uniform rather
    than TIME the way a soldier's phase is. Every part but a gate's own
    "gate_leaf" (see `art/buildings/_add_gate_leaf`) gets (0.0, 0.0), which
    the shader treats as "not a door" and leaves untouched.
    """
    out: list[tuple[float, float]] = []
    for pi in flat["part_index"]:
        part = model.parts[pi]
        if part.name == "gate_leaf":
            out.append((1.0, part.pivot[0]))
        else:
            out.append((0.0, 0.0))
    return out


def write_glb(model: Model, flat: dict, path: str,
              uv1_override: list[tuple[float, float]] | None = None) -> None:
    """Build a Blender mesh from the flattened arrays and export glTF binary.

    `uv1_override`, when given, replaces the VATIndex UV1 layer below with
    a caller-supplied per-vertex value instead — see `door_hinge_uv`, the
    only current user. Units never pass this; a building's UV1 would
    otherwise sit unused end to end.
    """
    import bpy

    _reset_scene(bpy)

    mesh = bpy.data.meshes.new(model.name)
    mesh.from_pydata([tuple(v) for v in flat["positions"]], [], flat["triangles"])
    mesh.update()

    obj = bpy.data.objects.new(model.name, mesh)
    bpy.context.collection.objects.link(obj)

    # Vertex colour: rgb is the part's own colour, ALPHA is the owner-colour
    # mask (D-052). Named COLOR_0 so glTF carries it as the standard attribute.
    layer = mesh.color_attributes.new(name="COLOR_0", type="FLOAT_COLOR",
                                      domain="CORNER")
    for i, loop in enumerate(mesh.loops):
        layer.data[i].color = flat["colours"][loop.vertex_index]

    # UV0 is unused at this tier (units are vertex-coloured, not textured) but
    # glTF wants a first UV set before a second, so it is written flat.
    uv0 = mesh.uv_layers.new(name="UVMap")
    uv1 = mesh.uv_layers.new(name="VATIndex")
    width = len(flat["positions"])
    for i, loop in enumerate(mesh.loops):
        uv0.data[i].uv = (0.0, 0.0)
        if uv1_override is not None:
            uv1.data[i].uv = uv1_override[loop.vertex_index]
        else:
            # Texel CENTRE, so nearest filtering lands unambiguously in
            # column i.
            uv1.data[i].uv = ((loop.vertex_index + 0.5) / width, 0.5)

    mesh.shade_flat()

    # `export_all_vertex_colors` rather than the old `export_colors`: Blender
    # 4.x renamed these, and the mesh has no material, so the "active vertex
    # colour when no material" switch is what actually carries COLOR_0 out.
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_normals=True,
        export_texcoords=True,
        export_all_vertex_colors=True,
        export_active_vertex_color_when_no_material=True,
        # NOT yup. Blender is Z-up and glTF is Y-up, so the exporter normally
        # rotates on the way out — but `geom.py` authors in Y-up already, to
        # match Godot. Letting the exporter convert would rotate the mesh while
        # the VAT offsets stayed in the authored space, and the two would
        # disagree: soldiers rendered lying on their backs, animated sideways.
        # Observed as a 0.37-tall bounding box on a model built 1.8 tall.
        export_yup=False,
        use_selection=False,
    )


def _srgb_to_linear(c: float) -> float:
    """The inverse of the transfer function Godot's glTF importer applies."""
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def write_prop_glb(model: Model, path: str) -> dict:
    """Export a ground-cover prop: real glTF materials, no VAT (D-100).

    ## Why props carry materials when nothing else here does

    Units and buildings put their colour in COLOR_0 (buildings) or the VAT
    (units) and read it back in a shader this project owns. Props can do
    neither. They are drawn from one MultiMesh per (chunk, model) — thousands
    of scene nodes is the M4 `by_id` shape — and a MultiMesh OVERRIDES the
    shader's `COLOR` with its own per-instance colour, which is exactly how
    every soldier came out black in M7. A prop drawn that way would lose the
    difference between a mushroom's stem and its cap.

    So a prop's colour lives in an ordinary glTF material, one per distinct
    part colour, which survives the MultiMesh path untouched and needs no
    shader at all. That is also how the authored TREES already render
    (client.gd sets no material_override on a tree chunk), so this is the
    proven path for scattered vegetation rather than a new one.

    No COLOR_0: the exporter drops a vertex colour layer no material's node
    tree reads (it says so, in a warning worth not ignoring), so writing one
    here would be code that looks like a fallback and is not one.

    Returns the mesh statistics the manifest records.
    """
    import bpy

    _reset_scene(bpy)

    # Parts flow into one mesh, grouped by material. Vertices are NOT split
    # per corner the way `flatten` splits them: props have no VAT, so there is
    # no column contract to honour, and `shade_flat` gives the faceted look
    # without paying three vertices per triangle.
    verts: list[Vec3] = []
    faces: list[tuple[int, int, int]] = []
    face_material: list[int] = []
    palette: list[tuple[float, float, float]] = []

    for part in model.parts:
        base = len(verts)
        verts.extend(tuple(v) for v in part.verts)
        if part.rgb not in palette:
            palette.append(tuple(part.rgb))
        index = palette.index(tuple(part.rgb))
        for tri in part.faces:
            faces.append((base + tri[0], base + tri[1], base + tri[2]))
            face_material.append(index)

    mesh = bpy.data.meshes.new(model.name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()

    obj = bpy.data.objects.new(model.name, mesh)
    bpy.context.collection.objects.link(obj)

    for i, rgb in enumerate(palette):
        material = bpy.data.materials.new(name="%s_%d" % (model.name, i))
        material.use_nodes = True
        shader = material.node_tree.nodes["Principled BSDF"]
        # sRGB -> linear on the way in, because Godot's glTF importer does
        # linear -> sRGB on the way out and NOTHING undoes it at render time.
        # Without this, an authored 0.36 arrives as albedo 0.63: measured, not
        # assumed (dump a prop's StandardMaterial3D and compare), and visible
        # as foliage that looks frosted next to ground painted with the same
        # numbers through the vertex-colour path.
        #
        # The property being preserved is that a prop coloured X renders as a
        # building part coloured X — one palette across the whole game, not one
        # per asset pipeline. tests/test_ground_cover.gd asserts it against the
        # imported material.
        linear = tuple(_srgb_to_linear(c) for c in rgb)
        shader.inputs["Base Color"].default_value = (
            linear[0], linear[1], linear[2], 1.0)
        # Matches `building_static.gdshader`'s ROUGHNESS 0.9 and its disabled
        # specular: a fern that glints when a town hall does not would read as
        # a different game's asset.
        shader.inputs["Roughness"].default_value = 0.9
        shader.inputs["Metallic"].default_value = 0.0
        mesh.materials.append(material)

    for polygon, index in zip(mesh.polygons, face_material):
        polygon.material_index = index

    mesh.shade_flat()

    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_normals=True,
        export_materials="EXPORT",
        # Y-up already, as everywhere else here — see write_glb.
        export_yup=False,
        use_selection=False,
    )
    # The AUTHORED colours, in surface order, so the Godot side can assert that
    # what it imported is what was painted here.
    return {
        "materials": len(palette),
        "vertices": len(verts),
        "colours": [[round(c, 6) for c in rgb] for rgb in palette],
    }


def write_vat(model: Model, flat: dict, path: str) -> dict:
    """Bake every clip into a half-float EXR. Returns the layout metadata."""
    import bpy

    positions_per_frame, normals_per_frame = bake_frames(model, flat)
    rest = flat["positions"]
    width = len(rest)
    total_frames = len(positions_per_frame)
    colour_row = total_frames * 2
    height = colour_row + 1

    # Blender image pixels are a flat RGBA list, bottom row first.
    pixels = [0.0] * (width * height * 4)

    def put(row: int, col: int, value, alpha: float = 1.0) -> None:
        i = (row * width + col) * 4
        pixels[i] = value[0]
        pixels[i + 1] = value[1]
        pixels[i + 2] = value[2]
        pixels[i + 3] = alpha

    for f in range(total_frames):
        frame_positions = positions_per_frame[f]
        frame_normals = normals_per_frame[f]
        for c in range(width):
            p, r = frame_positions[c], rest[c]
            put(f, c, (p[0] - r[0], p[1] - r[1], p[2] - r[2]))
            put(total_frames + f, c, frame_normals[c])

    for c in range(width):
        colour = flat["colours"][c]
        put(colour_row, c, colour, alpha=colour[3])

    image = bpy.data.images.new(f"{model.name}_vat", width=width, height=height,
                                alpha=True, float_buffer=True, is_data=True)
    image.pixels = pixels
    image.file_format = "OPEN_EXR"

    # Half float + ZIP. These are committed (D-064), so every art iteration
    # writes them into git history; uncompressed 32-bit was ~800 KB per
    # archetype for data that halves and then compresses losslessly.
    #
    # `save_render` rather than `save`, because the codec and bit depth live in
    # the scene's image settings and `save` does not consult them. The cost is
    # that `save_render` applies colour management — so the view transform is
    # forced to Raw first. A VAT run through a filmic curve would look like a
    # working animation with subtly wrong limb positions, which is a far worse
    # failure than a crash.
    scene = bpy.context.scene
    scene.view_settings.view_transform = "Raw"
    settings = scene.render.image_settings
    settings.file_format = "OPEN_EXR"
    settings.color_mode = "RGBA"
    settings.color_depth = "16"
    settings.exr_codec = "ZIP"
    image.save_render(filepath=path, scene=scene)

    return {
        "width": width,
        "height": height,
        "total_frames": total_frames,
        "colour_row": colour_row,
        "frames_per_clip": FRAMES_PER_CLIP,
        "clips": list(CLIP_ORDER),
    }


def _reset_scene(bpy) -> None:
    """Empty the default scene so a build is not order-dependent."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh, do_unlink=True)
    # Materials too, since `write_prop_glb` creates them (D-100). Blender
    # de-duplicates names by appending .001, so a leftover material from the
    # previous prop would rename this one's and put a build-order dependency
    # into the exported bytes — precisely what D-081's byte-identical rule
    # forbids. A no-op for units and buildings, which have no materials.
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material, do_unlink=True)
