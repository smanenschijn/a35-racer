"""
Generic car builder: turns a design (see designs.py) into a detailed, angular car made of
many named parts. One loft for the body (cut into panels), one for the cabin, plus lights,
bumpers, spoilers, extras, an interior and detailed wheels.

All conventions (axes, extras, material names) are described in carkit.py / README.md.
"""

import math

import bmesh
import bpy
from mathutils import Vector

import carkit as ck

HALF_STEPS = [7, 2, 4, 4, 3, 8]           # underside, sill chamfer, lower side, upper side, shoulder, top
A1 = HALF_STEPS[0]
A2 = A1 + HALF_STEPS[1]
A4 = A2 + HALF_STEPS[2] + HALF_STEPS[3]
A5 = A4 + HALF_STEPS[4]
H = sum(HALF_STEPS) + 1
S = 2 * H - 2

GH_STEPS = [6, 2, 6]
GH_HALF = sum(GH_STEPS) + 1
G = 2 * GH_HALF - 2


class Car:
    def __init__(self, d):
        self.d = d
        self.L = d['length']
        self.lod = d.get('lod', False)  # traffic: fewer rings and simpler wheels
        self.wr = d['wheel_r']
        self.ww = d['wheel_w']
        self.track = d['track']
        self.y_front_axle = -self.L / 2 + d['front_axle']
        self.y_rear_axle = self.y_front_axle + d['wheelbase']
        self.arch_r = self.wr + 0.065
        self.WIDTH = ck.Curve(d['width'])
        self.TOP = ck.Curve(d['top'])
        self.BOTTOM = ck.Curve(d['bottom'])
        self.SHOULDER = ck.Curve(d['shoulder'])
        self.g0, self.g1 = d['roof_h'][0][0], d['roof_h'][-1][0]
        self.ROOF_H = ck.Curve(d['roof_h'])
        self.ROOF_W = ck.Curve(d['roof_w'])
        sp = {'nose': 0.075, 'cowl': self.g0 + 0.01, 'door_r': 0.66, 'deck': 0.80, 'tail': 0.935}
        sp.update(d.get('splits', {}))
        self.sp = sp
        gl = {'ws_end': 0.49, 'roof_end': 0.66, 'rear_end': 0.785, 'side0': 0.42, 'side1': 0.70, 'pillars': [],
              'pillar_mat': 'Trim'}
        gl.update(d.get('glass', {}))
        self.gl = gl
        self._rings = {}

    # ---- geometry -------------------------------------------------------
    def y_of(self, t):
        return -self.L / 2 + t * self.L

    def t_of(self, y):
        return (y + self.L / 2) / self.L

    def bottom(self, t):
        y = self.y_of(t)
        z = self.BOTTOM(t)
        for yc in (self.y_front_axle, self.y_rear_axle):
            dy = y - yc
            if abs(dy) < self.arch_r:
                z = max(z, self.wr + math.sqrt(self.arch_r ** 2 - dy ** 2))
        return z

    def half_profile(self, t):
        w, zt, zb = self.WIDTH(t), self.TOP(t), self.bottom(t)
        g = max(0.02, zt - 0.012 - zb)
        zs = min(max(self.SHOULDER(t), zb + 0.6 * g), zb + 0.88 * g)
        zsill = min(zb + 0.07, zb + 0.3 * g)
        zmid = (zsill + zs) / 2
        inset = self.d.get('top_inset', 0.115)
        corners = [(0, zb), (w - 0.09, zb), (w - 0.012, zsill), (w, zmid), (w - 0.014, zs), (w - inset, zt - 0.012),
                   (0, zt)]
        return ck.densify(corners, HALF_STEPS)

    def ring(self, t):
        if t not in self._rings:
            half = self.half_profile(t)
            y = self.y_of(t)
            self._rings[t] = [(x, y, z) for x, z in half] + [(-x, y, z) for x, z in reversed(half[1:-1])]
        return self._rings[t]

    def body_section(self, t, j):
        return self.ring(t)[j]

    def body_part(self, tm, j, i):
        sp = self.sp
        if j < 0:
            return 'nose' if tm < 0.5 else 'tail'
        side = 'L' if j < H - 1 else 'R'
        top_band = A5 <= j < S - A5
        if j < A1 or j >= S - A1:
            return 'underbody'
        if tm < sp['nose']:
            return 'nose'
        if tm > sp['tail']:
            return 'tail'
        if tm < sp['cowl']:
            return 'hood' if top_band else f'fender_{side}'
        if tm < sp['door_r']:
            return 'tub' if top_band else f'door_{side}'
        if top_band:
            return 'deck_lid' if tm > sp['deck'] else 'tub'
        return f'quarter_{side}'

    def gh_half(self, t):
        zg = self.TOP(t) - 0.006
        wb = self.WIDTH(t) - self.d.get('gh_inset', 0.13)
        wr = min(self.ROOF_W(t), wb)
        hrel = self.ROOF_H(t) if self.g0 < t < self.g1 else 0.0
        zr = zg + hrel
        edge = min(0.035, hrel * 0.3)
        k = min(1, hrel / 0.1)
        return ck.densify([(wb, zg), (wr, zr - edge), (wr - 0.07 * k, zr), (0, zr + 0.012 * k)], GH_STEPS)

    def gh_section(self, t, k):
        half = self.gh_half(t)
        y = self.y_of(t)
        pts = [(x, y, z) for x, z in half] + [(-x, y, z) for x, z in reversed(half[:-1])]
        return pts[k]

    def gh_part(self, tm, k, i):
        if k < 0 or k >= G:
            return None
        gl = self.gl
        kk = k if k < G // 2 else G - 1 - k
        if kk == 0:
            return 'seal'
        band = 'side' if kk < GH_STEPS[0] else 'edge' if kk < GH_STEPS[0] + GH_STEPS[1] else 'roof'
        in_pillar = any(a <= tm < b for a, b in gl['pillars'])
        if tm < gl['ws_end']:
            if band == 'roof':
                return 'glass'
            if band == 'edge':
                return 'pillar'
            return 'glass' if tm > gl['side0'] else 'pillar'
        if band == 'side':
            if in_pillar:
                return 'pillar'
            return 'glass' if tm < gl['side1'] else 'roof'
        if band == 'edge' or tm < gl['roof_end']:
            return 'roof'
        return 'glass' if tm < gl['rear_end'] else 'roof'

    def ring_positions(self):
        n = 40 if self.lod else 120
        ts = {i / n for i in range(n + 1)}
        splits = [self.sp[k] for k in ('nose', 'cowl', 'door_r', 'deck', 'tail')]
        ts |= set(splits)
        for t0 in splits:
            ts |= {t0 - 0.0035, t0 + 0.0035}
        for yc in (self.y_front_axle, self.y_rear_axle):
            for e in (-self.arch_r, self.arch_r):
                for dd in (-0.004, 0.004):
                    ts.add(self.t_of(yc + e + dd))
            na = 7 if self.lod else 14
            for k in range(1, na):
                ts.add(self.t_of(yc - self.arch_r + 2 * self.arch_r * k / na))
        return sorted(t for t in ts if 0 <= t <= 1)

    def surface_z(self, t, x):
        half = self.half_profile(t)
        for (x0, z0), (x1, z1) in zip(half, half[1:]):
            lo, hi = min(x0, x1), max(x0, x1)
            if lo <= abs(x) <= hi and abs(x1 - x0) > 1e-6 and z1 >= z0 and z0 > self.bottom(t) + 0.01:
                return z0 + (z1 - z0) * (abs(x) - x0) / (x1 - x0)
        return self.TOP(t)

    def roof_z(self, t, x=0.0):
        half = self.gh_half(t)
        for (x0, z0), (x1, z1) in zip(half, half[1:]):
            lo, hi = min(x0, x1), max(x0, x1)
            if lo <= abs(x) <= hi and abs(x1 - x0) > 1e-6:
                return z0 + (z1 - z0) * (abs(x) - x0) / (x1 - x0)
        return half[-1][1]

    # ---- seams & strips -------------------------------------------------
    def ring_normal(self, ring, j):
        a, b = Vector(ring[(j - 1) % len(ring)]), Vector(ring[(j + 1) % len(ring)])
        tan = b - a
        n = Vector((tan.z, 0, -tan.x))
        if n.length < 1e-6:
            return Vector((0, 0, 1))
        n.normalize()
        p = Vector(ring[j])
        if n.dot(Vector((p.x, 0, p.z - 0.5))) < 0:
            n = -n
        return n

    def gap_across(self, name, t0, j_ranges, mat, col, width=0.006, lift=0.0016):
        dt = width / 2 / self.L
        r0, r1, rc = self.half_ring(t0 - dt), self.half_ring(t0 + dt), self.half_ring(t0)
        verts, faces = [], []
        for ja, jb in j_ranges:
            base = len(verts)
            for j in range(ja, jb + 1):
                n = self.ring_normal(rc, j % S)
                verts.append(Vector(r0[j % S]) + n * lift)
                verts.append(Vector(r1[j % S]) + n * lift)
            for k in range(jb - ja):
                a = base + 2 * k
                faces.append((a, a + 2, a + 3, a + 1))
        return ck.mesh_object(name, verts, faces, [mat], col=col)

    def half_ring(self, t):
        return self.ring(t)

    def gap_along(self, name, j, t_a, t_b, mat, col, width=0.006, lift=0.0016, steps=30):
        verts, faces = [], []
        for k in range(steps + 1):
            t = t_a + (t_b - t_a) * k / steps
            ring = self.ring(t)
            p = Vector(ring[j])
            tan = (Vector(ring[(j + 1) % S]) - Vector(ring[(j - 1) % S])).normalized()
            n = self.ring_normal(ring, j)
            verts.append(p + tan * width / 2 + n * lift)
            verts.append(p - tan * width / 2 + n * lift)
        for k in range(steps):
            a = 2 * k
            faces.append((a, a + 1, a + 3, a + 2))
        return ck.mesh_object(name, verts, faces, [mat], col=col)

    def top_strip(self, name, x0, x1, t_a, t_b, mat, col, roof=False, steps=24, lift=0.003):
        """A flat stripe following the top surface (bonnet/deck or roof)."""
        zf = self.roof_z if roof else self.surface_z
        verts, faces = [], []
        for k in range(steps + 1):
            t = t_a + (t_b - t_a) * k / steps
            y = self.y_of(t)
            verts.append((x0, y, zf(t, x0) + lift))
            verts.append((x1, y, zf(t, x1) + lift))
        for k in range(steps):
            a = 2 * k
            faces.append((a, a + 1, a + 3, a + 2))
        return ck.mesh_object(name, verts, faces, [mat], col=col)


    def side_x(self, t, z):
        """Outer x of the body side at height z (None where the arch cuts it away)."""
        half = self.half_profile(t)
        best = None
        for (x0, z0), (x1, z1) in zip(half, half[1:]):
            lo, hi = min(z0, z1), max(z0, z1)
            if lo <= z <= hi and hi - lo > 1e-6:
                x = x0 + (x1 - x0) * (z - z0) / (z1 - z0)
                best = x if best is None else max(best, x)
        return best

    def side_band(self, name, z0, z1, t_a, t_b, mat, col, lift=0.004, steps=60):
        """A livery band on both flanks between heights z0 and z1 (skips the wheel arches)."""
        verts, faces = [], []
        for sx in (1, -1):
            prev = None
            for k in range(steps + 1):
                t = t_a + (t_b - t_a) * k / steps
                y = self.y_of(t)
                lo = max(z0, self.bottom(t) + 0.012)
                xa, xb = self.side_x(t, lo), self.side_x(t, z1)
                if lo >= z1 - 0.005 or xa is None or xb is None:
                    prev = None
                    continue
                base = len(verts)
                verts.append((sx * (xa + lift), y, lo))
                verts.append((sx * (xb + lift), y, z1))
                if prev is not None:
                    a, b = prev, base
                    faces.append((a, b, b + 1, a + 1) if sx > 0 else (a, a + 1, b + 1, b))
                prev = base
        return ck.mesh_object(name, verts, faces, [mat], col=col)


