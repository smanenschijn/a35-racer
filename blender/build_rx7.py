"""
Mazdo RX-Zeven: the player's car (fictional, inspired by a 90s Japanese sports coupe).

Run headless from the repo root:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python blender/build_rx7.py

Outputs:
  assets/blender/rx7.blend   every part as its own object (edit these by hand if you like)
  public/models/rx7.glb      the joined model the game loads (parts kept as named nodes)
  assets/renders/rx7_*.png   preview renders
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import carkit as ck  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
NAME = 'rx7'

# --- Dimensions (metres) ----------------------------------------------------
L = 4.30          # length
WHEEL_R = 0.31
WHEEL_W = 0.225
TRACK = 0.735     # wheel centre to car centre line
Y_FRONT_AXLE = -L / 2 + 0.88
Y_REAR_AXLE = Y_FRONT_AXLE + 2.42
ARCH_R = WHEEL_R + 0.065


def t_of(y):
    return (y + L / 2) / L


# --- Body shape curves (t: 0 = nose, 1 = tail) ------------------------------
WIDTH = ck.Curve([(0, 0.60), (0.03, 0.77), (0.08, 0.85), (0.20, 0.895), (0.35, 0.88), (0.5, 0.872),
                  (0.65, 0.885), (0.77, 0.897), (0.9, 0.872), (0.97, 0.83), (1.0, 0.78)])
TOP = ck.Curve([(0, 0.50), (0.04, 0.60), (0.10, 0.675), (0.20, 0.72), (0.30, 0.755), (0.37, 0.775),
                (0.45, 0.80), (0.70, 0.83), (0.80, 0.865), (0.90, 0.895), (0.96, 0.90), (1.0, 0.84)])
BOTTOM = ck.Curve([(0, 0.24), (0.05, 0.17), (0.9, 0.17), (1.0, 0.30)])

# Greenhouse (cabin) curves
G0, G1 = 0.36, 0.81
ROOF_H = ck.Curve([(G0, 0.0), (0.375, 0.08), (0.50, 0.40), (0.56, 0.42), (0.63, 0.405), (0.70, 0.31),
                   (0.79, 0.05), (G1, 0.0)])
ROOF_W = ck.Curve([(G0, 0.80), (0.42, 0.70), (0.52, 0.60), (0.62, 0.60), (0.72, 0.64), (G1, 0.76)])

S = 64            # points around a body section
G = 24            # points across the greenhouse arch


def bottom(t):
    y = -L / 2 + t * L
    z = BOTTOM(t)
    for yc in (Y_FRONT_AXLE, Y_REAR_AXLE):
        dy = y - yc
        if abs(dy) < ARCH_R:
            z = max(z, WHEEL_R + math.sqrt(ARCH_R ** 2 - dy ** 2))
    return z


def body_section(t, j):
    y = -L / 2 + t * L
    w = WIDTH(t)
    zt, zb = TOP(t), bottom(t)
    zc, h = (zt + zb) / 2, (zt - zb) / 2
    th = -math.pi / 2 + 2 * math.pi * j / S
    c, s = math.cos(th), math.sin(th)
    n = 4.2 if s > 0 else 6.0            # firm shoulders, flat sides
    x = math.copysign(abs(c) ** (2 / n), c) * w
    z = zc + math.copysign(abs(s) ** (2 / n), s) * h
    if s > 0:
        x *= 1 - 0.08 * s ** 4           # tumblehome near the top only
    return (x, y, z)


HOOD = 8  # half-width of the hood/deck band in section steps


def body_part(tm, j, i):
    if j < 0:  # end caps
        return 'nose' if tm < 0.5 else 'tail'
    left = j < S // 2
    side = 'L' if left else 'R'
    top_band = S // 2 - HOOD <= j < S // 2 + HOOD
    under = j < 5 or j >= S - 5
    if under:
        return 'underbody'
    if tm < 0.075:
        return 'nose'
    if tm > 0.935:
        return 'tail'
    if tm < 0.37:
        return 'hood' if top_band else f'fender_{side}'
    if tm < 0.66:
        return 'tub' if top_band else f'door_{side}'
    if top_band:
        return 'deck_lid' if tm > 0.80 else 'tub'
    return f'quarter_{side}'


def greenhouse_section(t, k):
    y = -L / 2 + t * L
    base = TOP(t) - 0.06
    wb = WIDTH(t) * 0.84
    wr = ROOF_W(t)
    hrel = ROOF_H(t) + 0.06 if G0 < t < G1 else 0.0
    phi = math.pi * k / G
    u, c = math.sin(phi), math.cos(phi)
    x = math.copysign(abs(c) ** 0.6, c) * (wb + (wr - wb) * u)
    z = base + hrel * (u ** 0.35)
    return (x, y, z)


def greenhouse_part(tm, k, i):
    if k < 0 or k >= G:
        return None
    # Classify by height fraction (0 = window sill, 1 = roof centre) and by |x|.
    hf = math.sin(math.pi * (k + 0.5) / G) ** 0.35
    x = abs(greenhouse_section(tm, k + 0.5)[0])
    if hf < 0.06:
        return 'seal'
    if tm < 0.50:
        return 'glass' if hf >= 0.22 else 'roof'      # windscreen above the A-pillar base
    if tm < 0.66:
        return 'roof' if x < ROOF_W(tm) * 0.86 else 'glass'
    return 'glass' if x < ROOF_W(tm) * 0.75 and hf > 0.45 else 'roof'


def ring_positions():
    ts = {i / 110 for i in range(111)}
    ts |= {0.075, 0.37, 0.66, 0.80, 0.935}
    for yc in (Y_FRONT_AXLE, Y_REAR_AXLE):  # crisp wheel-arch edges
        for e in (-ARCH_R, ARCH_R):
            for d in (-0.004, 0.004):
                ts.add(t_of(yc + e + d))
        for k in range(1, 12):  # more rings around the arch curve
            ts.add(t_of(yc - ARCH_R + 2 * ARCH_R * k / 12))
    return sorted(t for t in ts if 0 <= t <= 1)


def build():
    ck.reset_scene()
    m = ck.standard_materials(paint=(0.62, 0.02, 0.02))
    col = ck.collection('RX7')
    root = bpy.data.objects.new('RX7', None)
    col.objects.link(root)
    parts = []

    # ---- Body panels (one loft, cut into panels) ----
    zone = {'nose': 'front', 'hood': 'front', 'fender_L': 'left', 'fender_R': 'right', 'door_L': 'left',
            'door_R': 'right', 'quarter_L': 'left', 'quarter_R': 'right', 'deck_lid': 'rear', 'tail': 'rear',
            'tub': 'top', 'underbody': 'bottom'}
    for name, (verts, faces) in ck.loft_parts(ring_positions(), S, body_section, body_part).items():
        mat = m['Trim'] if name == 'underbody' else m['Paint']
        o = ck.mesh_object(name, verts, faces, [mat], smooth=True, col=col,
                           props={'zone': zone[name], 'deform': 0 if name == 'underbody' else 1})
        parts.append(o)

    # ---- Cabin: windscreen, roof, side windows, rear bubble glass ----
    gts = sorted({G0 + (G1 - G0) * i / 60 for i in range(61)} | {0.50, 0.66})
    gmat = {'glass': m['Glass'], 'roof': m['Paint'], 'seal': m['Trim']}
    for name, (verts, faces) in ck.loft_parts(gts, G + 1, greenhouse_section, greenhouse_part,
                                              close_front=False, close_rear=False).items():
        parts.append(ck.mesh_object(f'cabin_{name}', verts, faces, [gmat[name]], smooth=True, col=col,
                                    props={'zone': 'top', 'deform': 1}))

    # ---- Pop-up headlights (raised: it's sunset) ----
    for side, x in (('L', 0.53), ('R', -0.53)):
        y = -L / 2 + 0.12 * L
        pod = ck.box(f'popup_{side}', (0.36, 0.2, 0.085), (x, y, 0.705), m['Paint'], col=col, bevel_width=0.02,
                     rotation=(math.radians(-9), 0, 0), props={'zone': 'front', 'detach': 1})
        lens = ck.box(f'popup_lens_{side}', (0.29, 0.012, 0.05), (x, y - 0.1, 0.712), m['HeadLight'], col=col,
                      bevel_width=0.004, rotation=(math.radians(-9), 0, 0), props={'zone': 'front', 'detach': 1})
        parts += [pod, lens]

    # ---- Nose details ----
    yn = -L / 2 - 0.004
    parts.append(ck.box('intake', (0.86, 0.03, 0.12), (0, yn, 0.40), m['Trim'], col=col, bevel_width=0.01,
                        props={'zone': 'front'}))
    for side, x in (('L', 1), ('R', -1)):
        parts.append(ck.box(f'lamp_{side}', (0.22, 0.03, 0.06), (x * 0.42, yn + 0.02, 0.49), m['HeadLight'], col=col,
                            bevel_width=0.01, props={'zone': 'front'}))
        parts.append(ck.box(f'indicator_front_{side}', (0.1, 0.03, 0.05), (x * 0.56, yn + 0.03, 0.40), m['Indicator'],
                            col=col, bevel_width=0.008, props={'zone': 'front'}))
    parts.append(ck.box('front_lip', (1.4, 0.16, 0.03), (0, -L / 2 + 0.07, 0.185), m['Trim'], col=col,
                        bevel_width=0.008, props={'zone': 'front', 'detach': 1}))
    parts.append(ck.plane('plate_front', (0.52, 0.115), (0, yn - 0.005, 0.29), m['Plate'], col=col,
                          props={'zone': 'front', 'detach': 1}))

    # ---- Tail details ----
    yt = L / 2 + 0.004
    parts.append(ck.box('tail_strip', (1.36, 0.025, 0.13), (0, yt, 0.71), m['Trim'], col=col, bevel_width=0.01,
                        props={'zone': 'rear'}))
    for side, x in (('L', 1), ('R', -1)):
        for k, xo in enumerate((0.26, 0.5)):
            lamp = ck.cylinder(f'taillight_{side}{k}', 0.06, 0.03, (x * xo, yt + 0.012, 0.71), m['BrakeLight'],
                               col=col, axis='Y', segments=20, props={'zone': 'rear'})
            lamp.scale = (1.5, 1, 1)
            parts.append(lamp)
        parts.append(ck.box(f'indicator_rear_{side}', (0.1, 0.03, 0.07), (x * 0.64, yt + 0.012, 0.71), m['Indicator'],
                            col=col, props={'zone': 'rear'}))
    parts.append(ck.box('diffuser', (1.2, 0.3, 0.06), (0, L / 2 - 0.12, 0.27), m['Trim'], col=col,
                        bevel_width=0.008, props={'zone': 'rear', 'detach': 1}))
    for k, x in enumerate((-0.38, -0.27)):
        parts.append(ck.cylinder(f'exhaust{k}', 0.045, 0.22, (x, L / 2 - 0.02, 0.28), m['Chrome'], col=col, axis='Y',
                                 segments=16, props={'zone': 'rear'}))
    parts.append(ck.plane('plate_rear', (0.52, 0.115), (0, yt + 0.006, 0.52), m['Plate'], col=col,
                          rotation=(0, 0, math.pi), props={'zone': 'rear', 'detach': 1}))

    # ---- Wing ----
    yw = L / 2 - 0.26
    parts.append(ck.box('spoiler', (1.46, 0.27, 0.035), (0, yw, 1.0), m['Paint'], col=col, bevel_width=0.012,
                        rotation=(math.radians(-5), 0, 0), props={'zone': 'rear', 'detach': 1}))
    for side, x in (('L', 0.55), ('R', -0.55)):
        parts.append(ck.box(f'spoiler_stand_{side}', (0.04, 0.12, 0.13), (x, yw + 0.02, 0.93), m['Trim'], col=col,
                            bevel_width=0.006, props={'zone': 'rear', 'detach': 1}))

    # ---- Sides: mirrors, skirts, handles, wheel-well liners ----
    for side, sx in (('L', 1), ('R', -1)):
        mirror = ck.ellipsoid(f'mirror_{side}', (0.06, 0.11, 0.055), (sx * 0.86, -L / 2 + 0.415 * L, 0.90), m['Paint'],
                              col=col, props={'zone': side == 'L' and 'left' or 'right', 'detach': 1})
        glass = ck.box(f'mirror_glass_{side}', (0.09, 0.012, 0.06), (sx * 0.875, -L / 2 + 0.415 * L - 0.105, 0.90),
                       m['Chrome'], col=col, props={'zone': side == 'L' and 'left' or 'right', 'detach': 1})
        stalk = ck.box(f'mirror_stalk_{side}', (0.08, 0.03, 0.02), (sx * 0.81, -L / 2 + 0.415 * L, 0.88), m['Trim'],
                       col=col, props={'zone': side == 'L' and 'left' or 'right', 'detach': 1})
        skirt_len = (Y_REAR_AXLE - Y_FRONT_AXLE) - 2 * ARCH_R - 0.05
        skirt = ck.box(f'skirt_{side}', (0.05, skirt_len, 0.07), (sx * 0.87, (Y_FRONT_AXLE + Y_REAR_AXLE) / 2, 0.205),
                       m['Trim'], col=col, bevel_width=0.01,
                       props={'zone': side == 'L' and 'left' or 'right', 'detach': 1})
        handle = ck.box(f'handle_{side}', (0.02, 0.13, 0.025), (sx * 0.872, -L / 2 + 0.6 * L, 0.76), m['Trim'],
                        col=col, bevel_width=0.006, props={'zone': side == 'L' and 'left' or 'right'})
        parts += [mirror, glass, stalk, skirt, handle]
        for axle, yc in (('F', Y_FRONT_AXLE), ('R', Y_REAR_AXLE)):
            parts.append(ck.box(f'well_{axle}{side}', (0.02, 2 * ARCH_R, 0.52), (sx * 0.47, yc, 0.44), m['Trim'],
                                col=col, props={'zone': 'bottom'}))

    # ---- Wheels: hub empties (steer) -> wheel (spins) + caliper (doesn't) ----
    base_wheel = ck.wheel('wheel_proto', WHEEL_R, WHEEL_W, m, col)
    hubs = []
    for axle, yc in (('F', Y_FRONT_AXLE), ('R', Y_REAR_AXLE)):
        for side, sx in (('L', 1), ('R', -1)):
            hub = bpy.data.objects.new(f'hub_{axle}{side}', None)
            hub.location = (sx * TRACK, yc, WHEEL_R)
            hub['steer'] = 1 if axle == 'F' else 0
            col.objects.link(hub)
            if sx > 0:
                w = base_wheel.copy()
                w.data = base_wheel.data.copy()
                w.name = f'wheel_{axle}{side}'
                col.objects.link(w)
            else:
                w = ck.mirror_x(base_wheel, f'wheel_{axle}{side}')
            w.location = (0, 0, 0)
            w.parent = hub
            w['spin'] = 1
            cal = ck.box(f'caliper_{axle}{side}', (0.05, 0.09, 0.12), (sx * -0.045, 0.1, 0.12), m['Caliper'], col=col,
                         bevel_width=0.01)
            cal.parent = hub
            hubs.append(hub)
    bpy.data.objects.remove(base_wheel)

    for o in parts + hubs:
        o.parent = root
    return root, m


def preview(path, cam_loc, target_h=0.55):
    ck.studio(target_height=target_h, cam_loc=cam_loc)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    root, _ = build()
    os.makedirs(os.path.join(ROOT, 'public/models'), exist_ok=True)
    os.makedirs(os.path.join(ROOT, 'assets/blender'), exist_ok=True)
    os.makedirs(os.path.join(ROOT, 'assets/renders'), exist_ok=True)

    car_objects = [root] + list(root.children_recursive)
    ck.export_glb(os.path.join(ROOT, f'public/models/{NAME}.glb'), car_objects)

    ck.studio(target_height=0.55, cam_loc=(-4.4, -5.6, 1.7))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, f'assets/blender/{NAME}.blend'))
    scene = bpy.context.scene
    cam = scene.camera
    from mathutils import Vector
    for label, loc in (('front', (-4.4, -5.6, 1.7)), ('rear', (4.2, 5.4, 1.9)), ('side', (-7.5, 0.2, 1.0))):
        cam.location = loc
        cam.rotation_euler = (Vector((0, 0, 0.55)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(ROOT, f'assets/renders/{NAME}_{label}.png')
        bpy.ops.render.render(write_still=True)

    tris = sum(len(o.data.polygons) for o in car_objects if o.type == 'MESH')
    print(f'BUILD_OK parts={len([o for o in car_objects if o.type == "MESH"])} polygons={tris}')


main()
