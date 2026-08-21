"""The generators, open in the real Blender GUI
(D-20260821-the-blender-gui-is-a-window-on-the-generators).

    just blender-gui [TARGET]          # the owner's entry point
    blender --python art/gui.py -- --target=militia
    tools/blender-venv/bin/python art/gui.py --check    # no GUI, see below

## What this is, and the one rule that keeps it honest

D-081 chose generated-not-hand-modelled art and gave the reason: this project's
premise is that its assets stay editable by Claude Code, and a hand-sculpted
`.blend` is the one thing `CLAUDE.md` flags as an exception rather than the
default path. Nothing here changes that.

So this file is a WINDOW, not a workshop. It builds the scene by calling the
same `art/` generators `art/build.py` calls, and it writes nothing except by
invoking `art/build.py` itself. **It contains no geometry of its own** — no
`box()`, no `prism()`, no vertex literal — and `tests/test_blender_gui.gd`
fails if any appears. The moment this file could produce a shape the headless
build cannot, `generated/` has two sources of truth and the committed build
product stops being reproducible from `art/`.

What the GUI buys, which headless `bpy` genuinely cannot:

- **Looking at the thing from an angle you chose.** `art/preview.py` renders one
  fixed three-quarter view; `just gen-model-preview` renders the shipping path
  but frames it its way. Neither lets you get under a shield to see whether the
  spear goes through the man's head.
- **Scrubbing the animation.** The timeline here IS the VAT: frame N shows
  exactly the vertex positions row N of `generated/vat/<archetype>.exr` will
  hold, because both come from `bake_frames`. See `_on_frame` below.
- **A change-look-change loop measured in seconds.** Edit `art/units/`, press
  Rebuild in the N-panel, see it. No process restart, no re-import, no engine.

## `bpy` the wheel has no GUI, and that is not a fixable thing

`just bootstrap-art` installs `bpy` from PyPI — Blender's Python module, with
the window manager and the interface compiled out. There is no flag that opens
a window on it. Seeing the GUI needs the real Blender APPLICATION, which is a
separate download; `blender-path.sh` is the one definition of where it is and
`just bootstrap-blender-gui` fetches one. The two must be the same version, for
the ordinary reason that a mesh built by one and baked by the other is only
accidentally the same mesh — `_version_note()` says so out loud rather than
leaving it to be discovered.

## The model lies on its back in Blender, and the fix is a viewing transform

`geom.py` authors in Y-up, to match Godot, and `bake.py` exports with
`export_yup=False` for a reason its own comment records at length. Blender is
Z-up, so the authored coordinates put a soldier flat on the floor.

This file rotates the OBJECT, never the mesh data. The vertices you select in
the viewport are the numbers that go into the glTF and the VAT; only the
container is turned. A version of this that rotated the geometry to make the
viewport tidy would be showing you a model that does not exist.

## What this is NOT the authority on

Appearance. The viewport material below approximates D-052's owner-colour mask
and the flat shading, and it is Blender's renderer, not Godot's — no VAT
sampling, no `world_look.gd` rig, no tonemap. `just gen-model-preview` and
`just test-client` remain the instruments that answer "is the picture right",
for the same reason `bench-render` rather than `test-client` answers "how
fast". This answers "is the SHAPE right", which nothing else does well.
"""

from __future__ import annotations

import argparse
import importlib
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

import bpy  # noqa: E402


# Reloaded in dependency order by the Rebuild operator, so that editing a
# generator and pressing a button shows the change. Order matters: `soldier`
# holds a reference to `geom.box`, so reloading `geom` after `soldier` would
# leave the old function bound and the edit invisible — which looks exactly
# like the edit not having been made.
RELOAD_ORDER = (
    "art.lib.geom",
    "art.lib.clips",
    "art.lib.soldier",
    "art.lib.bake",
    "art.units",
    "art.buildings",
    "art.scatter.props",
)

# The player colour the mask (D-052) is previewed against. Deliberately the
# same value `art/preview.py` uses, so the two instruments do not disagree
# about what a 0.85 tunic mask looks like.
OWNER_COLOUR = (0.20, 0.45, 0.85, 1.0)

VIEW_ROOT = "edotmw_view_root"


# --- the generators, addressed as one roster ----------------------------


def _modules() -> dict:
    """Import (or re-import) the generators and hand back what is needed.

    Returns module objects rather than the functions inside them: a reference
    captured before a reload points at the old code, which is the failure the
    RELOAD_ORDER comment above describes.
    """
    import art.buildings
    import art.lib.bake
    import art.lib.clips
    import art.lib.soldier
    import art.scatter.props
    import art.units
    return {
        "bake": art.lib.bake,
        "clips": art.lib.clips,
        "soldier": art.lib.soldier,
        "units": art.units,
        "buildings": art.buildings,
        "props": art.scatter.props,
    }