# ---------------------------------------------------------------------------

def build(d):
    car = Car(d)
    L = car.L
    ck.reset_scene()
    m = ck.standard_materials(paint=d['paint'])
    m['Interior'] = ck.material('Interior', (0.035, 0.035, 0.04), roughness=0.85)
    m['Seat'] = ck.material('Seat', d.get('seat', (0.06, 0.06, 0.065)), roughness=0.9)
    m['Reverse'] = ck.material('Reverse', (0.9, 0.9, 0.9), roughness=0.1, emission=(1, 1, 1), strength=0.3)
    m['Stripe'] = ck.material('Stripe', d.get('stripe', (0.92, 0.92, 0.92)), roughness=0.35, coat=1.0)
    m['Steel'] = ck.material('Steel', (0.3, 0.31, 0.33), metallic=0.7, roughness=0.45)
    m['Hubcap'] = ck.material('Hubcap', (0.72, 0.73, 0.75), metallic=0.6, roughness=0.3)
    ck.set_transparent(m['Glass'], 0.72)
    col = ck.collection(d['root'])
    root = bpy.data.objects.new(d['root'], None)
    col.objects.link(root)
    root['wheel_r'] = car.wr
    parts = []
    extras = set(d.get('extras', []))
    y_of, WIDTH, TOP = car.y_of, car.WIDTH, car.TOP

    def add(o):
        parts.append(o)
        return o

    def zone_of(sx):
        return 'left' if sx > 0 else 'right'

    # ---- Body ----
    zone = {'nose': 'front', 'hood': 'front', 'fender_L': 'left', 'fender_R': 'right', 'door_L': 'left',
            'door_R': 'right', 'quarter_L': 'left', 'quarter_R': 'right', 'deck_lid': 'rear', 'tail': 'rear',
            'tub': 'top', 'underbody': 'bottom'}
    for name, (verts, faces) in ck.loft_parts(car.ring_positions(), S, car.body_section, car.body_part).items():
        mat = m['Trim'] if name == 'underbody' else m['Paint']
        o = ck.mesh_object(name, verts, faces, [mat], smooth=True, col=col,
                           props={'zone': zone[name], 'deform': 0 if name == 'underbody' else 1})
        add(ck.mark_sharp(o, 28))

    # ---- Cabin ----
    gl = car.gl
    keys = {gl['ws_end'], gl['roof_end'], gl['rear_end'], gl['side0'], gl['side1']}
    for a, b in gl['pillars']:
        keys |= {a, b}
    ng = 30 if car.lod else 80
    gts = sorted({car.g0 + (car.g1 - car.g0) * i / ng for i in range(ng + 1)} | {k for k in keys if car.g0 < k < car.g1})
    gmat = {'glass': m['Glass'], 'roof': m['Paint'], 'seal': m[d.get('seal_mat', 'Trim')], 'pillar': m[gl['pillar_mat']]}
    for name, (verts, faces) in ck.loft_parts(gts, G + 1, car.gh_section, car.gh_part, close_front=False,
                                              close_rear=False).items():
        o = ck.mesh_object(f'cabin_{name}', verts, faces, [gmat[name]], smooth=True, col=col,
                           props={'zone': 'top', 'deform': 1})
        add(ck.mark_sharp(o, 30))

    # ---- Panel gaps ----
    sp = car.sp
    side_l, side_r, top = (A1 + 1, A5), (S - A5, S - A1 - 1), (A5, S - A5)
    gaps = [car.gap_across('gap_nose', sp['nose'], [(A1 + 1, S - A1 - 1)], m['Trim'], col),
            car.gap_across('gap_door_front', sp['cowl'], [side_l, side_r], m['Trim'], col),
            car.gap_across('gap_door_rear', sp['door_r'], [side_l, side_r], m['Trim'], col),
            car.gap_across('gap_tail', sp['tail'], [(A1 + 1, S - A1 - 1)], m['Trim'], col)]
    for j, s in ((A5, 'L'), (S - A5, 'R')):
        gaps.append(car.gap_along(f'gap_hood_{s}', j, sp['nose'], sp['cowl'], m['Trim'], col))
    if sp['deck'] < sp['tail'] - 0.02 and sp['deck'] > car.g1 - 0.01:
        gaps.append(car.gap_across('gap_deck', sp['deck'], [top], m['Trim'], col))
        for j, s in ((A5, 'L'), (S - A5, 'R')):
            gaps.append(car.gap_along(f'gap_deck_{s}', j, sp['deck'], sp['tail'], m['Trim'], col))
    for g in gaps:
        g['zone'] = 'top'
        g['deform'] = 1
        add(g)

    # ---- Arch flares ----
    for axle, yc in (('F', car.y_front_axle), ('R', car.y_rear_axle)):
        w = WIDTH(car.t_of(yc))
        for sx, s in ((1, 'L'), (-1, 'R')):
            add(ck.arc_band(f'flare_{axle}{s}', (yc, car.wr), car.arch_r - 0.004, d.get('flare', 0.032), 0.0,
                            math.pi, sx * (w - 0.03), sx * (w + 0.014),
                            m['Trim'] if d.get('bumper') in ('black', 'chrome') and d.get('flare_trim') else m['Paint'],
                            col=col, props={'zone': zone_of(sx), 'deform': 1}))

    # ---- Front & rear ----
    front(car, d, m, col, add)
    rear(car, d, m, col, add)
    spoiler(car, d, m, col, add)

    # ---- Sides ----
    tm_ = sp['cowl'] + 0.035
    ym, zm, wm = y_of(tm_), TOP(tm_), WIDTH(tm_)
    for sx, s in ((1, 'L'), (-1, 'R')):
        zs = zone_of(sx)
        add(ck.box(f'mirror_{s}', (0.075, 0.14, 0.075), (sx * (wm + 0.02), ym, zm + 0.06), m['Paint'], col=col,
                   bevel_width=0.015, props={'zone': zs, 'detach': 1}))
        add(ck.box(f'mirror_glass_{s}', (0.06, 0.008, 0.05), (sx * (wm + 0.025), ym + 0.072, zm + 0.06),
                   m['Chrome'], col=col, props={'zone': zs, 'detach': 1}))
        add(ck.box(f'mirror_stalk_{s}', (0.16, 0.04, 0.025), (sx * (wm - 0.08), ym + 0.02, zm + 0.025), m['Trim'],
                   col=col, props={'zone': zs, 'detach': 1}))
        if 'skirts' in extras:
            skirt_len = (car.y_rear_axle - car.y_front_axle) - 2 * car.arch_r - 0.08
            add(ck.box(f'skirt_{s}', (0.06, skirt_len, 0.075),
                       (sx * (WIDTH(0.5) - 0.0), (car.y_front_axle + car.y_rear_axle) / 2, car.BOTTOM(0.5) + 0.03),
                       m['Trim'], col=col, bevel_width=0.008, props={'zone': zs, 'detach': 1}))
        elif 'rubbing_strip' in extras:
            add(ck.box(f'strip_{s}', (0.02, L * 0.62, 0.04), (sx * (WIDTH(0.5) + 0.004), y_of(0.5),
                       car.SHOULDER(0.5) - 0.17), m['Trim'], col=col, bevel_width=0.006, props={'zone': zs}))
        th = (sp['cowl'] + sp['door_r']) / 2 + 0.07
        add(ck.box(f'handle_{s}', (0.015, 0.14, 0.03), (sx * (WIDTH(th) - 0.002), y_of(th), car.SHOULDER(th) - 0.03),
                   m['Trim'] if d.get('bumper') != 'chrome' else m['Chrome'], col=col, bevel_width=0.005,
                   props={'zone': zs}))
        for axle, yc in (('F', car.y_front_axle), ('R', car.y_rear_axle)):
            add(ck.box(f'well_{axle}{s}', (0.02, 2 * car.arch_r, car.arch_r + car.wr - 0.2),
                       (sx * (car.track - car.ww / 2 - 0.06), yc, (car.arch_r + car.wr) / 2 + 0.1), m['Trim'],
                       col=col, props={'zone': 'bottom'}))
    tf = (sp['door_r'] + sp['tail']) / 2 + 0.03
    add(ck.cylinder('fuel_cap', 0.055, 0.012, (-(WIDTH(tf) + 0.002), y_of(tf), car.SHOULDER(tf) - 0.07), m['Trim'],
                    col=col, axis='X', segments=20, props={'zone': 'right'}))
    if 'antenna' in extras:
        ta = min(0.9, sp['tail'] - 0.04)
        ant = add(ck.cylinder('antenna', 0.003, 0.38, (-(WIDTH(ta) - 0.2), y_of(ta), TOP(ta) + 0.17), m['Trim'],
                              col=col, axis='Z', segments=6, props={'zone': 'rear', 'detach': 1}))
        ant.rotation_euler = (math.radians(18), 0, 0)
    if 'vents' in extras:
        for k in range(5):
            t = sp['cowl'] * 0.65 + k * 0.012
            for sx in (1, -1):
                add(ck.box(f'vent_{"L" if sx > 0 else "R"}{k}', (0.24, 0.022, 0.012),
                           (sx * 0.2, y_of(t), car.surface_z(t, 0.2) + 0.004), m['Trim'], col=col,
                           rotation=(math.radians(-6), 0, 0), props={'zone': 'front'}))
    if 'scoop' in extras:
        t = sp['cowl'] * 0.6
        add(ck.box('hood_scoop', (0.5, 0.42, 0.05), (0, y_of(t), car.surface_z(t, 0) + 0.02), m['Paint'], col=col,
                   bevel_width=0.02, props={'zone': 'front', 'deform': 1}))
        add(ck.box('hood_scoop_mouth', (0.42, 0.02, 0.035), (0, y_of(t) - 0.21, car.surface_z(t, 0) + 0.025),
                   m['Trim'], col=col, props={'zone': 'front'}))
    for k, x in enumerate((0.25, -0.2)):
        t = sp['cowl'] + 0.003
        add(ck.box(f'wiper{k}', (0.5, 0.018, 0.012), (x, y_of(t), TOP(t) + 0.02), m['Trim'], col=col,
                   rotation=(math.radians(-25), 0, math.radians(6)), props={'zone': 'top'}))
    if 'rails' in extras:
        ta, tb = gl['ws_end'] + 0.03, car.g1 - 0.04
        for sx, s in ((1, 'L'), (-1, 'R')):
            x = sx * (car.ROOF_W((ta + tb) / 2) - 0.07)
            z = car.roof_z((ta + tb) / 2, abs(x)) + 0.035
            add(ck.box(f'rail_{s}', (0.035, (tb - ta) * L, 0.025), (x, y_of((ta + tb) / 2), z), m['Trim'], col=col,
                       bevel_width=0.008, props={'zone': 'top', 'detach': 1}))
            for t in (ta + 0.01, tb - 0.01):
                add(ck.box(f'rail_foot_{s}{int(t * 100)}', (0.04, 0.05, 0.05), (x, y_of(t), z - 0.025), m['Trim'],
                           col=col, props={'zone': 'top', 'detach': 1}))
    if 'roofbox' in extras:
        roofbox(car, m, col, add)
    if 'stripes' in extras:
        for k, (x0, x1) in enumerate(((0.08, 0.2), (-0.2, -0.08))):
            add(car.top_strip(f'stripe_hood{k}', x0, x1, sp['nose'] * 0.4, sp['cowl'] - 0.005, m['Stripe'], col))
            add(car.top_strip(f'stripe_roof{k}', x0, x1, gl['ws_end'] + 0.005, gl['roof_end'] - 0.005, m['Stripe'],
                              col, roof=True))
            add(car.top_strip(f'stripe_deck{k}', x0, x1, max(car.g1, sp['deck']) + 0.005, 0.995, m['Stripe'], col))

    if 'police' in extras:
        police(car, d, m, col, add)

    interior(car, d, m, col, add)

    # ---- Wheels ----
    base_wheel = wheel(car, d.get('wheel_style', 'tenspoke'), m, col)
    hubs = []
    for axle, yc in (('F', car.y_front_axle), ('R', car.y_rear_axle)):
        for sx, s in ((1, 'L'), (-1, 'R')):
            hub = bpy.data.objects.new(f'hub_{axle}{s}', None)
            hub.location = (sx * car.track, yc, car.wr)
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
            r = car.wr
            cal = ck.box(f'caliper_{axle}{s}', (0.055, 0.42 * r, 0.35 * r), (sx * -0.05, 0.35 * r, 0.32 * r),
                         m['Caliper'] if d.get('red_calipers', True) else m['Steel'], col=col, bevel_width=0.015,
                         rotation=(math.radians(-40), 0, 0))
            cal.parent = hub
            hubs.append(hub)
    bpy.data.objects.remove(base_wheel)

    for o in parts:
        if 'zone' not in o.keys():
            o['zone'] = 'top'
    for o in parts + hubs:
        o.parent = root
    return root, car


