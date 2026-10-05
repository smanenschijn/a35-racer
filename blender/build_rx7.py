"""
Mazdo RX-Zeven: the player's car (fictional, inspired by a 90s Japanese sports coupe).
Angular body with sharp creases, panel gaps, detailed nose/tail, interior and detailed wheels.

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
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import carkit as ck  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
NAME = 'rx7'

# --- Dimensions (metres) ----------------------------------------------------
L = 4.30
WHEEL_R = 0.31
WHEEL_W = 0.225
TRACK = 0.735
Y_FRONT_AXLE = -L / 2 + 0.88
Y_REAR_AXLE = Y_FRONT_AXLE + 2.42
ARCH_R = WHEEL_R + 0.065


def t_of(y):
    return (y + L / 2) / L


def y_of(t):
    return -L / 2 + t * L


# --- Body curves (t: 0 = nose, 1 = tail) -------------------------------------
WIDTH = ck.Curve([(0, 0.62), (0.025, 0.78), (0.07, 0.855), (0.20, 0.895), (0.35, 0.885), (0.5, 0.878),
                  (0.65, 0.888), (0.77, 0.898), (0.9, 0.878), (0.975, 0.84), (1.0, 0.80)])
TOP = ck.Curve([(0, 0.47), (0.03, 0.585), (0.10, 0.665), (0.20, 0.715), (0.30, 0.75), (0.37, 0.772),
                (0.45, 0.80), (0.70, 0.83), (0.80, 0.865), (0.90, 0.895), (0.965, 0.90), (1.0, 0.85)])
BOTTOM = ck.Curve([(0, 0.24), (0.05, 0.17), (0.9, 0.17), (1.0, 0.29)])
SHOULDER = ck.Curve([(0, 0.40), (0.08, 0.57), (0.3, 0.645), (0.6, 0.685), (0.85, 0.755), (1.0, 0.74)])

G0, G1 = 0.36, 0.81
ROOF_H = ck.Curve([(G0, 0.0), (0.375, 0.07), (0.49, 0.40), (0.56, 0.425), (0.63, 0.41), (0.70, 0.31),
                   (0.79, 0.05), (G1, 0.0)])
ROOF_W = ck.Curve([(G0, 0.74), (0.42, 0.68), (0.50, 0.60), (0.62, 0.60), (0.72, 0.64), (G1, 0.72)])

HALF_STEPS = [7, 2, 4, 4, 3, 8]           # underside, sill chamfer, lower side, upper side, shoulder, top
A1 = HALF_STEPS[0]                        # index of the sill edge
A2 = A1 + HALF_STEPS[1]
A4 = A2 + HALF_STEPS[2] + HALF_STEPS[3]   # shoulder crease
A5 = A4 + HALF_STEPS[4]                   # edge of the top plane (hood / deck)
H = sum(HALF_STEPS) + 1                   # points in a half section
S = 2 * H - 2                             # points around a full section

GH_STEPS = [6, 2, 6]                      # greenhouse: side glass, roof edge, roof
GH_HALF = sum(GH_STEPS) + 1
G = 2 * GH_HALF - 2                       # segments across the greenhouse


def bottom(t):
    y = y_of(t)
    z = BOTTOM(t)
    for yc in (Y_FRONT_AXLE, Y_REAR_AXLE):
        dy = y - yc
        if abs(dy) < ARCH_R:
            z = max(z, WHEEL_R + math.sqrt(ARCH_R ** 2 - dy ** 2))
    return z


def half_profile(t):
    """Angular half section (x >= 0): flat underside, sill chamfer, slab side, shoulder crease, top."""
    w, zt, zb = WIDTH(t), TOP(t), bottom(t)
    g = max(0.02, zt - 0.012 - zb)
    zs = min(max(SHOULDER(t), zb + 0.6 * g), zb + 0.88 * g)
    zsill = min(zb + 0.07, zb + 0.3 * g)
    zmid = (zsill + zs) / 2
    corners = [(0, zb), (w - 0.09, zb), (w - 0.012, zsill), (w, zmid), (w - 0.014, zs), (w - 0.115, zt - 0.012),
               (0, zt)]
    return ck.densify(corners, HALF_STEPS)


def body_ring(t):
    half = half_profile(t)
    y = y_of(t)
    left = [(x, y, z) for x, z in half]
    right = [(-x, y, z) for x, z in reversed(half[1:-1])]
    return left + right


_ring_cache = {}


def body_section(t, j):
    if t not in _ring_cache:
        _ring_cache[t] = body_ring(t)
    return _ring_cache[t][j]


def body_part(tm, j, i):
    if j < 0:
        return 'nose' if tm < 0.5 else 'tail'
    side = 'L' if j < H - 1 else 'R'
    top_band = A5 <= j < S - A5
    if j < A1 or j >= S - A1:
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


def gh_half(t):
    zg = TOP(t) - 0.006
    wb = WIDTH(t) - 0.13
    wr = min(ROOF_W(t), wb)
    hrel = ROOF_H(t) if G0 < t < G1 else 0.0
    zr = zg + hrel
    edge = min(0.035, hrel * 0.3)
    return ck.densify([(wb, zg), (wr, zr - edge), (wr - 0.07 * min(1, hrel / 0.1), zr), (0, zr + 0.012 * min(1, hrel / 0.1))],
                      GH_STEPS)


def gh_section(t, k):
    half = gh_half(t)
    y = y_of(t)
    pts = [(x, y, z) for x, z in half] + [(-x, y, z) for x, z in reversed(half[:-1])]
    return pts[k]


def gh_part(tm, k, i):
    if k < 0 or k >= G:
        return None
    side_n, edge_n = GH_STEPS[0], GH_STEPS[1]
    kk = k if k < G // 2 else G - 1 - k        # mirror to the left half
    if kk == 0:
        return 'seal'
    band = 'side' if kk < side_n else 'edge' if kk < side_n + edge_n else 'roof'
    if tm < 0.49:
        return {'roof': 'glass', 'edge': 'pillar', 'side': 'glass' if tm > 0.42 else 'pillar'}[band]
    if tm < 0.66:
        return 'glass' if band == 'side' else 'roof'
    if band == 'roof':
        return 'glass' if tm < 0.785 else 'roof'
    if band == 'edge':
        return 'roof'
    return 'glass' if tm < 0.70 else 'roof'


def ring_positions():
    ts = {i / 120 for i in range(121)}
    ts |= {0.075, 0.37, 0.66, 0.80, 0.935}
    for d in (0.0035,):
        for t0 in (0.075, 0.37, 0.66, 0.80, 0.935):
            ts |= {t0 - d, t0 + d}
    for yc in (Y_FRONT_AXLE, Y_REAR_AXLE):
        for e in (-ARCH_R, ARCH_R):
            for d in (-0.004, 0.004):
                ts.add(t_of(yc + e + d))
        for k in range(1, 14):
            ts.add(t_of(yc - ARCH_R + 2 * ARCH_R * k / 14))
    return sorted(t for t in ts if 0 <= t <= 1)


# --- Panel gaps: thin dark strips laid on the body surface --------------------

def ring_normal(ring, j):
    a, b = Vector(ring[(j - 1) % len(ring)]), Vector(ring[(j + 1) % len(ring)])
    tan = b - a
    n = Vector((tan.z, 0, -tan.x))
    if n.length < 1e-6:
        return Vector((0, 0, 1))
    n.normalize()
    p = Vector(ring[j])
    # outward = away from the section centre line
    if n.dot(Vector((p.x, 0, p.z - 0.5))) < 0:
        n = -n
    return n


def gap_across(name, t0, j_ranges, mat, col, width=0.006, lift=0.0016):
    """A seam running around the body at position t0, over the given ring index ranges."""
    dt = width / 2 / L
    r0, r1, rc = body_ring(t0 - dt), body_ring(t0 + dt), body_ring(t0)
    verts, faces = [], []
    for ja, jb in j_ranges:
        base = len(verts)
        for j in range(ja, jb + 1):
            n = ring_normal(rc, j % S)
            verts.append(Vector(r0[j % S]) + n * lift)
            verts.append(Vector(r1[j % S]) + n * lift)
        for k in range(jb - ja):
            a = base + 2 * k
            faces.append((a, a + 2, a + 3, a + 1))
    return ck.mesh_object(name, verts, faces, [mat], col=col)


def gap_along(name, j, t_a, t_b, mat, col, width=0.006, lift=0.0016, steps=30):
    """A seam running lengthwise along ring index j between t_a and t_b."""
    verts, faces = [], []
    for k in range(steps + 1):
        t = t_a + (t_b - t_a) * k / steps
        ring = body_ring(t)
        p = Vector(ring[j])
        tan = (Vector(ring[(j + 1) % S]) - Vector(ring[(j - 1) % S])).normalized()
        n = ring_normal(ring, j)
        verts.append(p + tan * width / 2 + n * lift)
        verts.append(p - tan * width / 2 + n * lift)
    for k in range(steps):
        a = 2 * k
        faces.append((a, a + 1, a + 3, a + 2))
    return ck.mesh_object(name, verts, faces, [mat], col=col)


def surface_z(t, x):
    """Height of the body top at (t, x) (for placing things on the hood/deck)."""
    half = half_profile(t)
    for (x0, z0), (x1, z1) in zip(half, half[1:]):
        lo, hi = min(x0, x1), max(x0, x1)
        if lo <= abs(x) <= hi and abs(x1 - x0) > 1e-6 and z1 >= z0 and z0 > bottom(t) + 0.01:
            f = (abs(x) - x0) / (x1 - x0)
            return z0 + (z1 - z0) * f
    return TOP(t)


# --- Build -------------------------------------------------------------------

def build():
    ck.reset_scene()
    m = ck.standard_materials(paint=(0.62, 0.02, 0.02))
    m['Interior'] = ck.material('Interior', (0.035, 0.035, 0.04), roughness=0.85)
    m['Seat'] = ck.material('Seat', (0.25, 0.02, 0.02), roughness=0.9)
    m['Reverse'] = ck.material('Reverse', (0.9, 0.9, 0.9), roughness=0.1, emission=(1, 1, 1), strength=0.3)
    ck.set_transparent(m['Glass'], 0.72)
    col = ck.collection('RX7')
    root = bpy.data.objects.new('RX7', None)
    col.objects.link(root)
    parts = []

    def add(o):
        parts.append(o)
        return o

    def side_zone(sx):
        return 'left' if sx > 0 else 'right'

    # ---- Body panels: one angular loft, cut into panels, creases marked sharp ----
    zone = {'nose': 'front', 'hood': 'front', 'fender_L': 'left', 'fender_R': 'right', 'door_L': 'left',
            'door_R': 'right', 'quarter_L': 'left', 'quarter_R': 'right', 'deck_lid': 'rear', 'tail': 'rear',
            'tub': 'top', 'underbody': 'bottom'}
    for name, (verts, faces) in ck.loft_parts(ring_positions(), S, body_section, body_part).items():
        mat = m['Trim'] if name == 'underbody' else m['Paint']
        o = ck.mesh_object(name, verts, faces, [mat], smooth=True, col=col,
                           props={'zone': zone[name], 'deform': 0 if name == 'underbody' else 1})
        add(ck.mark_sharp(o, 28))

    # ---- Cabin ----
    gts = sorted({G0 + (G1 - G0) * i / 70 for i in range(71)} | {0.42, 0.49, 0.66, 0.70, 0.785})
    gmat = {'glass': m['Glass'], 'roof': m['Paint'], 'seal': m['Trim'], 'pillar': m['Trim']}
    for name, (verts, faces) in ck.loft_parts(gts, G + 1, gh_section, gh_part, close_front=False,
                                              close_rear=False).items():
        o = ck.mesh_object(f'cabin_{name}', verts, faces, [gmat[name]], smooth=True, col=col,
                           props={'zone': 'top', 'deform': 1})
        add(ck.mark_sharp(o, 30))

    # ---- Panel gaps ----
    side_l = (A1 + 1, A5)                  # sill edge .. top edge, left side
    side_r = (S - A5, S - A1 - 1)          # same on the right
    top = (A5, S - A5)
    gap = m['Trim']
    add(gap_across('gap_nose', 0.075, [(A1 + 1, S - A1 - 1)], gap, col))
    add(gap_across('gap_door_front', 0.37, [side_l, side_r], gap, col))
    add(gap_across('gap_door_rear', 0.66, [side_l, side_r], gap, col))
    add(gap_across('gap_deck', 0.80, [top], gap, col))
    add(gap_across('gap_tail', 0.935, [(A1 + 1, S - A1 - 1)], gap, col))
    for j, s in ((A5, 'L'), (S - A5, 'R')):
        add(gap_along(f'gap_hood_{s}', j, 0.075, 0.37, gap, col))
        add(gap_along(f'gap_deck_{s}', j, 0.80, 0.935, gap, col))
    for g in [p for p in parts if p.name.startswith('gap_')]:
        g['zone'] = 'top'
        g['deform'] = 1

    # ---- Wheel-arch flares ----
    for axle, yc in (('F', Y_FRONT_AXLE), ('R', Y_REAR_AXLE)):
        w = WIDTH(t_of(yc))
        for sx, s in ((1, 'L'), (-1, 'R')):
            add(ck.arc_band(f'flare_{axle}{s}', (yc, WHEEL_R), ARCH_R - 0.004, 0.032, 0.0, math.pi,
                            sx * (w - 0.03), sx * (w + 0.014), m['Paint'], col=col,
                            props={'zone': side_zone(sx), 'deform': 1}))

    # ---- Nose ----
    yn = -L / 2 - 0.004
    add(ck.box('intake', (0.64, 0.04, 0.15), (0, yn + 0.01, 0.355), m['Trim'], col=col, bevel_width=0.012,
               props={'zone': 'front'}))
    for k, z in enumerate((0.33, 0.38)):
        add(ck.box(f'intake_slat{k}', (0.6, 0.02, 0.012), (0, yn - 0.012, z), m['Chrome'], col=col,
                   props={'zone': 'front'}))
    for sx, s in ((1, 'L'), (-1, 'R')):
        add(ck.box(f'duct_{s}', (0.19, 0.04, 0.10), (sx * 0.43, yn + 0.01, 0.33), m['Trim'], col=col,
                   bevel_width=0.01, props={'zone': 'front'}))
        add(ck.cylinder(f'foglamp_{s}', 0.034, 0.02, (sx * 0.43, yn - 0.012, 0.33), m['HeadLight'], col=col,
                        axis='Y', segments=20, props={'zone': 'front'}))
        add(ck.box(f'indicator_front_{s}', (0.12, 0.03, 0.035), (sx * 0.48, yn + 0.008, 0.43), m['Indicator'],
                   col=col, bevel_width=0.006, props={'zone': 'front'}))
    add(ck.extrude_yz('splitter', [(-L / 2 - 0.06, 0.165), (-L / 2 + 0.3, 0.165), (-L / 2 + 0.3, 0.185),
                                   (-L / 2 - 0.01, 0.2)], -0.8, 0.8, m['Trim'], col=col,
                      props={'zone': 'front', 'detach': 1}))
    add(ck.box('plate_frame_front', (0.56, 0.015, 0.14), (0, yn + 0.004, 0.245), m['Trim'], col=col,
               props={'zone': 'front', 'detach': 1}))
    add(ck.plane('plate_front', (0.52, 0.115), (0, yn - 0.006, 0.245), m['Plate'], col=col,
                 props={'zone': 'front', 'detach': 1}))

    # ---- Pop-up headlights (raised), two round lamps each ----
    for sx, s in ((1, 'L'), (-1, 'R')):
        t = 0.115
        x = sx * 0.5
        z = surface_z(t, 0.5) + 0.04
        y = y_of(t)
        tilt = (math.radians(-8), 0, 0)
        add(ck.box(f'popup_{s}', (0.36, 0.20, 0.085), (x, y, z), m['Paint'], col=col, bevel_width=0.008,
                   rotation=tilt, props={'zone': 'front', 'detach': 1}))
        add(ck.box(f'popup_face_{s}', (0.33, 0.012, 0.07), (x, y - 0.1, z + 0.006), m['Trim'], col=col,
                   rotation=tilt, props={'zone': 'front', 'detach': 1}))
        for k, dx in enumerate((-0.08, 0.08)):
            add(ck.cylinder(f'popup_ring_{s}{k}', 0.032, 0.008, (x + dx, y - 0.108, z + 0.007), m['Chrome'],
                            col=col, axis='Y', segments=20, props={'zone': 'front', 'detach': 1}))
            add(ck.cylinder(f'popup_lamp_{s}{k}', 0.026, 0.008, (x + dx, y - 0.113, z + 0.007), m['HeadLight'],
                            col=col, axis='Y', segments=20, props={'zone': 'front', 'detach': 1}))

    # ---- Hood vents & wipers ----
    for k in range(5):
        t = 0.24 + k * 0.012
        for sx in (1, -1):
            add(ck.box(f'vent_{"L" if sx > 0 else "R"}{k}', (0.24, 0.022, 0.012), (sx * 0.2, y_of(t),
                       surface_z(t, 0.2) + 0.004), m['Trim'], col=col, rotation=(math.radians(-6), 0, 0),
                       props={'zone': 'front'}))
    for k, x in enumerate((0.25, -0.2)):
        add(ck.box(f'wiper{k}', (0.5, 0.018, 0.012), (x, y_of(0.372), TOP(0.372) + 0.02), m['Trim'], col=col,
                   rotation=(math.radians(-25), 0, math.radians(6)), props={'zone': 'top'}))

    # ---- Sides: mirrors, skirts, handles, fuel cap, antenna, well liners ----
    for sx, s in ((1, 'L'), (-1, 'R')):
        zs = side_zone(sx)
        tm_ = 0.405
        ym, zm, wm = y_of(tm_), TOP(tm_), WIDTH(tm_)
        add(ck.box(f'mirror_{s}', (0.075, 0.14, 0.07), (sx * (wm + 0.02), ym, zm + 0.055), m['Paint'], col=col,
                   bevel_width=0.015, props={'zone': zs, 'detach': 1}))
        add(ck.box(f'mirror_glass_{s}', (0.06, 0.008, 0.05), (sx * (wm + 0.025), ym + 0.072, zm + 0.055),
                   m['Chrome'], col=col, props={'zone': zs, 'detach': 1}))
        add(ck.box(f'mirror_stalk_{s}', (0.16, 0.04, 0.025), (sx * (wm - 0.08), ym + 0.02, zm + 0.02), m['Trim'],
                   col=col, props={'zone': zs, 'detach': 1}))
        skirt_len = (Y_REAR_AXLE - Y_FRONT_AXLE) - 2 * ARCH_R - 0.08
        add(ck.box(f'skirt_{s}', (0.06, skirt_len, 0.075), (sx * 0.88, (Y_FRONT_AXLE + Y_REAR_AXLE) / 2, 0.2),
                   m['Trim'], col=col, bevel_width=0.008, props={'zone': zs, 'detach': 1}))
        add(ck.box(f'handle_{s}', (0.015, 0.14, 0.03), (sx * (WIDTH(0.6) - 0.002), y_of(0.6), 0.67), m['Trim'],
                   col=col, bevel_width=0.005, props={'zone': zs}))
        for axle, yc in (('F', Y_FRONT_AXLE), ('R', Y_REAR_AXLE)):
            add(ck.box(f'well_{axle}{s}', (0.02, 2 * ARCH_R, 0.52), (sx * 0.47, yc, 0.44), m['Trim'], col=col,
                       props={'zone': 'bottom'}))
    add(ck.cylinder('fuel_cap', 0.06, 0.012, (WIDTH(0.74) + 0.002, y_of(0.74), 0.70), m['Trim'], col=col,
                    axis='X', segments=20, props={'zone': 'left'}))
    ant = add(ck.cylinder('antenna', 0.003, 0.38, (-0.62, y_of(0.88), TOP(0.88) + 0.17), m['Trim'], col=col,
                          axis='Z', segments=6, props={'zone': 'rear', 'detach': 1}))
    ant.rotation_euler = (math.radians(18), 0, 0)

    # ---- Tail ----
    yt = L / 2 + 0.004
    add(ck.box('tail_garnish', (1.44, 0.025, 0.16), (0, yt, 0.69), m['Trim'], col=col, bevel_width=0.008,
               props={'zone': 'rear'}))
    for sx, s in ((1, 'L'), (-1, 'R')):
        for k, xo in enumerate((0.33, 0.58)):
            add(ck.cylinder(f'tail_ring_{s}{k}', 0.066, 0.01, (sx * xo, yt + 0.014, 0.69), m['Chrome'], col=col,
                            axis='Y', segments=24, props={'zone': 'rear'}))
            add(ck.cylinder(f'taillight_{s}{k}', 0.056, 0.012, (sx * xo, yt + 0.02, 0.69), m['BrakeLight'],
                            col=col, axis='Y', segments=24, props={'zone': 'rear'}))
        add(ck.cylinder(f'reverse_{s}', 0.03, 0.01, (sx * 0.16, yt + 0.016, 0.69), m['Reverse'], col=col,
                        axis='Y', segments=16, props={'zone': 'rear'}))
        add(ck.box(f'indicator_rear_{s}', (0.16, 0.012, 0.022), (sx * 0.46, yt + 0.016, 0.625), m['Indicator'],
                   col=col, props={'zone': 'rear'}))
    add(ck.box('badge', (0.16, 0.01, 0.03), (0, yt + 0.016, 0.69), m['Chrome'], col=col, props={'zone': 'rear'}))
    add(ck.box('plate_frame_rear', (0.56, 0.015, 0.14), (0, yt + 0.002, 0.5), m['Trim'], col=col,
               props={'zone': 'rear', 'detach': 1}))
    add(ck.plane('plate_rear', (0.52, 0.115), (0, yt + 0.012, 0.5), m['Plate'], col=col, rotation=(0, 0, math.pi),
                 props={'zone': 'rear', 'detach': 1}))
    add(ck.box('diffuser', (1.2, 0.34, 0.03), (0, L / 2 - 0.14, 0.215), m['Trim'], col=col,
               props={'zone': 'rear', 'detach': 1}))
    for k in range(4):
        add(ck.box(f'diffuser_fin{k}', (0.012, 0.32, 0.07), (-0.36 + k * 0.24, L / 2 - 0.14, 0.245), m['Trim'],
                   col=col, props={'zone': 'rear', 'detach': 1}))
    for k, x in enumerate((-0.47, -0.34)):
        add(ck.cylinder(f'exhaust{k}', 0.048, 0.2, (x, L / 2 - 0.02, 0.27), m['Chrome'], col=col, axis='Y',
                        segments=20, props={'zone': 'rear'}))
        add(ck.cylinder(f'exhaust_inner{k}', 0.036, 0.205, (x, L / 2 - 0.02, 0.27), m['Trim'], col=col,
                        axis='Y', segments=20, props={'zone': 'rear'}))

    # ---- Wing: aerofoil with end plates and a third brake light ----
    yw = L / 2 - 0.47
    zw = 1.0
    foil = [(0.0, 0.0), (0.03, 0.022), (0.10, 0.04), (0.20, 0.038), (0.32, 0.018), (0.33, 0.008), (0.20, 0.008),
            (0.10, 0.004), (0.03, -0.006)]
    add(ck.extrude_yz('spoiler', [(yw + y, zw + z) for y, z in foil], -0.72, 0.72, m['Paint'], col=col,
                      props={'zone': 'rear', 'detach': 1}))
    for sx, s in ((1, 'L'), (-1, 'R')):
        add(ck.box(f'spoiler_plate_{s}', (0.012, 0.3, 0.085), (sx * 0.725, yw + 0.17, zw + 0.012), m['Paint'],
                   col=col, bevel_width=0.004, props={'zone': 'rear', 'detach': 1}))
        add(ck.box(f'spoiler_stand_{s}', (0.03, 0.12, 0.11), (sx * 0.5, yw + 0.2, zw - 0.06), m['Trim'], col=col,
                   bevel_width=0.006, rotation=(math.radians(15), 0, 0), props={'zone': 'rear', 'detach': 1}))
    add(ck.box('brake_light_high', (0.36, 0.012, 0.018), (0, yw + 0.335, zw + 0.02), m['BrakeLight'], col=col,
               props={'zone': 'rear', 'detach': 1}))

    # ---- Interior (seen through the tinted glass); left-hand drive ----
    yi = y_of
    add(ck.box('dash', (1.42, 0.34, 0.16), (0, yi(0.43), 0.79), m['Interior'], col=col, bevel_width=0.02,
               rotation=(math.radians(-12), 0, 0)))
    add(ck.box('console', (0.22, 0.75, 0.2), (0, yi(0.53), 0.52), m['Interior'], col=col, bevel_width=0.02))
    add(ck.ellipsoid('gear_knob', (0.025, 0.025, 0.025), (0, yi(0.5), 0.67), m['Chrome'], col=col))
    sw = ck.torus_x('steering_wheel', 0.17, 0.018, (0.37, yi(0.465), 0.87), m['Interior'], col=col)
    sw.rotation_euler = (0, math.radians(25), math.pi / 2)  # axis towards the driver, tilted
    add(sw)
    add(ck.cylinder('steering_hub', 0.05, 0.05, (0.37, yi(0.465), 0.87), m['Interior'], col=col, axis='Y'))
    for sx, s in ((1, 'L'), (-1, 'R')):
        x = sx * 0.37
        add(ck.box(f'seat_base_{s}', (0.46, 0.5, 0.12), (x, yi(0.565), 0.42), m['Seat'], col=col, bevel_width=0.03))
        back = add(ck.box(f'seat_back_{s}', (0.46, 0.12, 0.6), (x, yi(0.625), 0.7), m['Seat'], col=col,
                          bevel_width=0.03, rotation=(math.radians(14), 0, 0)))
        add(ck.box(f'seat_bolster_{s}', (0.5, 0.1, 0.45), (x, yi(0.632), 0.68), m['Interior'], col=col,
                   bevel_width=0.03, rotation=(math.radians(14), 0, 0)))
        add(ck.box(f'headrest_{s}', (0.26, 0.1, 0.16), (x, yi(0.645), 1.05), m['Seat'], col=col, bevel_width=0.03,
                   rotation=(math.radians(14), 0, 0)))
        del back
    add(ck.box('parcel_shelf', (1.3, 0.5, 0.03), (0, yi(0.74), 0.84), m['Interior'], col=col))
    add(ck.box('cabin_floor', (1.5, 1.6, 0.04), (0, yi(0.56), 0.3), m['Interior'], col=col))
    for p in parts[-12:]:
        if 'zone' not in p.keys():
            p['zone'] = 'top'

    # ---- Wheels ----
    base_wheel = detailed_wheel('wheel_proto', m, col)
    hubs = []
    for axle, yc in (('F', Y_FRONT_AXLE), ('R', Y_REAR_AXLE)):
        for sx, s in ((1, 'L'), (-1, 'R')):
            hub = bpy.data.objects.new(f'hub_{axle}{s}', None)
            hub.location = (sx * TRACK, yc, WHEEL_R)
            hub['steer'] = 1 if axle == 'F' else 0
            col.objects.link(hub)
            if sx > 0:
                w = base_wheel.copy()
                w.data = base_wheel.data.copy()
                w.name = f'wheel_{axle}{s}'
                col.objects.link(w)
            else:
                w = ck.mirror_x(base_wheel, f'wheel_{axle}{s}')
            w.location = (0, 0, 0)
            w.parent = hub
            w['spin'] = 1
            cal = ck.box(f'caliper_{axle}{s}', (0.055, 0.13, 0.11), (sx * -0.05, 0.11, 0.1), m['Caliper'], col=col,
                         bevel_width=0.015, rotation=(math.radians(-40), 0, 0))
            cal.parent = hub
            hubs.append(hub)
    bpy.data.objects.remove(base_wheel)

    for o in parts + hubs:
        o.parent = root
    return root


def detailed_wheel(name, m, col):
    """Tyre with tread grooves, 10-spoke rim with lip, lug nuts, cap, drilled-look disc. Axis = X, face = +X."""
    r, w = WHEEL_R, WHEEL_W
    rim_r = r * 0.66
    tread = []
    for k in range(6):  # four grooves across the tread
        x0 = -w / 2 + 0.03 + k * (w - 0.06) / 5
        tread += [(r, x0), (r - 0.007, x0 + 0.004), (r - 0.007, x0 + 0.01), (r, x0 + 0.014)] if 0 < k < 5 else [(r, x0)]
    profile = [(rim_r, -w / 2 + 0.012), (r - 0.04, -w / 2), (r - 0.01, -w / 2 + 0.012)] + tread + \
              [(r - 0.01, w / 2 - 0.012), (r - 0.04, w / 2), (rim_r, w / 2 - 0.012)]
    parts = [ck.bm_object(name + '_tyre', ck.lathe(profile, 40), [m['Tyre']], col=col, smooth=True)]
    ck.mark_sharp(parts[0], 50)
    barrel = ck.lathe([(rim_r + 0.004, w / 2 - 0.01), (rim_r - 0.008, w / 2 - 0.02), (rim_r - 0.012, -w / 2 + 0.03),
                       (rim_r, -w / 2 + 0.012)], 40)
    parts.append(ck.bm_object(name + '_barrel', barrel, [m['Rim']], col=col, smooth=True))
    lip = ck.lathe([(rim_r - 0.012, w / 2 - 0.012), (rim_r + 0.006, w / 2 - 0.008), (rim_r + 0.006, w / 2 - 0.02)], 40)
    parts.append(ck.bm_object(name + '_lip', lip, [m['Chrome']], col=col, smooth=True))
    face_x = w / 2 - 0.04
    parts.append(ck.cylinder(name + '_hub', rim_r * 0.3, 0.05, (face_x - 0.012, 0, 0), m['Rim'], col=col,
                             segments=20))
    parts.append(ck.cylinder(name + '_cap', rim_r * 0.13, 0.02, (face_x + 0.016, 0, 0), m['Chrome'], col=col,
                             segments=16))
    for k in range(5):
        a = 2 * math.pi * (k + 0.5) / 5
        parts.append(ck.cylinder(name + f'_nut{k}', 0.011, 0.02, (face_x + 0.012, -math.sin(a) * rim_r * 0.2,
                                 math.cos(a) * rim_r * 0.2), m['Chrome'], col=col, segments=6))
    for k in range(10):  # five pairs of thin spokes
        a = 2 * math.pi * (k // 2) / 5 + (0.12 if k % 2 else -0.12)
        s = ck.box(name + f'_spoke{k}', (0.022, 0.026, rim_r * 0.74), (0, 0, 0), m['Rim'], col=col)
        s.rotation_euler = (a, 0, 0)
        s.location = (face_x - 0.008, -math.sin(a) * rim_r * 0.55, math.cos(a) * rim_r * 0.55)
        parts.append(s)
    parts.append(ck.cylinder(name + '_disc', rim_r * 0.84, 0.024, (-0.025, 0, 0), m['Chrome'], col=col, segments=32))
    parts.append(ck.cylinder(name + '_disc_hat', rim_r * 0.42, 0.05, (-0.005, 0, 0), m['Trim'], col=col, segments=20))
    bpy.context.view_layer.update()
    ck.apply_transforms(parts)
    return ck.join(parts, name)


def main():
    root = build()
    for d in ('public/models', 'assets/blender', 'assets/renders'):
        os.makedirs(os.path.join(ROOT, d), exist_ok=True)

    car_objects = [root] + list(root.children_recursive)
    ck.export_glb(os.path.join(ROOT, f'public/models/{NAME}.glb'), car_objects)

    cam = ck.studio(target_height=0.55, cam_loc=(-4.4, -5.6, 1.7))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, f'assets/blender/{NAME}.blend'))
    scene = bpy.context.scene
    for label, loc, target in (('front', (-4.4, -5.6, 1.7), 0.55), ('rear', (4.2, 5.4, 1.9), 0.55),
                               ('side', (-7.5, 0.2, 1.0), 0.55), ('detail', (-2.2, -3.2, 1.25), 0.55)):
        cam.location = loc
        cam.rotation_euler = (Vector((0, -0.6 if label == 'detail' else 0, target)) - Vector(loc)) \
            .to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(ROOT, f'assets/renders/{NAME}_{label}.png')
        bpy.ops.render.render(write_still=True)

    meshes = [o for o in car_objects if o.type == 'MESH']
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    print(f'BUILD_OK parts={len(meshes)} triangles={tris}')


main()