def reload_generators() -> dict:
    for name in RELOAD_ORDER:
        module = sys.modules.get(name)
        if module is not None:
            importlib.reload(module)
    return _modules()


def targets() -> list[tuple[str, str]]:
    """Every buildable thing, as (id, kind), sorted the way the build sorts.

    Sorted per kind rather than globally, because `art/build.py` iterates each
    roster separately and a reader comparing this list with a build log should
    not have to reconcile two orders.
    """
    m = _modules()
    out: list[tuple[str, str]] = []
    out += [(name, "unit") for name in sorted(m["units"].ROSTER)]
    out += [(name, "building") for name in sorted(m["buildings"].ROSTER)]
    out += [(name, "prop") for name in sorted(m["props"].ROSTER)]
    return out


def build_model(target: str, kind: str):
    """Build one target through its own generator. No geometry lives here."""
    m = _modules()
    if kind == "unit":
        return m["soldier"].build(target, m["units"].ROSTER[target])
    if kind == "building":
        return m["buildings"].build(target, m["buildings"].ROSTER[target])
    if kind == "prop":
        model = m["props"].build(target)
        # Props are settled onto y=0 by the build before anything measures
        # them, so a preview that skipped it would show every prop floating or
        # buried by however much its author happened to be out.
        m["props"].settle(model)
        return model
    raise ValueError(f"unknown kind {kind!r}")


# --- scene construction -------------------------------------------------


def _clear() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh, do_unlink=True)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material, do_unlink=True)


def _preview_material() -> bpy.types.Material:
    """A viewport material that shows what the owner-colour mask does.

    The mask lives in COLOR_0's ALPHA (D-081), so this mixes the part's own rgb
    toward `OWNER_COLOUR` by that alpha — the same arithmetic the shipping
    shader does and the same `art/preview.py` does. Without it every mask value
    previews identically and the one thing vertex colour is carrying for
    gameplay is invisible.
    """
    material = bpy.data.materials.new("edotmw_preview")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    attribute = nodes.new("ShaderNodeAttribute")
    owner = nodes.new("ShaderNodeRGB")
    mix = nodes.new("ShaderNodeMix")

    attribute.attribute_name = "COLOR_0"
    owner.outputs[0].default_value = OWNER_COLOUR
    mix.data_type = "RGBA"
    bsdf.inputs["Roughness"].default_value = 0.78
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25

    links.new(attribute.outputs["Color"], mix.inputs[6])   # A
    links.new(owner.outputs["Color"], mix.inputs[7])       # B
    links.new(attribute.outputs["Alpha"], mix.inputs[0])   # Factor
    links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    for node, x, y in ((out, 400, 0), (bsdf, 180, 0), (mix, -60, 0),
                       (attribute, -320, 60), (owner, -320, -160)):
        node.location = (x, y)
    return material


def _mesh_object(model, flat: dict, material) -> bpy.types.Object:
    """One Blender object from the SAME flattened arrays the bake writes.

    `flatten` splits a vertex per triangle corner and its ORDER is the contract
    between the mesh and the VAT (see `bake.py`). Rebuilding that here from
    `model.parts` would be a second implementation of the contract, free to
    drift, and the drift would show as a model that previews correctly and
    animates wrong.
    """
    mesh = bpy.data.meshes.new(model.name)
    mesh.from_pydata([tuple(v) for v in flat["positions"]], [], flat["triangles"])
    mesh.update()

    layer = mesh.color_attributes.new(name="COLOR_0", type="FLOAT_COLOR",
                                      domain="CORNER")
    for i, loop in enumerate(mesh.loops):
        layer.data[i].color = flat["colours"][loop.vertex_index]

    mesh.shade_flat()
    obj = bpy.data.objects.new(model.name, mesh)
    obj.data.materials.append(material)
    bpy.context.collection.objects.link(obj)
    return obj


def _view_root() -> bpy.types.Object:
    """The Y-up-to-Z-up viewing transform, and the only lie in the scene.

    See the module docstring: the mesh keeps its authored coordinates so that
    what you inspect is what bakes, and the container is turned instead.
    """
    root = bpy.data.objects.new(VIEW_ROOT, None)
    root.rotation_euler = (1.5707963267948966, 0.0, 0.0)
    root.empty_display_size = 0.35
    bpy.context.collection.objects.link(root)
    return root


