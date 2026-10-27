"""Shared helpers for the custom emote props (Popcorn, Bullseye): one small texture atlas per
set (flat colour tiles, each face mapped onto its tile, plus optional painted regions) so a
whole set is one material and every object one MeshPart, and the shapes the sets are built from.

Studs throughout (1 Blender metre = 1 stud; STUDIO_NOTES "Models from Blender").
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "abilities"))
import common  # noqa: E402

ROOT = common.ROOT


def out_dir(name):
    path = os.path.join(ROOT, "assets", "emotes", name)
    os.makedirs(os.path.join(path, "renders"), exist_ok=True)
    return path


class Atlas:
    """A grid of flat colour tiles. tiles: { name: ((col, row from the top), (r, g, b)) }."""

    def __init__(self, tiles, grid=4, tile=64):
        self.tiles = tiles
        self.grid = grid
        self.tile = tile

    def pixels(self):
        size = self.tile * self.grid
        rgba = np.ones((size, size, 4), dtype=np.float32)
        for (col, row), rgb in self.tiles.values():
            t = self.tile
            rgba[row * t:(row + 1) * t, col * t:(col + 1) * t, :3] = rgb
        return rgba

    def image(self, name, path, rgba=None):
        return common.image_from_array(name, self.pixels() if rgba is None else rgba, path)

    def uv(self, name):
        (col, row), _ = self.tiles[name]
        return ((col + 0.5) / self.grid, 1 - (row + 0.5) / self.grid)

    def paint(self, bm, face, name):
        uv = bm.loops.layers.uv.verify()
        u = self.uv(name)
        for loop in face.loops:
            loop[uv].uv = u

    def tube(self, bm, points, radius, tile, caps=True, sides=8):
        """A round tube along `points` (rings kept from twisting by carrying the last normal)."""
        pts = [Vector(p) for p in points]
        n = len(pts)
        rings = []
        normal = None
        for i, p in enumerate(pts):
            if i == 0:
                t = (pts[1] - pts[0]).normalized()
            elif i == n - 1:
                t = (pts[-1] - pts[-2]).normalized()
            else:
                t = ((pts[i] - pts[i - 1]).normalized() + (pts[i + 1] - pts[i]).normalized()).normalized()
            ref = normal if normal is not None else (Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0)))
            normal = (ref - t * ref.dot(t)).normalized()
            binormal = t.cross(normal)
            r = radius(i / (n - 1)) if callable(radius) else radius
            rings.append([bm.verts.new(p + (normal * math.cos(2 * math.pi * k / sides)
                                            + binormal * math.sin(2 * math.pi * k / sides)) * r)
                          for k in range(sides)])
        for a, b in zip(rings, rings[1:]):
            for k in range(sides):
                f = bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
                self.paint(bm, f, tile(a, b) if callable(tile) else tile)
        if caps:
            for ring, end in ((rings[0], pts[0]), (rings[-1], pts[-1])):
                centre = bm.verts.new(end)
                for k in range(sides):
                    f = bm.faces.new((ring[k], ring[(k + 1) % sides], centre))
                    self.paint(bm, f, tile(ring, ring) if callable(tile) else tile)

    def sphere(self, bm, centre, radius, tile, subdivisions=2):
        geom = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
        for v in geom["verts"]:
            v.co += Vector(centre)
        for f in {f for v in geom["verts"] for f in v.link_faces}:
            self.paint(bm, f, tile)

    def sheet(self, bm, grid, tile_of, thickness, rim="White"):
        """A two-sided surface from a grid of points (rows x cols): the top as given, and a copy
        pushed down by `thickness` along each point's normal with its faces turned over, so it
        shows from both sides (Roblox draws only a face's front). tile_of(row, col) names a
        face's tile."""
        rows, cols = len(grid), len(grid[0])

        def normal_at(r, c):
            dr = grid[min(r + 1, rows - 1)][c] - grid[max(r - 1, 0)][c]
            dc = grid[r][min(c + 1, cols - 1)] - grid[r][max(c - 1, 0)]
            return dc.cross(dr).normalized()

        top = [[bm.verts.new(grid[r][c]) for c in range(cols)] for r in range(rows)]
        under = [[bm.verts.new(grid[r][c] - normal_at(r, c) * thickness) for c in range(cols)]
                 for r in range(rows)]
        for r in range(rows - 1):
            for c in range(cols - 1):
                name = tile_of(r, c)
                f = bm.faces.new((top[r][c], top[r][c + 1], top[r + 1][c + 1], top[r + 1][c]))
                self.paint(bm, f, name)
                g = bm.faces.new((under[r + 1][c], under[r + 1][c + 1], under[r][c + 1], under[r][c]))
                self.paint(bm, g, name)
        # Close the rim so the two skins read as one thin cloth from the side.
        edges = ([(top[0][c], top[0][c + 1], under[0][c + 1], under[0][c]) for c in range(cols - 1)]
                 + [(top[-1][c + 1], top[-1][c], under[-1][c], under[-1][c + 1]) for c in range(cols - 1)]
                 + [(top[r + 1][0], top[r][0], under[r][0], under[r + 1][0]) for r in range(rows - 1)]
                 + [(top[r][-1], top[r + 1][-1], under[r + 1][-1], under[r][-1]) for r in range(rows - 1)])
        for quad in edges:
            self.paint(bm, bm.faces.new(quad), rim)


def new_object(name, bm, mat, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    me.materials.append(mat)
    return obj


def fillet(points, size=0.28, steps=4):
    """A polyline with each inner corner rounded by a short quadratic curve."""
    pts = [Vector(p) for p in points]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, p, c = pts[i - 1], pts[i], pts[i + 1]
        d1, d2 = (a - p), (c - p)
        f1 = min(size, d1.length * 0.45)
        f2 = min(size, d2.length * 0.45)
        q1, q2 = p + d1.normalized() * f1, p + d2.normalized() * f2
        for s in range(steps + 1):
            t = s / steps
            out.append(q1 * (1 - t) ** 2 + p * 2 * (1 - t) * t + q2 * t * t)
    out.append(pts[-1])
    return out


def resample(points, step):
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        seg = b - a
        count = max(1, int(math.ceil(seg.length / step)))
        for s in range(1, count + 1):
            out.append(a + seg * (s / count))
    return out


def preview_scene(sun_energy=4.0):
    """A floor, a sun and plain colour management for the preview renders."""
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    floor = bpy.context.object
    fmat = bpy.data.materials.new("Floor")
    fmat.use_nodes = True
    next(n for n in fmat.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.75, 0.6, 0.42, 1)
    floor.data.materials.append(fmat)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = sun_energy
    sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(-30))
    bpy.context.scene.collection.objects.link(sun)
    view = bpy.context.scene.view_settings
    names = [i.identifier for i in view.bl_rna.properties["view_transform"].enum_items]
    if "Standard" in names:
        view.view_transform = "Standard"
    return floor
