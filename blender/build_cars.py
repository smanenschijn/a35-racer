"""
Build cars from designs.py.

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python blender/build_cars.py -- rx7 golv
  (no names = build all)

Per car:
  assets/blender/<name>.blend   parts as separate objects (editable)
  public/models/<name>.glb      joined model for the game
  assets/renders/<name>_*.png   preview renders
"""

import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import carbuilder  # noqa: E402
import carkit as ck  # noqa: E402
from designs import DESIGNS  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..'))


def build_one(name, renders=True):
    d = DESIGNS[name]
    root, car = carbuilder.build(d)
    for sub in ('public/models', 'assets/blender', 'assets/renders'):
        os.makedirs(os.path.join(ROOT, sub), exist_ok=True)
    objs = [root] + list(root.children_recursive)
    ck.export_glb(os.path.join(ROOT, f'public/models/{name}.glb'), objs)

    cam = ck.studio(target_height=0.6, cam_loc=(-4.4, -5.6, 1.7))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, f'assets/blender/{name}.blend'))
    if renders:
        scene = bpy.context.scene
        scene.render.resolution_x, scene.render.resolution_y = 1100, 640
        for label, loc in (('front', (-4.4, -5.8, 1.7)), ('rear', (4.2, 5.8, 1.9)), ('side', (-8.0, 0.2, 1.0))):
            cam.location = loc
            cam.rotation_euler = (Vector((0, 0, 0.6)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            scene.render.filepath = os.path.join(ROOT, f'assets/renders/{name}_{label}.png')
            bpy.ops.render.render(write_still=True)
    meshes = [o for o in objs if o.type == 'MESH']
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    print(f'BUILD_OK {name}: parts={len(meshes)} triangles={tris} length={car.L} '
          f'width={2 * max(v for _, v in d["width"]):.2f} wheel_r={car.wr}')


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    names = argv or list(DESIGNS)
    for n in names:
        build_one(n)


main()