# ---------------------------------------------------------------------------
# Front / rear styles
# ---------------------------------------------------------------------------

def nose_box(car):
    """Usable area of the flat nose face: (half width, z bottom, z top)."""
    return car.WIDTH(0) - 0.09, car.BOTTOM(0) + 0.02, car.TOP(0) - 0.02


def tail_box(car):
    return car.WIDTH(1) - 0.09, car.BOTTOM(1) + 0.02, car.TOP(1) - 0.02


def front(car, d, m, col, add):
    L = car.L
    yn = -L / 2 - 0.004
    hw, zb, zt = nose_box(car)
    style = d.get('front', 'popup')
    bumper = d.get('bumper', 'body')
    fz = lambda f: zb + (zt - zb) * f  # noqa: E731  (fraction up the nose face)
    props = {'zone': 'front'}

    # Bumper bar (separate, can be torn off) or integrated intake.
    if bumper in ('black', 'chrome'):
        bz = fz(0.28)
        mat = m['Chrome'] if bumper == 'chrome' else m['Trim']
        add(ck.box('bumper_front', (2 * hw + 0.2, 0.12, 0.13), (0, yn - 0.05, bz), mat, col=col, bevel_width=0.025,
                   props={'zone': 'front', 'detach': 1}))
        if bumper == 'chrome':
            add(ck.box('bumper_front_rubber', (2 * hw + 0.21, 0.125, 0.035), (0, yn - 0.05, bz), m['Trim'], col=col,
                       props={'zone': 'front', 'detach': 1}))
        for sx in (1, -1):
            add(ck.box(f'bumper_front_end{sx}', (0.1, 0.35, 0.12), (sx * (hw + 0.08), yn + 0.14, bz), mat, col=col,
                       bevel_width=0.02, props={'zone': 'front', 'detach': 1}))
        plate_z, plate_y = bz, yn - 0.115
    else:
        add(ck.box('intake', (min(0.66, hw * 1.1), 0.04, 0.15), (0, yn + 0.01, fz(0.42)), m['Trim'], col=col,
                   bevel_width=0.012, props=props))
        for k, f in enumerate((0.36, 0.48)):
            add(ck.box(f'intake_slat{k}', (min(0.62, hw * 1.05), 0.02, 0.012), (0, yn - 0.012, fz(f)), m['Chrome'],
                       col=col, props=props))
        plate_z, plate_y = fz(0.14), yn - 0.006
    add(ck.box('plate_frame_front', (0.56, 0.015, 0.14), (0, plate_y + 0.01, plate_z), m['Trim'], col=col,
               props={'zone': 'front', 'detach': 1}))
    add(ck.plane('plate_front', (0.52, 0.115), (0, plate_y, plate_z), m['Plate'], col=col,
                 props={'zone': 'front', 'detach': 1}))

    if 'splitter' in d.get('extras', []):
        add(ck.extrude_yz('splitter', [(-L / 2 - 0.06, car.BOTTOM(0) - 0.07), (-L / 2 + 0.3, car.BOTTOM(0) - 0.07),
                                       (-L / 2 + 0.3, car.BOTTOM(0) - 0.05), (-L / 2 - 0.01, car.BOTTOM(0) - 0.035)],
                          -hw - 0.15, hw + 0.15, m['Trim'], col=col, props={'zone': 'front', 'detach': 1}))
    if 'foglamps' in d.get('extras', []):
        for sx, s in ((1, 'L'), (-1, 'R')):
            add(ck.box(f'duct_{s}', (0.19, 0.04, 0.10), (sx * hw * 0.72, yn + 0.01, fz(0.3)), m['Trim'], col=col,
                       bevel_width=0.01, props=props))
            add(ck.cylinder(f'foglamp_{s}', 0.034, 0.02, (sx * hw * 0.72, yn - 0.012, fz(0.3)), m['HeadLight'],
                            col=col, axis='Y', segments=20, props=props))

    for sx, s in ((1, 'L'), (-1, 'R')):
        if style == 'popup':
            t = 0.115
            x, y = sx * 0.5, car.y_of(t)
            z = car.surface_z(t, 0.5) + 0.04
            tilt = (math.radians(-8), 0, 0)
            pp = {'zone': 'front', 'detach': 1}
            add(ck.box(f'popup_{s}', (0.36, 0.20, 0.085), (x, y, z), m['Paint'], col=col, bevel_width=0.008,
                       rotation=tilt, props=pp))
            add(ck.box(f'popup_face_{s}', (0.33, 0.012, 0.07), (x, y - 0.1, z + 0.006), m['Trim'], col=col,
                       rotation=tilt, props=pp))
            for k, dx in enumerate((-0.08, 0.08)):
                add(ck.cylinder(f'popup_ring_{s}{k}', 0.032, 0.008, (x + dx, y - 0.108, z + 0.007), m['Chrome'],
                                col=col, axis='Y', segments=20, props=pp))
                add(ck.cylinder(f'popup_lamp_{s}{k}', 0.026, 0.008, (x + dx, y - 0.113, z + 0.007), m['HeadLight'],
                                col=col, axis='Y', segments=20, props=pp))
            add(ck.box(f'indicator_front_{s}', (0.12, 0.03, 0.035), (sx * hw * 0.8, yn + 0.008, fz(0.62)),
                       m['Indicator'], col=col, bevel_width=0.006, props=props))
        elif style in ('rect', 'slim', 'twin_rect'):
            hgt = {'rect': 0.085, 'slim': 0.05, 'twin_rect': 0.12}[style]
            wid = {'rect': 0.36, 'slim': 0.42, 'twin_rect': 0.3}[style]
            x = sx * (hw - wid / 2 - 0.02)
            z = fz(0.8) if style != 'twin_rect' else fz(0.7)
            add(ck.box(f'lamp_bezel_{s}', (wid + 0.03, 0.03, hgt + 0.03), (x, yn + 0.006, z), m['Trim'], col=col,
                       bevel_width=0.008, props=props))
            add(ck.box(f'headlamp_{s}', (wid, 0.02, hgt), (x, yn - 0.006, z), m['HeadLight'], col=col,
                       bevel_width=0.006, props=props))
            add(ck.box(f'lamp_divider_{s}', (0.012, 0.024, hgt), (x - sx * wid * 0.15, yn - 0.008, z), m['Chrome'],
                       col=col, props=props))
            add(ck.box(f'indicator_front_{s}', (0.09, 0.025, hgt * 0.8), (sx * (hw - 0.02), yn + 0.02, z),
                       m['Indicator'], col=col, props=props))
        elif style == 'round':
            z = fz(0.68)
            for k, (dx, r) in enumerate(((0.2, 0.075), (0.38, 0.06))):
                add(ck.cylinder(f'ring_{s}{k}', r + 0.012, 0.02, (sx * (hw - 0.45 + dx), yn - 0.004, z), m['Chrome'],
                                col=col, axis='Y', segments=24, props=props))
                add(ck.cylinder(f'headlamp_{s}{k}', r, 0.02, (sx * (hw - 0.45 + dx), yn - 0.01, z), m['HeadLight'],
                                col=col, axis='Y', segments=24, props=props))
            add(ck.box(f'indicator_front_{s}', (0.12, 0.03, 0.04), (sx * (hw - 0.1), yn - 0.08, fz(0.28) - 0.07),
                       m['Indicator'], col=col, props=props))
        elif style == 'square':
            z = fz(0.66)
            add(ck.box(f'lamp_bezel_{s}', (0.3, 0.03, 0.2), (sx * (hw - 0.17), yn + 0.006, z), m['Chrome'], col=col,
                       bevel_width=0.008, props=props))
            add(ck.box(f'headlamp_{s}', (0.26, 0.02, 0.16), (sx * (hw - 0.17), yn - 0.006, z), m['HeadLight'],
                       col=col, props=props))
            add(ck.box(f'indicator_front_{s}', (0.07, 0.025, 0.16), (sx * (hw + 0.0), yn + 0.03, z), m['Indicator'],
                       col=col, props=props))

    # Grilles between the lamps
    grille = d.get('grille')
    if grille == 'slats':
        gw = hw - 0.42 if style != 'twin_rect' else hw - 0.34
        z = fz(0.72) if style == 'twin_rect' else fz(0.68)
        add(ck.box('grille', (2 * gw, 0.03, 0.12), (0, yn + 0.004, z), m['Trim'], col=col, bevel_width=0.008,
                   props=props))
        for k in range(3):
            add(ck.box(f'grille_slat{k}', (2 * gw - 0.02, 0.012, 0.01), (0, yn - 0.012, z - 0.04 + k * 0.04),
                       m['Chrome'] if d.get('chrome_grille') else m['Trim'], col=col, props=props))
        if d.get('grille_stripe'):
            add(ck.box('grille_stripe', (2 * hw - 0.05, 0.012, 0.012), (0, yn - 0.014, z - 0.065), m['Caliper'],
                       col=col, props=props))
    elif grille == 'band':  # full-width black band holding round lamps
        add(ck.box('grille', (2 * hw + 0.02, 0.03, 0.2), (0, yn + 0.01, fz(0.68)), m['Trim'], col=col,
                   bevel_width=0.008, props=props))
        for k in range(4):
            add(ck.box(f'grille_slat{k}', (0.42, 0.012, 0.012), (0, yn - 0.008, fz(0.68) - 0.06 + k * 0.04),
                       m['Trim'], col=col, props=props))
        if d.get('grille_stripe'):
            add(ck.box('grille_stripe', (2 * hw - 0.05, 0.012, 0.014), (0, yn - 0.012, fz(0.68) - 0.09),
                       m['Caliper'], col=col, props=props))
    elif grille == 'egg':
        z = fz(0.66)
        gw = hw - 0.34
        add(ck.box('grille_frame', (2 * gw + 0.04, 0.03, 0.22), (0, yn + 0.004, z), m['Chrome'], col=col,
                   bevel_width=0.01, props=props))
        add(ck.box('grille', (2 * gw, 0.03, 0.18), (0, yn - 0.002, z), m['Trim'], col=col, props=props))
        for k in range(9):
            add(ck.box(f'grille_bar{k}', (0.01, 0.014, 0.18), (-gw + (k + 0.5) * 2 * gw / 9, yn - 0.014, z),
                       m['Chrome'], col=col, props=props))
        add(ck.box('grille_badge', (0.04, 0.012, 0.19), (0, yn - 0.02, z), m['Chrome'], col=col,
                   rotation=(0, math.radians(35), 0), props=props))