def _light_and_camera(span: float) -> None:
    """A sun and a camera at roughly the angle the game is played at.

    Deliberately NOT a port of `world_look.gd`. That rig is defined in Godot
    terms — a sky material, sky-sourced ambient, an ACES tonemap — and a
    hand-copy of it here would be a fourth copy of the numbers `world_look.gd`
    exists to be the single definition of (D-086), drifting quietly in a file
    no Godot test can scan. The docstring says what this view is and is not
    the authority on; `just gen-model-preview` renders the real rig.
    """
    sun_data = bpy.data.lights.new("key", type="SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("key", sun_data)
    sun.rotation_euler = (0.96, 0.0, 0.79)
    bpy.context.collection.objects.link(sun)

    fill_data = bpy.data.lights.new("fill", type="SUN")
    fill_data.energy = 1.0
    fill_data.color = (0.72, 0.80, 0.95)
    fill = bpy.data.objects.new("fill", fill_data)
    fill.rotation_euler = (1.15, 0.0, -2.30)
    bpy.context.collection.objects.link(fill)

    camera_data = bpy.data.cameras.new("camera")
    camera_data.lens = 55.0
    camera = bpy.data.objects.new("camera", camera_data)
    distance = max(span * 1.6, 3.0)
    camera.location = (distance * 0.72, -distance, distance * 0.62)
    camera.rotation_euler = (1.02, 0.0, 0.62)
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera

    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background is not None:
        background.inputs[0].default_value = (0.16, 0.17, 0.20, 1.0)
        background.inputs[1].default_value = 0.6
    bpy.context.scene.world = world


# --- animation: the timeline is the VAT ---------------------------------


_FRAMES: dict[str, list] = {}


def _on_frame(scene) -> None:
    """Show the vertex positions VAT row `frame` holds.

    Written straight onto the mesh rather than through shape keys on purpose:
    the VAT is sampled with NEAREST filtering (`bake.py`), so a shape key's
    interpolation between frames would show the owner a smoothness the game
    does not have. The scrub is a row browser, not a playback.
    """
    for name, frames in _FRAMES.items():
        obj = bpy.data.objects.get(name)
        if obj is None or not frames:
            continue
        positions = frames[scene.frame_current % len(frames)]
        flat: list[float] = []
        for p in positions:
            flat.extend((p[0], p[1], p[2]))
        obj.data.vertices.foreach_set("co", flat)
        obj.data.update()


def _attach() -> None:
    if _on_frame not in bpy.app.handlers.frame_change_post:
        bpy.app.handlers.frame_change_post.append(_on_frame)


def detach() -> None:
    """Take the frame handler back off, and it is NOT optional to call this.

    A `frame_change_post` handler left registered makes the `bpy` WHEEL hang
    forever at interpreter shutdown — measured here at 4.5.12: the same script
    exits in 1 s with no handler and never exits with one, printing "Not freed
    memory blocks" and then spinning in Blender's leak detector. The scene had
    already built correctly and every line of output had already printed, so
    the symptom is a script that does its whole job and then refuses to end,
    which reads exactly like a slow build.

    The real Blender APPLICATION does not do this — it unregisters handlers as
    part of a normal quit — so this is a hazard of the headless path only, and
    therefore of `--check` and of anything that ever tests this file.
    """
    if _on_frame in bpy.app.handlers.frame_change_post:
        bpy.app.handlers.frame_change_post.remove(_on_frame)


def clip_at(frame: int) -> tuple[str, float]:
    """Which clip and phase a timeline frame is, for the panel readout."""
    m = _modules()
    per = m["clips"].FRAMES_PER_CLIP
    order = m["clips"].CLIP_ORDER
    total = per * len(order)
    f = frame % total
    return order[f // per], (f % per) / per


# --- the scene ----------------------------------------------------------


def build_scene(selection: str = "militia") -> dict:
    """Build `selection` into the current Blender scene.

    `selection` is a target id, or one of the group names below. Returns a
    summary the panel and the `--check` mode both read, so that what a test
    asserts is what the owner is looking at.
    """
    _clear()
    _FRAMES.clear()

    every = targets()
    kinds = {"units": "unit", "buildings": "building", "props": "prop"}
    if selection == "all":
        chosen = every
    elif selection in kinds:
        chosen = [t for t in every if t[1] == kinds[selection]]
    else:
        chosen = [t for t in every if t[0] == selection]
    if not chosen:
        raise SystemExit(
            f"unknown target {selection!r}. Try one of: all, units, buildings, "
            f"props, or {', '.join(t[0] for t in every)}")

    m = _modules()
    material = _preview_material()
    root = _view_root()

    # Laid out in a row along the authored X axis, widest-first spacing so a
    # cavalry model does not stand inside the militia beside it.
    columns = max(1, int(len(chosen) ** 0.5 + 0.999))
    pitch = 2.4
    built: list[dict] = []
    for index, (name, kind) in enumerate(chosen):
        model = build_model(name, kind)
        flat = m["bake"].flatten(model)
        obj = _mesh_object(model, flat, material)
        obj.parent = root
        col, row = index % columns, index // columns
        # Authored space is Y-up, so the ground plane is XZ and "beside" is X.
        obj.location = ((col - (columns - 1) / 2.0) * pitch, 0.0, -row * pitch)

        if kind == "unit":
            positions, _normals = m["bake"].bake_frames(model, flat)
            _FRAMES[obj.name] = positions

        built.append({
            "name": name,
            "kind": kind,
            "object": obj.name,
            "triangles": model.triangle_count(),
            "vertices": len(flat["positions"]),
        })

    _light_and_camera(pitch * columns)

    scene = bpy.context.scene
    frames = m["clips"].FRAMES_PER_CLIP * len(m["clips"].CLIP_ORDER)
    scene.frame_start = 0
    scene.frame_end = frames - 1
    _attach()

    # `animated` is the count of models that actually carry frames, not the
    # frame RANGE. A town hall does not walk (D-082 bakes no VAT for one), and
    # reporting "64 animation frames" for a building would be a summary that
    # describes the timeline rather than the thing on it.
    return {"selection": selection, "built": built,
            "triangles": sum(b["triangles"] for b in built),
            "animated": len(_FRAMES), "frames": frames}


def _assert_the_timeline_moves() -> None:
    """Scrub to a mid-walk frame and check the mesh actually moved.

    A check that only proved "a scene was built" is the vacuous pass D-022's
    audit block was written about: the handler could be unregistered, the frame
    table empty, or `_on_frame` writing to a stale object, and every count
    above would still print. So this drives the timeline the way a person
    would and compares coordinates.

    The frame is chosen mid-`walk` rather than at 0 because `idle` frame 0 is
    the rest pose by construction — comparing against it would assert nothing.
    """
    if not _FRAMES:
        return
    m = _modules()
    per = m["clips"].FRAMES_PER_CLIP
    walk = m["clips"].CLIP_ORDER.index("walk") * per + per // 4

    name = sorted(_FRAMES)[0]
    obj = bpy.data.objects[name]
    scene = bpy.context.scene

    scene.frame_set(0)
    rest = [tuple(v.co) for v in obj.data.vertices]
    scene.frame_set(walk)
    posed = [tuple(v.co) for v in obj.data.vertices]
    moved = sum(1 for a, b in zip(rest, posed)
                if abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) > 1e-5)
    if moved == 0:
        raise SystemExit(
            f"blender-gui: scrubbing to frame {walk} (mid-walk) moved no "
            f"vertex of {name}. The timeline is not showing the VAT.")
    print(f"blender-gui: frame {walk} moves {moved}/{len(rest)} vertices "
          f"of {name} — the timeline is live")
    scene.frame_set(0)


def _version_note() -> str:
    """Whether the app you are looking at matches the wheel that bakes.

    A mismatch is not cosmetic. The exporter, the mesh API and the glTF writer
    all move between Blender versions, so a model built in one and baked by the
    other is only accidentally the same model — and the difference would show
    up as a `generated/` diff nobody asked for.
    """
    pinned = "unknown"
    path = os.path.join(_ROOT, ".blender-version")
    if os.path.exists(path):
        with open(path) as handle:
            pinned = handle.read().strip()
    running = ".".join(str(n) for n in bpy.app.version)
    ok = running.startswith(".".join(pinned.split(".")[:2]))
    return (f"Blender {running} vs pinned {pinned}"
            + ("" if ok else "  — MISMATCH: bake with the pinned version"))


# --- the N-panel --------------------------------------------------------


def _target_items(self, context):
    items = [("all", "Everything", "Every unit, building and prop"),
             ("units", "All units", "Every soldier archetype"),
             ("buildings", "All buildings", "Every structure"),
             ("props", "All props", "Every ground-cover prop")]
    items += [(name, name, kind) for name, kind in targets()]
    return items


class EDOTMW_OT_rebuild(bpy.types.Operator):
    """Re-read art/ from disk and rebuild the scene"""

    bl_idname = "edotmw.rebuild"
    bl_label = "Reload generators & rebuild"

    def execute(self, context):
        reload_generators()
        summary = build_scene(context.scene.edotmw_target)
        self.report({"INFO"},
                    f"{len(summary['built'])} model(s), "
                    f"{summary['triangles']} tris")
        return {"FINISHED"}


class EDOTMW_OT_bake(bpy.types.Operator):
    """Run art/build.py — the real one — and write generated/"""

    bl_idname = "edotmw.bake"
    bl_label = "Bake through art/build.py"

    only: bpy.props.BoolProperty(name="This target only", default=True)  # noqa: F821

    def execute(self, context):
        # Imported here, not at module scope: `art.build` runs a build on
        # import of nothing, but it pulls in every roster, and this file is
        # meant to be cheap to load into a GUI that may never bake.
        import art.build
        importlib.reload(art.build)
        target = context.scene.edotmw_target
        single = self.only and target not in ("all", "units", "buildings", "props")
        argv = sys.argv
        try:
            sys.argv = ["build.py"] + ([f"--only={target}"] if single else [])
            art.build.main()
        except SystemExit as exc:                    # a budget failure, usually
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}
        finally:
            sys.argv = argv
        self.report({"INFO"}, "generated/ written — run `just _import` before Godot")
        return {"FINISHED"}


