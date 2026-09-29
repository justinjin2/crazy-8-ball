"""Shared helpers for the ability asset scripts (docs/prompts/ABILITIES_PROMPT.md section 6).

Every script in this folder rebuilds its assets from nothing, live through the Blender MCP
(exec(open(path).read()) with ROOT set) or headless:

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/abilities/<id>.py

Scale: 1 Blender metre = 1 Roblox stud (STUDIO_NOTES). Colours are baked into image textures
(plain Principled colours arrive in Roblox as grey Plastic). Keep materials few: a model
splits into one MeshPart per material.
"""

import math
import os

import bpy
import numpy as np

ROOT = os.environ.get("EIGHTBALL_ROOT") or os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
)
ASSETS = os.path.join(ROOT, "assets", "abilities")

# Roblox's table scale: a ball's drawn diameter in studs (Config.Balls.RadiusInches 1.125,
# Table.StudsPerInch 0.16, RenderScale 1.08).
BALL_STUDS = 2 * 1.125 * 0.16 * 1.08


def asset_dir(ult_id):
    path = os.path.join(ASSETS, ult_id)
    os.makedirs(os.path.join(path, "renders"), exist_ok=True)
    os.makedirs(os.path.join(path, "textures"), exist_ok=True)
    return path


def clear_scene():
    """An empty scene: every object, mesh, material, image and curve removed."""
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves,
                 bpy.data.cameras, bpy.data.lights, bpy.data.node_groups):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)


def image_from_array(name, rgba, path):
    """A Blender image from an (h, w, 4) float array in 0..1 (row 0 = the image's TOP), saved as
    PNG at `path` and packed so a .glb export embeds it."""
    h, w = rgba.shape[0], rgba.shape[1]
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    # Blender's pixel rows start at the bottom.
    img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


def image_material(name, img, emission=0.0, alpha=False, roughness=0.5, metallic=0.0):
    """A Principled material whose Base Colour (and alpha) is `img`."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    links = mat.node_tree.links
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    if emission > 0:
        links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def export_glb(path, objects):
    """Export only `objects` to a .glb with images embedded, Y up (Roblox's importer)."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_image_format="AUTO",
        export_materials="EXPORT",
    )


def triangles(objects):
    total = 0
    for obj in objects:
        if obj.type != "MESH":
            continue
        me = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        me.calc_loop_triangles()
        total += len(me.loop_triangles)
    return total


def look_at(obj, target):
    direction = (target - obj.location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_preview(path, size=512, target=(0, 0, 0), distance=3.0, elevation=35.0,
                   azimuth=35.0, background=(0.07, 0.08, 0.1, 1), transparent=False):
    """A quick Eevee render of the scene for a look at the asset (renders/ folder)."""
    from mathutils import Vector

    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    el, az = math.radians(elevation), math.radians(azimuth)
    tgt = Vector(target)
    cam.location = tgt + Vector((math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az),
                                 math.sin(el))) * distance
    look_at(cam, tgt)
    scene.camera = cam
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        try:
            scene.render.engine = "BLENDER_EEVEE"
        except TypeError:
            pass
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.film_transparent = transparent
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = next(n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = background
    bg.inputs["Strength"].default_value = 1.0
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