def rear(car, d, m, col, add):
    L = car.L
    yt = L / 2 + 0.004
    hw, zb, zt = tail_box(car)
    fz = lambda f: zb + (zt - zb) * f  # noqa: E731
    style = d.get('rear', 'round4')
    bumper = d.get('bumper', 'body')
    props = {'zone': 'rear'}
    lz = fz(d.get('tail_lamp_height', 0.68))

    if style == 'round4':
        add(ck.box('tail_garnish', (2 * hw + 0.1, 0.025, 0.16), (0, yt, lz), m['Trim'], col=col, bevel_width=0.008,
                   props=props))
        for sx, s in ((1, 'L'), (-1, 'R')):
            for k, xo in enumerate((0.38, 0.66)):
                x = sx * hw * xo / 0.66 * 0.95
                add(ck.cylinder(f'tail_ring_{s}{k}', 0.066, 0.01, (x, yt + 0.014, lz), m['Chrome'], col=col, axis='Y',
                                segments=24, props=props))
                add(ck.cylinder(f'taillight_{s}{k}', 0.056, 0.012, (x, yt + 0.02, lz), m['BrakeLight'], col=col,
                                axis='Y', segments=24, props=props))
            add(ck.cylinder(f'reverse_{s}', 0.03, 0.01, (sx * 0.16, yt + 0.016, lz), m['Reverse'], col=col, axis='Y',
                            segments=16, props=props))
            add(ck.box(f'indicator_rear_{s}', (0.16, 0.012, 0.022), (sx * hw * 0.65, yt + 0.016, lz - 0.065),
                       m['Indicator'], col=col, props=props))
    elif style == 'oval2':
        add(ck.box('tail_garnish', (2 * hw + 0.1, 0.025, 0.2), (0, yt, lz), m['Trim'], col=col, bevel_width=0.008,
                   props=props))
        for sx, s in ((1, 'L'), (-1, 'R')):
            for k, xo in enumerate((0.42, 0.78)):
                x = sx * hw * xo
                ring = add(ck.cylinder(f'tail_ring_{s}{k}', 0.085, 0.01, (x, yt + 0.014, lz), m['Chrome'], col=col,
                                       axis='Y', segments=28, props=props))
                lamp = add(ck.cylinder(f'taillight_{s}{k}', 0.075, 0.012, (x, yt + 0.02, lz), m['BrakeLight'],
                                       col=col, axis='Y', segments=28, props=props))
                ring.scale = lamp.scale = (1.35, 1, 1)
            add(ck.box(f'reverse_{s}', (0.12, 0.012, 0.05), (sx * hw * 0.12, yt + 0.016, lz), m['Reverse'], col=col,
                       props=props))
    elif style == 'bar':
        add(ck.box('tail_bar', (2 * hw + 0.12, 0.025, 0.11), (0, yt, lz), m['BrakeLight'], col=col,
                   bevel_width=0.008, props=props))
        add(ck.box('tail_bar_center', (0.5, 0.03, 0.115), (0, yt + 0.004, lz), m['Trim'], col=col, props=props))
        for sx, s in ((1, 'L'), (-1, 'R')):
            add(ck.box(f'reverse_{s}', (0.12, 0.03, 0.06), (sx * 0.32, yt + 0.006, lz), m['Reverse'], col=col,
                       props=props))
            add(ck.box(f'indicator_rear_{s}', (0.1, 0.03, 0.05), (sx * (hw - 0.02), yt + 0.006, lz), m['Indicator'],
                       col=col, props=props))
    elif style == 'blocks':
        for sx, s in ((1, 'L'), (-1, 'R')):
            x = sx * (hw - 0.17)
            add(ck.box(f'tail_housing_{s}', (0.36, 0.025, 0.2), (x, yt, lz), m['Trim'], col=col, bevel_width=0.01,
                       props=props))
            add(ck.box(f'taillight_{s}', (0.32, 0.03, 0.08), (x, yt + 0.004, lz + 0.045), m['BrakeLight'], col=col,
                       props=props))
            add(ck.box(f'indicator_rear_{s}', (0.32, 0.03, 0.04), (x, yt + 0.004, lz - 0.02), m['Indicator'],
                       col=col, props=props))
            add(ck.box(f'reverse_{s}', (0.32, 0.03, 0.035), (x, yt + 0.004, lz - 0.065), m['Reverse'], col=col,
                       props=props))
    elif style == 'tall':
        for sx, s in ((1, 'L'), (-1, 'R')):
            x = sx * (hw - 0.06)
            h = (zt - zb) * 0.6
            z = zt - h / 2 - 0.02
            add(ck.box(f'tail_housing_{s}', (0.16, 0.03, h + 0.03), (x, yt, z), m['Chrome'], col=col,
                       bevel_width=0.006, props=props))
            add(ck.box(f'taillight_{s}', (0.13, 0.034, h * 0.55), (x, yt + 0.002, z + h * 0.2), m['BrakeLight'],
                       col=col, props=props))
            add(ck.box(f'indicator_rear_{s}', (0.13, 0.034, h * 0.2), (x, yt + 0.002, z - h * 0.18), m['Indicator'],
                       col=col, props=props))
            add(ck.box(f'reverse_{s}', (0.13, 0.034, h * 0.16), (x, yt + 0.002, z - h * 0.38), m['Reverse'],
                       col=col, props=props))

    if bumper in ('black', 'chrome'):
        bz = fz(0.22)
        mat = m['Chrome'] if bumper == 'chrome' else m['Trim']
        add(ck.box('bumper_rear', (2 * hw + 0.2, 0.12, 0.13), (0, yt + 0.05, bz), mat, col=col, bevel_width=0.025,
                   props={'zone': 'rear', 'detach': 1}))
        if bumper == 'chrome':
            add(ck.box('bumper_rear_rubber', (2 * hw + 0.21, 0.125, 0.035), (0, yt + 0.05, bz), m['Trim'], col=col,
                       props={'zone': 'rear', 'detach': 1}))
        plate_z = fz(0.45)
    else:
        plate_z = fz(0.4)
        if 'diffuser' in d.get('extras', []):
            add(ck.box('diffuser', (2 * hw - 0.1, 0.34, 0.03), (0, L / 2 - 0.14, car.BOTTOM(1) - 0.075), m['Trim'],
                       col=col, props={'zone': 'rear', 'detach': 1}))
            for k in range(4):
                add(ck.box(f'diffuser_fin{k}', (0.012, 0.32, 0.07), (-0.36 + k * 0.24, L / 2 - 0.14,
                           car.BOTTOM(1) - 0.045), m['Trim'], col=col, props={'zone': 'rear', 'detach': 1}))
    add(ck.box('plate_frame_rear', (0.56, 0.015, 0.14), (0, yt + 0.002, plate_z), m['Trim'], col=col,
               props={'zone': 'rear', 'detach': 1}))
    add(ck.plane('plate_rear', (0.52, 0.115), (0, yt + 0.012, plate_z), m['Plate'], col=col, rotation=(0, 0, math.pi),
                 props={'zone': 'rear', 'detach': 1}))

    exhaust = d.get('exhaust', 'dual')
    ez = car.BOTTOM(1) - 0.02
    xs = {'dual': (-0.47, -0.34), 'single': (-0.45,), 'can': (-0.45,), 'split': (-0.55, 0.55),
          'quad': (-0.6, -0.47, 0.47, 0.6)}[exhaust]
    for k, x in enumerate(xs):
        r = {'single': 0.035, 'can': 0.075}.get(exhaust, 0.048)
        add(ck.cylinder(f'exhaust{k}', r, 0.2, (x, L / 2 - 0.02, ez), m['Chrome'], col=col, axis='Y', segments=20,
                        props=props))
        add(ck.cylinder(f'exhaust_inner{k}', r * 0.75, 0.205, (x, L / 2 - 0.02, ez), m['Trim'], col=col, axis='Y',
                        segments=20, props=props))