class EDOTMW_PT_panel(bpy.types.Panel):
    bl_label = "eDotMW assets"
    bl_idname = "EDOTMW_PT_panel"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "eDotMW"

    def draw(self, context):
        layout = self.layout
        scene = context.scene
        layout.prop(scene, "edotmw_target", text="")
        layout.operator(EDOTMW_OT_rebuild.bl_idname, icon="FILE_REFRESH")

        # `panel`, not `box`: `UILayout.box()` is Blender's framed sub-layout
        # and has nothing to do with `geom.box()`, but this file is scanned
        # for the primitives it may not call (tests/test_blender_gui.gd) and
        # naming a local after one of them is a needless collision between a
        # rule and its enforcement.
        panel = layout.box()
        clip, phase = clip_at(scene.frame_current)
        panel.label(text=f"frame {scene.frame_current}: {clip} @ {phase:.2f}")
        panel.label(text="the timeline is the VAT — one frame, one row")

        total = sum(len(obj.data.polygons) for obj in bpy.data.objects
                    if obj.type == "MESH")
        row = panel.row()
        row.alert = total > 300 and len(_FRAMES) == 1
        row.label(text=f"{total} triangles in scene")

        layout.separator()
        layout.operator(EDOTMW_OT_bake.bl_idname, icon="EXPORT")
        layout.label(text=_version_note(), icon="INFO")


