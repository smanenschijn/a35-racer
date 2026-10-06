"""
Build the landmarks in landmarks.py.

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python blender/build_landmarks.py -- veste
  (no names = build all)

Per landmark: assets/blender/lm_<name>.blend, public/models/lm_<name>.glb, assets/renders/lm_<name>.png
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import carkit as ck  # noqa: E402
from landmarks import BUILDERS  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..'))


def build_one(name):
    root = BUILDERS[name]()
    objs = [root] + list(root.children_recursive)
    meshes = [o for o in objs if o.type == 'MESH']
    ck.export_glb(os.path.join(ROOT, f'public/models/lm_{name}.glb'), objs)

    # Frame the whole site for the preview.
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = (hi - lo).length
    centre = (lo + hi) / 2
    cam = ck.studio(target_height=centre.z, cam_loc=(centre.x - size * 0.55, centre.y - size * 0.85, centre.z + size * 0.32),
                    resolution=(1100, 640))
    cam.data.clip_end = 2000
    for o in bpy.data.objects:
        if o.name == 'Ground':
            o.scale = (12, 12, 1)
    cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.45, 0.32, 0.3, 1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, f'assets/blender/lm_{name}.blend'))
    bpy.context.scene.render.filepath = os.path.join(ROOT, f'assets/renders/lm_{name}.png')
    bpy.ops.render.render(write_still=True)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    print(f'BUILD_OK lm_{name}: parts={len(meshes)} triangles={tris} size={tuple(round(v) for v in (hi - lo))}')


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    for n in argv or list(BUILDERS):
        build_one(n)


main()