def spoiler(car, d, m, col, add):
    L = car.L
    kind = d.get('spoiler')
    pp = {'zone': 'rear', 'detach': 1}
    if kind in ('wing', 'hoop'):
        hoop = kind == 'hoop'
        yw = L / 2 - (0.47 if not hoop else 0.4)
        tz = car.TOP(car.t_of(yw + 0.2))
        zw = tz + (0.1 if not hoop else 0.2)
        foil = [(0.0, 0.0), (0.03, 0.022), (0.10, 0.04), (0.20, 0.038), (0.32, 0.018), (0.33, 0.008), (0.20, 0.008),
                (0.10, 0.004), (0.03, -0.006)]
        span = 0.72 if not hoop else 0.68
        add(ck.extrude_yz('spoiler', [(yw + y, zw + z) for y, z in foil], -span, span, m['Paint'], col=col,
                          props=pp))
        for sx, s in ((1, 'L'), (-1, 'R')):
            if hoop:  # the stands are the outer ends of the hoop, in body colour
                add(ck.box(f'spoiler_stand_{s}', (0.06, 0.2, zw - tz + 0.03), (sx * (span - 0.03), yw + 0.18,
                           (zw + tz) / 2), m['Paint'], col=col, bevel_width=0.015,
                           rotation=(math.radians(10), 0, 0), props=pp))
            else:
                add(ck.box(f'spoiler_plate_{s}', (0.012, 0.3, 0.085), (sx * (span + 0.005), yw + 0.17, zw + 0.012),
                           m['Paint'], col=col, bevel_width=0.004, props=pp))
                add(ck.box(f'spoiler_stand_{s}', (0.03, 0.12, zw - tz + 0.02), (sx * 0.5, yw + 0.2, (zw + tz) / 2),
                           m['Trim'], col=col, bevel_width=0.006, rotation=(math.radians(15), 0, 0), props=pp))
        add(ck.box('brake_light_high', (0.36, 0.012, 0.018), (0, yw + 0.335, zw + 0.02), m['BrakeLight'], col=col,
                   props=pp))
    elif kind == 'roof':
        # A lip on the trailing edge of the roof, just above the rear window.
        t = car.gl['roof_end'] - 0.012
        z = car.roof_z(t) + 0.012
        w = car.ROOF_W(t) - 0.05
        add(ck.box('spoiler', (2 * w, 0.18, 0.025), (0, car.y_of(t) + 0.06, z), m['Paint'], col=col,
                   bevel_width=0.008, rotation=(math.radians(-8), 0, 0), props=pp))
        add(ck.box('brake_light_high', (0.3, 0.012, 0.02), (0, car.y_of(t) + 0.15, z - 0.01), m['BrakeLight'],
                   col=col, props=pp))
    elif kind == 'lip':
        t = 0.985
        z = car.TOP(t) + 0.02
        add(ck.box('spoiler', (2 * (car.WIDTH(t) - 0.15), 0.12, 0.03), (0, car.y_of(t), z), m['Paint'], col=col,
                   bevel_width=0.01, rotation=(math.radians(12), 0, 0), props=pp))