_CLASSES = (EDOTMW_OT_rebuild, EDOTMW_OT_bake, EDOTMW_PT_panel)


def register() -> None:
    for cls in _CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.edotmw_target = bpy.props.EnumProperty(
        name="Target", items=_target_items)


def unregister() -> None:
    for cls in reversed(_CLASSES):
        bpy.utils.unregister_class(cls)
    del bpy.types.Scene.edotmw_target


# --- entry point --------------------------------------------------------


def _argv() -> list[str]:
    """Arguments after `--`, which is how Blender hands a script its own.

    Without the split, Blender's own flags reach argparse and it exits on
    them — which under `--python` prints a traceback into a GUI nobody is
    reading and leaves an empty scene that looks like a build failure.
    """
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", default="militia")
    parser.add_argument("--check", action="store_true",
                        help="build the scene and exit; no GUI needed, which "
                             "is what lets this file be tested at all")
    args = parser.parse_args(_argv() if "--" in sys.argv else None)

    summary = build_scene(args.target)
    print(f"blender-gui: {_version_note()}")
    for entry in summary["built"]:
        print(f"  {entry['name']:20s} {entry['kind']:9s} "
              f"{entry['triangles']:4d} tris  {entry['vertices']:5d} verts")
    animation = (f"{summary['animated']} animated over {summary['frames']} frames"
                 if summary["animated"] else "nothing animated (no VAT at this tier)")
    print(f"blender-gui: {len(summary['built'])} model(s), "
          f"{summary['triangles']} tris, {animation}")

    if args.check:
        _assert_the_timeline_moves()
        # See `detach`. Without this the process never exits, having already
        # printed everything above.
        detach()
        return

    register()
    bpy.context.scene.frame_set(0)
    # Material preview, so the owner-colour mask is visible without anyone
    # having to find the shading dropdown. Guarded because `--check` and the
    # bpy wheel have no screen to walk.
    screen = getattr(bpy.context, "screen", None)
    for area in getattr(screen, "areas", []) or []:
        if area.type == "VIEW_3D":
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.type = "MATERIAL"


if __name__ == "__main__":
    main()