def roofbox(car, m, col, add):
    """Thuisbesteld delivery box on the roof, with lettering built from a text object."""
    t = (car.gl['ws_end'] + car.gl['roof_end']) / 2 + 0.03
    z = car.roof_z(t) + 0.245
    y = car.y_of(t)
    add(ck.box('roofbox', (0.62, 0.52, 0.46), (0, y, z), m['Paint'], col=col, bevel_width=0.025,
               props={'zone': 'top', 'detach': 1}))
    add(ck.box('roofbox_lid', (0.64, 0.54, 0.04), (0, y, z + 0.24), m['Stripe'], col=col, bevel_width=0.015,
               props={'zone': 'top', 'detach': 1}))
    for sx in (1, -1):
        add(text_mesh(f'roofbox_text{sx}', 'Thuisbesteld', 0.085, (sx * 0.314, y, z + 0.02), sx, m['Stripe'], col))
    for k, x in enumerate((-0.2, 0.2)):
        add(ck.box(f'roofbox_strap{k}', (0.04, 0.6, 0.02), (x, y, car.roof_z(t, abs(x)) + 0.02), m['Trim'], col=col,
                   props={'zone': 'top', 'detach': 1}))


def police(car, d, m, col, add):
    """Dutch police striping: a wide blue band over a thin red-orange one, POLITIE, light bar."""
    blue = ck.material('PoliceBlue', (0.012, 0.045, 0.32), roughness=0.35, coat=1.0)
    orange = ck.material('PoliceOrange', (0.95, 0.12, 0.02), roughness=0.35, coat=1.0)
    white = ck.material('White', (0.85, 0.85, 0.85), roughness=0.4)
    sp, gl, L = car.sp, car.gl, car.L
    zs = car.SHOULDER(0.5)
    zb = zs - 0.25
    band = add(car.side_band('livery_blue', zb, zs - 0.04, 0.035, 0.975, blue, col))
    band['zone'], band['deform'] = 'left', 1
    thin = add(car.side_band('livery_orange', zb - 0.075, zb - 0.02, 0.035, 0.975, orange, col))
    thin['zone'], thin['deform'] = 'right', 1
    tm = (sp['cowl'] + sp['door_r']) / 2
    for sx in (1, -1):
        x = car.side_x(tm, zs - 0.165) or car.WIDTH(tm)
        add(text_mesh(f'politie_{"L" if sx > 0 else "R"}', 'POLITIE', 0.15, (sx * (x + 0.008), car.y_of(tm),
                      zs - 0.165), sx, white, col))
    # Light bar across the roof, just behind the windscreen.
    tb = gl['ws_end'] + 0.05
    zr = car.roof_z(tb, 0)
    y = car.y_of(tb)
    add(ck.box('lightbar', (1.15, 0.26, 0.06), (0, y, zr + 0.05), m['Trim'], col=col, bevel_width=0.015,
               props={'zone': 'top', 'detach': 1}))
    for sx, nm in ((1, 'BeaconL'), (-1, 'BeaconR')):
        mat = ck.material(nm, (0.02, 0.05, 0.25), roughness=0.2, emission=(0.1, 0.3, 1.0), strength=0.5)
        ck.set_transparent(mat, 0.85)
        add(ck.box(f'beacon_{"L" if sx > 0 else "R"}', (0.5, 0.22, 0.11), (sx * 0.29, y, zr + 0.13), mat, col=col,
                   bevel_width=0.03, props={'zone': 'top', 'detach': 1}))


def text_mesh(name, text, size, location, side, mat, col):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = text
    curve.size = size
    curve.align_x = 'CENTER'
    curve.align_y = 'CENTER'
    curve.extrude = 0.002
    tmp = bpy.data.objects.new(name + '_tmp', curve)
    col.objects.link(tmp)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(deps))
    bpy.data.objects.remove(tmp)
    me.materials.clear()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    obj.location = location
    # Text lies in XY facing +Z; stand it up and face it outwards along ±X.
    obj.rotation_euler = (math.pi / 2, 0, math.pi / 2 if side > 0 else -math.pi / 2)
    obj['zone'] = 'top'
    obj['detach'] = 1
    return obj


def interior(car, d, m, col, add):
    y_of = car.y_of
    sp = car.sp
    zoff = d.get('seat_z', 0.0)
    dash_t = sp['cowl'] + 0.065
    dz = car.TOP(dash_t) + 0.0 + zoff * 0.5
    add(ck.box('dash', (2 * car.WIDTH(dash_t) - 0.34, 0.34, 0.16), (0, y_of(dash_t), dz), m['Interior'], col=col,
               bevel_width=0.02, rotation=(math.radians(-12), 0, 0)))
    seat_t = dash_t + 0.13
    add(ck.box('console', (0.22, 0.75, 0.2), (0, y_of(seat_t - 0.02), 0.52 + zoff), m['Interior'], col=col,
               bevel_width=0.02))
    if not car.lod:
        add(ck.ellipsoid('gear_knob', (0.025, 0.025, 0.025), (0, y_of(seat_t - 0.06), 0.67 + zoff), m['Chrome'], col=col))
    sw_t = dash_t + 0.035
    if not car.lod:
        sw = ck.torus_x('steering_wheel', 0.17, 0.018, (0.37, y_of(sw_t), dz + 0.08), m['Interior'], col=col)
        sw.rotation_euler = (0, math.radians(25), math.pi / 2)
        add(sw)
    add(ck.cylinder('steering_hub', 0.05, 0.05, (0.37, y_of(sw_t), dz + 0.08), m['Interior'], col=col, axis='Y'))
    for sx, s in ((1, 'L'), (-1, 'R')):
        x = sx * 0.37
        add(ck.box(f'seat_base_{s}', (0.46, 0.5, 0.12), (x, y_of(seat_t), 0.42 + zoff), m['Seat'], col=col,
                   bevel_width=0.03))
        add(ck.box(f'seat_back_{s}', (0.46, 0.12, 0.6), (x, y_of(seat_t) + 0.27, 0.7 + zoff), m['Seat'], col=col,
                   bevel_width=0.03, rotation=(math.radians(14), 0, 0)))
        add(ck.box(f'headrest_{s}', (0.26, 0.1, 0.16), (x, y_of(seat_t) + 0.35, 1.05 + zoff), m['Seat'], col=col,
                   bevel_width=0.03, rotation=(math.radians(14), 0, 0)))
    if d.get('rear_seat'):
        rt = seat_t + 0.9 / car.L
        add(ck.box('rear_bench', (1.3, 0.48, 0.12), (0, y_of(rt), 0.45 + zoff), m['Seat'], col=col, bevel_width=0.03))
        add(ck.box('rear_back', (1.3, 0.12, 0.5), (0, y_of(rt) + 0.27, 0.7 + zoff), m['Seat'], col=col,
                   bevel_width=0.03, rotation=(math.radians(10), 0, 0)))
    add(ck.box('cabin_floor', (1.5, 1.6, 0.04), (0, y_of(seat_t), 0.3), m['Interior'], col=col))


# ---------------------------------------------------------------------------
# Wheels
# ---------------------------------------------------------------------------

def wheel(car, style, m, col, name='wheel_proto'):
    r, w = car.wr, car.ww
    rim_r = r * 0.66
    seg = 18 if car.lod else 40
    tread = []
    for k in range(6):
        x0 = -w / 2 + 0.03 + k * (w - 0.06) / 5
        tread += [(r, x0), (r - 0.007, x0 + 0.004), (r - 0.007, x0 + 0.01), (r, x0 + 0.014)] if 0 < k < 5 else [(r, x0)]
    if car.lod:
        tread = [(r, -w / 2 + 0.03), (r, w / 2 - 0.03)]
    profile = [(rim_r, -w / 2 + 0.012), (r - 0.04, -w / 2), (r - 0.01, -w / 2 + 0.012)] + tread + \
              [(r - 0.01, w / 2 - 0.012), (r - 0.04, w / 2), (rim_r, w / 2 - 0.012)]
    parts = [ck.bm_object(name + '_tyre', ck.lathe(profile, seg), [m['Tyre']], col=col, smooth=True)]
    ck.mark_sharp(parts[0], 50)
    rim_mat = m['Steel'] if style == 'steel' else m['Rim']
    barrel = ck.lathe([(rim_r + 0.004, w / 2 - 0.01), (rim_r - 0.008, w / 2 - 0.02), (rim_r - 0.012, -w / 2 + 0.03),
                       (rim_r, -w / 2 + 0.012)], seg)
    parts.append(ck.bm_object(name + '_barrel', barrel, [rim_mat], col=col, smooth=True))
    face_x = w / 2 - 0.04

    if style == 'steel':
        cap = ck.lathe([(0.001, face_x + 0.02), (rim_r * 0.5, face_x + 0.018), (rim_r * 0.92, face_x + 0.004),
                        (rim_r * 0.98, face_x - 0.01)], seg)
        parts.append(ck.bm_object(name + '_hubcap', cap, [m['Hubcap']], col=col, smooth=True))
        for k in range(8):
            a = 2 * math.pi * k / 8
            s = ck.box(name + f'_slot{k}', (0.01, 0.03, 0.05), (0, 0, 0), m['Trim'], col=col)
            s.rotation_euler = (a, 0, 0)
            s.location = (face_x + 0.012, -math.sin(a) * rim_r * 0.72, math.cos(a) * rim_r * 0.72)
            parts.append(s)
    else:
        lip = ck.lathe([(rim_r - 0.012, w / 2 - 0.012), (rim_r + 0.006, w / 2 - 0.008), (rim_r + 0.006, w / 2 - 0.02)],
                       seg)
        parts.append(ck.bm_object(name + '_lip', lip, [m['Chrome']], col=col, smooth=True))
        parts.append(ck.cylinder(name + '_hub', rim_r * 0.3, 0.05, (face_x - 0.012, 0, 0), m['Rim'], col=col,
                                 segments=20))
        parts.append(ck.cylinder(name + '_cap', rim_r * 0.13, 0.02, (face_x + 0.016, 0, 0), m['Chrome'], col=col,
                                 segments=16))
        for k in range(5):
            a = 2 * math.pi * (k + 0.5) / 5
            parts.append(ck.cylinder(name + f'_nut{k}', 0.011, 0.02, (face_x + 0.012, -math.sin(a) * rim_r * 0.2,
                                     math.cos(a) * rim_r * 0.2), m['Chrome'], col=col, segments=6))
        spokes = {
            'tenspoke': [(2 * math.pi * (k // 2) / 5 + (0.12 if k % 2 else -0.12), 0.022) for k in range(10)],
            'fivespoke': [(2 * math.pi * k / 5, 0.055) for k in range(5)],
            'mesh': [(2 * math.pi * k / 16, 0.012) for k in range(16)],
            'turbine': [(2 * math.pi * k / 12, 0.03) for k in range(12)],
        }[style]
        for k, (a, width) in enumerate(spokes):
            s = ck.box(name + f'_spoke{k}', (0.022, width, rim_r * 0.74), (0, 0, 0), m['Rim'], col=col)
            twist = math.radians(30) if style == 'turbine' else math.radians(18 * (1 if k % 2 else -1)) if style == 'mesh' else 0
            s.rotation_euler = (a, 0, twist)
            s.location = (face_x - 0.008, -math.sin(a) * rim_r * 0.55, math.cos(a) * rim_r * 0.55)
            parts.append(s)
        if style == 'mesh':
            for k in range(16):  # second, crossing set of wires
                a = 2 * math.pi * (k + 0.5) / 16
                s = ck.box(name + f'_wire{k}', (0.02, 0.012, rim_r * 0.74), (0, 0, 0), m['Rim'], col=col)
                s.rotation_euler = (a, 0, math.radians(-18 if k % 2 else 18))
                s.location = (face_x - 0.012, -math.sin(a) * rim_r * 0.55, math.cos(a) * rim_r * 0.55)
                parts.append(s)
        if style == 'turbine':
            parts.append(ck.cylinder(name + '_face', rim_r * 0.92, 0.012, (face_x - 0.025, 0, 0), m['Rim'], col=col,
                                     segments=32))
    parts.append(ck.cylinder(name + '_disc', rim_r * 0.84, 0.024, (-0.025, 0, 0), m['Chrome'], col=col,
                             segments=12 if car.lod else 32))
    parts.append(ck.cylinder(name + '_disc_hat', rim_r * 0.42, 0.05, (-0.005, 0, 0), m['Trim'], col=col, segments=20))
    bpy.context.view_layer.update()
    ck.apply_transforms(parts)
    return ck.join(parts, name)
