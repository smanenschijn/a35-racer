"""
Landmarks along the A35 Hengelo -> Enschede, built from many small named parts.

Conventions: metres, Z up, origin at ground level in the middle of the site, and the side that
faces the motorway points to -Y (the game turns each landmark to face the road).
Neon signs use emissive materials so they glow (bloom) in the sunset.
"""

import math

import bmesh
import bpy
from mathutils import Vector

import carkit as ck


def materials():
    M = {}

    def mk(name, color, **kw):
        M[name] = ck.material(name, color, **kw)

    mk('Brick', (0.26, 0.1, 0.065), roughness=0.92)
    mk('DarkBrick', (0.1, 0.06, 0.05), roughness=0.9)
    mk('Concrete', (0.52, 0.51, 0.49), roughness=0.9)
    mk('Facade', (0.07, 0.12, 0.17), metallic=0.6, roughness=0.12)
    mk('Steel', (0.6, 0.62, 0.66), metallic=0.9, roughness=0.3)
    mk('White', (0.82, 0.82, 0.8), roughness=0.5)
    mk('Dark', (0.03, 0.03, 0.035), roughness=0.7)
    mk('TwenteRed', (0.55, 0.02, 0.025), roughness=0.5)
    mk('Seats', (0.42, 0.015, 0.02), roughness=0.6)
    mk('Pitch', (0.06, 0.22, 0.04), roughness=1.0)
    mk('Line', (0.9, 0.9, 0.9), roughness=0.8)
    mk('Tank', (0.75, 0.76, 0.78), metallic=0.95, roughness=0.18)
    mk('Orange', (0.95, 0.32, 0.02), roughness=0.4)
    mk('Window', (0.9, 0.7, 0.45), roughness=0.3, emission=(1.0, 0.72, 0.42), strength=1.6)
    mk('NeonPink', (1.0, 0.2, 0.6), emission=(1.0, 0.15, 0.55), strength=7.0)
    mk('NeonWhite', (1, 1, 1), emission=(1.0, 0.97, 0.9), strength=5.0)
    mk('NeonGreen', (0.1, 0.8, 0.3), emission=(0.15, 1.0, 0.35), strength=6.0)
    mk('NeonOrange', (1.0, 0.45, 0.05), emission=(1.0, 0.42, 0.04), strength=7.0)
    mk('NeonRed', (1.0, 0.1, 0.08), emission=(1.0, 0.08, 0.05), strength=6.0)
    mk('Glass', (0.03, 0.05, 0.06), metallic=0.9, roughness=0.05)
    mk('BottleGlass', (0.04, 0.32, 0.1), roughness=0.08, emission=(0.02, 0.25, 0.06), strength=0.6)
    ck.set_transparent(M['BottleGlass'], 0.82)
    mk('Porcelain', (0.92, 0.92, 0.9), roughness=0.25)
    mk('HullBlack', (0.025, 0.03, 0.04), roughness=0.6)
    mk('HullRed', (0.5, 0.03, 0.03), roughness=0.6)
    mk('DeckGreen', (0.08, 0.2, 0.1), roughness=0.7)
    mk('Tyre', (0.012, 0.012, 0.012), roughness=0.92)
    mk('Blue', (0.02, 0.08, 0.4), roughness=0.5)
    # Nijverdal
    mk('RedBrick', (0.42, 0.12, 0.055), roughness=0.9)
    mk('Panel', (0.16, 0.17, 0.17), roughness=0.45, metallic=0.3)
    mk('Sand', (0.62, 0.5, 0.33), roughness=0.85)
    mk('SandBrick', (0.6, 0.42, 0.2), roughness=0.9)
    mk('Cladding', (0.5, 0.52, 0.56), metallic=0.65, roughness=0.32)
    mk('LogoBlue', (0.04, 0.16, 0.8), roughness=0.3, emission=(0.1, 0.3, 1.0), strength=2.5)
    mk('Water', (0.08, 0.42, 0.75), roughness=0.05, emission=(0.05, 0.3, 0.55), strength=0.4)
    mk('Grass', (0.07, 0.22, 0.04), roughness=1.0)
    mk('SlideRed', (0.6, 0.02, 0.08), roughness=0.3, coat=1.0)
    mk('Solar', (0.015, 0.03, 0.1), metallic=0.7, roughness=0.15)
    mk('KswBrick', (0.12, 0.065, 0.06), roughness=0.9)
    mk('Cream', (0.74, 0.6, 0.38), roughness=0.7)
    mk('OrangeBrick', (0.62, 0.22, 0.06), roughness=0.8)
    mk('Slate', (0.1, 0.11, 0.13), roughness=0.6)
    mk('Pine', (0.025, 0.08, 0.03), roughness=1.0)
    mk('DoorGreen', (0.02, 0.07, 0.045), roughness=0.5)
    return M


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

class Site:
    """Collects parts for one landmark under a root empty."""

    def __init__(self, name):
        ck.reset_scene()
        self.m = materials()
        self.col = ck.collection(name)
        self.root = bpy.data.objects.new(name, None)
        self.col.objects.link(self.root)
        self.parts = []

    def add(self, o):
        self.parts.append(o)
        return o

    def box(self, name, size, loc, mat, bevel=0.0, rot=(0, 0, 0)):
        return self.add(ck.box(name, size, loc, self.m[mat], col=self.col, bevel_width=bevel, rotation=rot))

    def cyl(self, name, r, h, loc, mat, segments=24, r2=None, axis='Z'):
        return self.add(ck.cylinder(name, r, h, loc, self.m[mat], col=self.col, axis=axis, segments=segments,
                                    radius2=r2))

    def text(self, name, body, size, loc, mat, rot=(math.pi / 2, 0, 0), extrude=0.15, align='CENTER'):
        curve = bpy.data.curves.new(name, 'FONT')
        curve.body = body
        curve.size = size
        curve.align_x = align
        curve.align_y = 'BOTTOM'
        curve.extrude = extrude
        try:
            curve.font = bpy.data.fonts.load('/System/Library/Fonts/Supplemental/Arial Black.ttf', check_existing=True)
        except Exception:
            pass
        tmp = bpy.data.objects.new(name + '_tmp', curve)
        self.col.objects.link(tmp)
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(tmp)
        me.materials.clear()
        me.materials.append(self.m[mat])
        obj = bpy.data.objects.new(name, me)
        self.col.objects.link(obj)
        obj.location = loc
        obj.rotation_euler = rot
        return self.add(obj)

    def windows(self, name, center, width, height, cols, rows, mat='Window', face='-Y', size=(0.62, 0.55),
                lit=0.55, seed=1):
        """A grid of window panes on one facade, merged into a single mesh. Some are lit."""
        import random
        rnd = random.Random(seed)
        verts, faces, fmats = [], [], []
        cx, cy, cz = center
        for r in range(rows):
            for c in range(cols):
                u = (c + 0.5) / cols - 0.5
                v = (r + 0.5) / rows - 0.5
                w, h = width / cols * size[0], height / rows * size[1]
                pu, pv = u * width, v * height
                quad = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
                base = len(verts)
                for qu, qv in quad:
                    if face == '-Y':
                        verts.append((cx + pu + qu, cy - 0.03, cz + pv + qv))
                    elif face == '+Y':
                        verts.append((cx - pu - qu, cy + 0.03, cz + pv + qv))
                    elif face == '+X':
                        verts.append((cx + 0.03, cy + pu + qu, cz + pv + qv))
                    else:
                        verts.append((cx - 0.03, cy - pu - qu, cz + pv + qv))
                faces.append((base, base + 1, base + 2, base + 3))
                fmats.append(0 if rnd.random() < lit else 1)
        return self.add(ck.mesh_object(name, verts, faces, [self.m[mat], self.m['Glass']], face_mats=fmats,
                                       col=self.col))

    def prism(self, name, poly, y0, y1, mat):
        return self.add(prism_xz(name, poly, y0, y1, self.m[mat], self.col))

    def objects_rotate_last(self, angle):
        self.parts[-1].rotation_euler = (0, 0, angle)

    def finish(self):
        for o in self.parts:
            if o.parent is None:
                o.parent = self.root
        return self.root


def prism_xz(name, poly, y0, y1, mat, col):
    """Extrude an (x, z) outline along Y from y0 to y1: facades with arches, gables, window shapes."""
    n = len(poly)
    verts = [(x, y0, z) for x, z in poly] + [(x, y1, z) for x, z in poly]
    faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    obj = ck.mesh_object(name, verts, faces, [mat], col=col)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return ck.mark_sharp(obj, 35)


def arc(cx, cz, r, a0, a1, steps=16):
    return [(cx + r * math.cos(a0 + (a1 - a0) * k / steps), cz + r * math.sin(a0 + (a1 - a0) * k / steps))
            for k in range(steps + 1)]


def round_top(cx, half, z0, z1, steps=16):
    """Outline of an opening with a semicircular head: z0 = sill, z1 = crown."""
    zs = z1 - half
    return [(cx - half, z0), (cx + half, z0)] + arc(cx, zs, half, 0, math.pi, steps)


def arch_ring(cx, zs, r_in, r_out, steps=16):
    """A half ring (brick arch over a window)."""
    return arc(cx, zs, r_out, 0, math.pi, steps) + arc(cx, zs, r_in, math.pi, 0, steps)


def arched_window(S, name, cx, z0, z1, w, yf, arch_mat=None, glass='Glass', frame='White'):
    """Round-headed window on a facade whose front face is at y = yf (facing -Y)."""
    S.prism(name + '_frame', round_top(cx, w / 2 + 0.15, z0 - 0.15, z1 + 0.15), yf - 0.06, yf + 0.05, frame)
    S.prism(name + '_glass', round_top(cx, w / 2, z0, z1), yf - 0.1, yf - 0.06, glass)
    S.box(name + '_mullion', (0.1, 0.06, z1 - z0 - w / 2), (cx, yf - 0.12, z0 + (z1 - z0 - w / 2) / 2), frame)
    S.box(name + '_transom', (w, 0.06, 0.1), (cx, yf - 0.12, z1 - w / 2), frame)
    if arch_mat:
        S.prism(name + '_arch', arch_ring(cx, z1 - w / 2, w / 2 + 0.15, w / 2 + 0.6), yf - 0.15, yf + 0.05, arch_mat)


def diamonds(name, x0, x1, step, z, size, y, mat, col):
    """A row of small diamond tiles facing -Y in one mesh (brick friezes)."""
    verts, faces = [], []
    x = x0
    while x <= x1:
        b = len(verts)
        verts += [(x, y, z - size), (x + size, y, z), (x, y, z + size), (x - size, y, z)]
        faces.append((b, b + 1, b + 2, b + 3))
        x += step
    return ck.mesh_object(name, verts, faces, [mat], col=col)


def lathe_z(profile, segments=32):
    """Spin an (r, z) profile around Z. Returns bmesh."""
    bm = bmesh.new()
    rings = []
    for k in range(segments):
        a = 2 * math.pi * k / segments
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, z in profile])
    for k in range(segments):
        r0, r1 = rings[k], rings[(k + 1) % segments]
        for i in range(len(profile) - 1):
            bm.faces.new((r0[i], r1[i], r1[i + 1], r0[i + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ---------------------------------------------------------------------------
# Metropool Hengelo + Stork hall (Hart van Zuid)
# ---------------------------------------------------------------------------

def metropool():
    S = Site('Metropool')
    S.box('plaza', (150, 64, 0.2), (0, -6, 0.1), 'Concrete')
    S.box('hall', (64, 40, 15), (6, 12, 7.5), 'DarkBrick', bevel=0.2)
    S.box('fly_tower', (22, 18, 24), (14, 16, 12), 'Brick', bevel=0.2)
    S.box('foyer', (52, 8, 9), (6, -12, 4.5), 'Facade')
    S.box('foyer_roof', (56, 11, 0.7), (6, -12.5, 9.35), 'White', bevel=0.1)
    for k in range(7):
        S.box(f'mullion{k}', (0.3, 0.3, 9), (6 - 24 + k * 8, -16.1, 4.5), 'Dark')
    S.text('sign', 'METROPOOL', 4.2, (6, -18.0, 9.9), 'NeonPink', extrude=0.35)
    for k in range(6):
        S.box(f'light_strip{k}', (0.35, 0.25, 12), (6 - 26 + k * 10.4, -8.1, 7.0), 'NeonWhite')
    S.windows('fly_windows', (14, 6.9, 18), 18, 8, 6, 3, face='-Y', seed=3)
    S.box('canopy', (14, 6, 0.4), (6, -19, 4.2), 'White', bevel=0.05)
    for x in (0, 12):
        S.cyl(f'canopy_post{x}', 0.18, 4.2, (x, -21.5, 2.1), 'Steel', segments=10)

    # Old Stork machine hall with a saw-tooth roof and chimney (Hart van Zuid).
    hx = -60
    S.box('stork_walls', (60, 40, 9), (hx, 10, 4.5), 'Brick', bevel=0.15)
    for k in range(6):
        y = 10 - 20 + k * (40 / 6) + 40 / 12
        prism = S.add(ck.extrude_yz(f'saw{k}', [(-3.3, 0), (3.3, 0), (3.3, 4.2)], -30, 30, S.m['Dark'], col=S.col))
        prism.location = (hx, y, 9)
        S.box(f'saw_glass{k}', (59, 0.2, 4.0), (hx, y + 3.25, 11.0), 'Window')
    S.windows('stork_windows', (hx, -10.05, 4.5), 54, 6, 12, 2, face='-Y', size=(0.7, 0.75), lit=0.4, seed=5)
    S.cyl('chimney', 2.0, 36, (hx - 24, 26, 18), 'Brick', segments=20, r2=1.4)
    for z in (30, 33):
        S.cyl(f'chimney_band{z}', 1.62, 0.8, (hx - 24, 26, z), 'White', segments=20)
    S.text('stork_sign', 'HART VAN ZUID', 2.0, (hx, -10.2, 9.6), 'NeonWhite', extrude=0.15)
    return S.finish()


# ---------------------------------------------------------------------------
# Universiteit Twente
# ---------------------------------------------------------------------------

def utwente():
    S = Site('UTwente')
    S.box('lawn_path', (140, 8, 0.15), (0, -24, 0.08), 'Concrete')
    # Long teaching building with ribbon windows.
    S.box('building_a', (90, 16, 15), (0, 0, 7.5), 'White', bevel=0.15)
    for r in range(4):
        z = 2.2 + r * 3.6
        S.box(f'band_front{r}', (88, 0.2, 1.7), (0, -8.05, z), 'Facade')
        S.box(f'band_back{r}', (88, 0.2, 1.7), (0, 8.05, z), 'Facade')
    S.windows('a_lit', (0, -8.1, 7.6), 88, 14.4, 30, 4, face='-Y', size=(0.9, 0.42), lit=0.35, seed=7)
    S.box('roof_a', (91, 17, 0.5), (0, 0, 15.25), 'Concrete')
    S.text('sign_ut', 'UNIVERSITEIT TWENTE', 2.6, (0, -8.4, 15.6), 'NeonWhite', extrude=0.2)
    # Round tower
    tower = S.add(ck.bm_object('tower', lathe_z([(0.01, 0), (7, 0), (7, 40), (6.5, 40.6), (0.01, 40.6)], 36),
                               [S.m['White']], col=S.col, smooth=True, location=(-52, 14, 0)))
    for k in range(9):
        S.add(ck.bm_object(f'tower_ring{k}', lathe_z([(7.02, 3 + k * 4.2), (7.02, 4.6 + k * 4.2)], 36),
                           [S.m['Facade']], col=S.col, smooth=True, location=(-52, 14, 0)))
    S.text('tower_logo', 'UT', 5, (-52, 6.8, 31), 'NeonWhite', extrude=0.3)
    # Glass cube
    S.box('cube', (30, 30, 24), (58, 18, 12), 'Facade')
    for k in range(7):
        S.box(f'cube_v{k}', (0.35, 0.35, 24), (58 - 15 + k * 5, 2.9, 12), 'Steel')
        S.box(f'cube_h{k}', (30, 0.35, 0.35), (58, 2.9, 3 + k * 3.5), 'Steel')
    S.windows('cube_lit', (58, 2.8, 12), 28, 22, 6, 6, face='-Y', size=(0.8, 0.8), lit=0.3, seed=11)
    # Campus entrance sign
    S.box('entrance_wall', (24, 1.2, 2.6), (-20, -28, 1.3), 'Concrete', bevel=0.05)
    S.text('entrance_text', 'UNIVERSITY OF TWENTE.', 1.1, (-20, -28.65, 0.75), 'Dark', extrude=0.06)
    return S.finish()


# ---------------------------------------------------------------------------
# Grolsj Veste (stadium)
# ---------------------------------------------------------------------------

def rounded_rect(u, hw, hh, r):
    """Point and outward normal at perimeter fraction u of a rounded rectangle."""
    straight_x, straight_y = 2 * (hw - r), 2 * (hh - r)
    arc = math.pi * r / 2
    per = 2 * straight_x + 2 * straight_y + 4 * arc
    d = (u % 1.0) * per
    segs = [('s', straight_x, (-(hw - r), -hh), (1, 0), (0, -1)), ('a', arc, (hw - r, -(hh - r)), -math.pi / 2),
            ('s', straight_y, (hw, -(hh - r)), (0, 1), (1, 0)), ('a', arc, (hw - r, hh - r), 0.0),
            ('s', straight_x, (hw - r, hh), (-1, 0), (0, 1)), ('a', arc, (-(hw - r), hh - r), math.pi / 2),
            ('s', straight_y, (-hw, hh - r), (0, -1), (-1, 0)), ('a', arc, (-(hw - r), -(hh - r)), math.pi)]
    for seg in segs:
        length = seg[1]
        if d <= length or seg is segs[-1]:
            if seg[0] == 's':
                (x0, y0), (dx, dy), n = seg[2], seg[3], seg[4]
                return (x0 + dx * d, y0 + dy * d), n
            (cx, cy), a0 = seg[2], seg[3]
            a = a0 + d / r
            return (cx + r * math.cos(a), cy + r * math.sin(a)), (math.cos(a), math.sin(a))
        d -= length
    raise ValueError


def ring_mesh(name, profile, hw, hh, r, mat, col, n=160):
    """Sweep an (offset, z) profile around a rounded rectangle."""
    verts, faces = [], []
    m = len(profile)
    for k in range(n):
        (x, y), (nx, ny) = rounded_rect(k / n, hw, hh, r)
        for o, z in profile:
            verts.append((x + nx * o, y + ny * o, z))
    for k in range(n):
        a, b = k * m, ((k + 1) % n) * m
        for i in range(m - 1):
            faces.append((a + i, b + i, b + i + 1, a + i + 1))
    obj = ck.mesh_object(name, verts, faces, [mat], col=col)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return ck.mark_sharp(obj, 35)


def veste():
    S = Site('Veste')
    hw, hh, r = 60, 42, 14   # inner edge of the stands, around the pitch
    S.box('pitch', (105, 68, 0.3), (0, 0, 0.15), 'Pitch')
    for name, size, loc in (('line_side1', (105, 0.2, 0.02), (0, -34, 0.31)), ('line_side2', (105, 0.2, 0.02), (0, 34, 0.31)),
                            ('line_end1', (0.2, 68, 0.02), (-52.5, 0, 0.31)), ('line_end2', (0.2, 68, 0.02), (52.5, 0, 0.31)),
                            ('line_half', (0.2, 68, 0.02), (0, 0, 0.31))):
        S.box(name, size, loc, 'Line')
    S.add(ck.bm_object('centre_circle', lathe_z([(9.0, 0.31), (9.2, 0.31)], 48), [S.m['Line']], col=S.col))
    S.add(ring_mesh('stands', [(0, 1.5), (14, 10), (16, 11), (34, 22)], hw, hh, r, S.m['Seats'], S.col))
    S.add(ring_mesh('concourse', [(34, 22), (37, 22)], hw, hh, r, S.m['Concrete'], S.col))
    S.add(ring_mesh('facade', [(37, 22), (37.3, 0)], hw, hh, r, S.m['TwenteRed'], S.col))
    S.add(ring_mesh('facade_band1', [(37.4, 6.5), (37.4, 8.0)], hw, hh, r, S.m['White'], S.col))
    S.add(ring_mesh('facade_band2', [(37.4, 15.0), (37.4, 16.5)], hw, hh, r, S.m['White'], S.col))
    S.add(ring_mesh('roof', [(39, 29.5), (8, 31), (8, 30.2), (39, 28.6), (39, 29.5)], hw, hh, r, S.m['White'], S.col))
    S.add(ring_mesh('roof_lights', [(8.2, 30.1), (9.2, 30.0)], hw, hh, r, S.m['NeonWhite'], S.col))
    # Columns and roof trusses.
    n = 28
    for k in range(n):
        (x, y), (nx, ny) = rounded_rect(k / n, hw, hh, r)
        px, py = x + nx * 37.6, y + ny * 37.6
        S.cyl(f'column{k}', 0.45, 29, (px, py, 14.5), 'White', segments=10)
        tx, ty = x + nx * 23, y + ny * 23
        truss = S.box(f'truss{k}', (0.5, 31, 1.6), (tx, ty, 31.6), 'Steel')
        truss.rotation_euler = (0, 0, math.atan2(ny, nx) + math.pi / 2)
    # Big name on the side facing the motorway.
    S.text('sign', 'GROLSJ VESTE', 7.5, (0, -(hh + 37.6) - 0.4, 10.5), 'NeonWhite', extrude=0.4)
    S.text('sign_fc', 'FC TWENTE', 3.4, (0, -(hh + 37.6) - 0.4, 3.0), 'NeonRed', extrude=0.25)
    # Floodlight masts at the corners.
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (hw + 28), sy * (hh + 28)
            S.cyl(f'mast{sx}{sy}', 0.7, 40, (x, y, 20), 'Steel', segments=10, r2=0.45)
            S.box(f'mast_lamps{sx}{sy}', (6, 1.2, 3.2), (x, y, 41), 'NeonWhite',
                  rot=(math.radians(-25) * sy, 0, math.atan2(-y, -x) + math.pi / 2))
    S.box('car_park', (250, 30, 0.12), (0, -(hh + 60), 0.06), 'Concrete')
    return S.finish()


# ---------------------------------------------------------------------------
# Grolsj brewery (Boekelo)
# ---------------------------------------------------------------------------

def brouwerij():
    S = Site('Brouwerij')
    S.box('yard', (170, 90, 0.15), (0, 10, 0.08), 'Concrete')
    S.box('brewhouse', (70, 34, 16), (-25, 8, 8), 'Brick', bevel=0.2)
    S.box('brewhouse_glass', (58, 0.4, 7), (-25, -9.1, 9.5), 'Facade')
    S.windows('brewhouse_lit', (-25, -9.3, 9.5), 56, 6, 14, 1, face='-Y', size=(0.85, 0.8), lit=0.7, seed=13)
    S.box('brewhouse_roof', (72, 36, 0.6), (-25, 8, 16.3), 'Concrete')
    S.text('sign', 'GROLSJ', 7.0, (-35, -9.6, 16.8), 'NeonGreen', extrude=0.4)
    # Fermentation tank farm
    for i in range(4):
        for j in range(3):
            x, y = 22 + i * 8.5, 0 + j * 8.5
            S.cyl(f'tank_{i}{j}', 3.4, 19, (x, y, 9.5 + 1.2), 'Tank', segments=28)
            S.cyl(f'tank_cone_{i}{j}', 3.4, 2.4, (x, y, 21.4), 'Tank', segments=28, r2=0.6)
            S.cyl(f'tank_leg_{i}{j}', 1.2, 1.2, (x, y, 0.6), 'Concrete', segments=12)
    S.box('catwalk', (36, 1.4, 0.3), (34.75, -4.5, 17), 'Steel')
    S.box('catwalk_rail', (36, 0.08, 1.1), (34.75, -5.2, 17.6), 'Steel')
    # Silos and chimney
    for k, x in enumerate((64, 74)):
        S.cyl(f'silo{k}', 4.2, 30, (x, 22, 15), 'White', segments=28)
        S.cyl(f'silo_top{k}', 4.2, 2, (x, 22, 31), 'White', segments=28, r2=1.0)
    S.cyl('chimney', 2.2, 46, (-62, 30, 23), 'Brick', segments=20, r2=1.5)
    for z in (38, 42):
        S.cyl(f'chimney_band{z}', 1.75, 1.0, (-62, 30, z), 'White', segments=20)
    S.cyl('chimney_beacon', 0.5, 0.6, (-62, 30, 46.3), 'NeonRed', segments=10)
    # Pipe bridge from the brewhouse to the tanks
    for k, z in enumerate((12.0, 12.8, 13.6)):
        S.cyl(f'pipe{k}', 0.32, 30, (2, 4 + k * 0.9, z), 'Steel', segments=10, axis='X')
    for x in (-5, 5, 15):
        S.box(f'pipe_post{x}', (0.4, 3, 13), (x, 4.9, 6.5), 'Steel')
    # Giant swing-top bottle (beugelfles) facing the road.
    bx, by = 2, -18
    body = lathe_z([(0.01, 0), (2.5, 0), (2.6, 0.4), (2.6, 9.5), (2.2, 12), (1.05, 15.5), (0.95, 18.2),
                    (1.05, 18.6), (0.95, 19.0), (0.01, 19.0)], 40)
    S.add(ck.bm_object('bottle', body, [S.m['BottleGlass']], col=S.col, smooth=True, location=(bx, by, 0.3)))
    S.add(ck.bm_object('bottle_label', lathe_z([(2.63, 4.0), (2.63, 8.0)], 40), [S.m['White']], col=S.col,
                       smooth=True, location=(bx, by, 0.3)))
    S.text('bottle_label_text', 'GROLSJ', 1.25, (bx, by - 2.66, 5.3), 'NeonGreen', extrude=0.06)
    S.add(ck.bm_object('bottle_stopper', lathe_z([(0.01, 0), (0.95, 0), (1.0, 0.35), (0.85, 1.1), (0.01, 1.2)], 24),
                       [S.m['Porcelain']], col=S.col, smooth=True, location=(bx, by, 19.35)))
    for sx in (-1, 1):  # the wire clasp
        S.box(f'bottle_wire{sx}', (0.08, 0.08, 2.2), (bx + sx * 1.05, by, 18.6), 'Steel')
        S.box(f'bottle_lever{sx}', (0.1, 1.6, 0.1), (bx + sx * 1.05, by + 0.4, 17.6), 'Steel',
              rot=(math.radians(25), 0, 0))
    S.box('bottle_plinth', (7, 7, 0.6), (bx, by, 0.3), 'Concrete', bevel=0.1)
    # Scale the whole bottle up around its plinth so it towers over the brewhouse.
    F = 1.6
    for o in S.parts:
        if o.name.startswith('bottle'):
            o.location = Vector((bx + (o.location.x - bx) * F, by + (o.location.y - by) * F, o.location.z * F))
            o.scale = (o.scale[0] * F, o.scale[1] * F, o.scale[2] * F)
    return S.finish()


# ---------------------------------------------------------------------------
# Thuisbesteld HQ (De Ruyterlaan, Enschede)
# ---------------------------------------------------------------------------

def thuisbesteld():
    S = Site('Thuisbesteld')
    S.box('forecourt', (80, 40, 0.15), (0, -8, 0.08), 'Concrete')
    S.box('podium', (50, 30, 6), (0, 6, 3), 'White', bevel=0.1)
    S.box('podium_glass', (46, 0.3, 4.4), (0, -9.1, 2.6), 'Facade')
    S.windows('podium_lit', (0, -9.3, 2.6), 44, 4, 11, 1, face='-Y', size=(0.85, 0.85), lit=0.8, seed=17)
    S.box('tower', (30, 22, 34), (0, 8, 23), 'Facade')
    S.windows('tower_lit', (0, -3.1, 23), 28, 32, 10, 10, face='-Y', size=(0.75, 0.6), lit=0.45, seed=19)
    for k in range(13):  # orange vertical fins
        S.box(f'fin{k}', (0.5, 1.6, 34), (-15 + k * 2.5, -3.6, 23), 'Orange')
    S.box('tower_roof', (31, 23, 1.0), (0, 8, 40.5), 'White')
    S.text('sign', 'Thuisbesteld', 4.2, (2.5, -3.9, 41.2), 'NeonOrange', extrude=0.35)
    # House-shaped logo next to the name
    logo = [(0, 0), (3.6, 0), (3.6, 2.6), (1.8, 4.3), (0, 2.6)]
    house = S.add(ck.extrude_yz('logo', [(x - 1.8, z) for x, z in logo], -0.2, 0.2, S.m['NeonOrange'], col=S.col))
    house.rotation_euler = (0, 0, math.pi / 2)
    house.location = (-13.5, -3.9, 41.2)
    S.box('canopy', (16, 6, 0.4), (0, -12, 4.6), 'Orange', bevel=0.05)
    # Delivery scooters lined up out front.
    for k in range(6):
        x = -14 + k * 2.2
        S.box(f'scooter{k}', (0.5, 1.4, 0.5), (x, -20, 0.55), 'Orange', bevel=0.08)
        S.box(f'scooter_box{k}', (0.55, 0.55, 0.5), (x, -19.6, 1.1), 'Orange', bevel=0.05)
        for dy in (-0.55, 0.55):
            S.cyl(f'scooter_wheel{k}{int(dy * 10)}', 0.22, 0.12, (x, -20 + dy, 0.22), 'Tyre', segments=12, axis='X')
        S.box(f'scooter_bar{k}', (0.6, 0.06, 0.06), (x, -20.6, 1.15), 'Dark')
    return S.finish()


# ---------------------------------------------------------------------------
# Inland barge for the Twentekanaal (length along X)
# ---------------------------------------------------------------------------

def barge():
    S = Site('Barge')
    L, W = 80, 9.5
    # Hull: box with a raked bow.
    verts, faces = [], []
    sec = [(-L / 2, 1.0), (L / 2 - 8, 1.0), (L / 2, 0.55)]  # x, relative width
    for x, wf in sec:
        for y, z in ((-W / 2 * wf, -1.5), (W / 2 * wf, -1.5), (W / 2 * wf, 3.0), (-W / 2 * wf, 3.0)):
            verts.append((x, y, z))
    for i in range(len(sec) - 1):
        a, b = i * 4, (i + 1) * 4
        for k in range(4):
            faces.append((a + k, a + (k + 1) % 4, b + (k + 1) % 4, b + k))
    faces.append((3, 2, 1, 0))
    faces.append((8, 9, 10, 11))
    hull = S.add(ck.mesh_object('hull', verts, faces, [S.m['HullBlack']], col=S.col))
    bm = bmesh.new()
    bm.from_mesh(hull.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(hull.data)
    bm.free()
    S.box('stripe', (L - 6, W + 0.08, 0.5), (-3, 0, 2.5), 'HullRed')
    S.box('hatches', (52, W - 2, 1.4), (0, 0, 3.6), 'DeckGreen', bevel=0.3)
    for k in range(13):
        S.box(f'hatch_rib{k}', (0.3, W - 1.9, 1.5), (-25 + k * 4.2, 0, 3.65), 'Dark')
    S.box('wheelhouse', (7, 7, 3.2), (-33, 0, 4.6), 'White', bevel=0.1)
    S.box('wheelhouse_glass', (7.1, 7.1, 1.1), (-33, 0, 5.4), 'Glass')
    S.box('wheelhouse_roof', (8, 8, 0.3), (-33, 0, 6.35), 'White')
    S.box('cabin', (10, 8, 2.2), (-34, 0, 4.1), 'White', bevel=0.1)
    S.cyl('mast', 0.12, 4, (-33, 0, 8.4), 'Steel', segments=8)
    S.cyl('nav_light', 0.25, 0.3, (-33, 0, 10.5), 'NeonWhite', segments=10)
    S.box('deck_car', (4.2, 1.8, 1.3), (-38, 0, 5.85), 'TwenteRed', bevel=0.2)
    S.text('name_stern', 'TWENTEVAART', 1.0, (-L / 2 - 0.05, 0, 0.6), 'White', rot=(math.pi / 2, 0, -math.pi / 2),
           extrude=0.03)
    return S.finish()


# ---------------------------------------------------------------------------
# Gemeentehuis Raalte
# ---------------------------------------------------------------------------

def raadhuis():
    S = Site('Raadhuis')
    S.box('square', (90, 50, 0.15), (0, -6, 0.08), 'Concrete')
    S.box('hall', (44, 16, 11), (0, 6, 5.5), 'Brick', bevel=0.12)
    roof = S.add(ck.extrude_yz('roof', [(-8.6, 0), (8.6, 0), (0, 7.5)], -22.6, 22.6, S.m['Dark'], col=S.col))
    roof.location = (0, 6, 11)
    S.windows('hall_windows', (0, -2.05, 5.6), 40, 8, 12, 2, face='-Y', size=(0.55, 0.62), lit=0.6, seed=23)
    for k in range(12):  # white frames
        S.box(f'frame{k}', (1.9, 0.12, 0.15), (-20 + 1.66 + k * 3.33, -2.1, 7.4), 'White')
    # Clock tower with spire over the entrance.
    S.box('tower', (7, 7, 22), (0, -1.5, 11), 'Brick', bevel=0.1)
    S.box('tower_band', (7.3, 7.3, 0.6), (0, -1.5, 18), 'White')
    S.add(ck.bm_object('spire', lathe_z([(0.01, 0), (4.6, 0), (0.25, 9), (0.01, 9.4)], 4), [S.m['Dark']], col=S.col,
                       location=(0, -1.5, 22)))
    S.objects_rotate_last(math.pi / 4)
    S.cyl('clock', 1.5, 0.2, (0, -5.1, 19.6), 'White', segments=28, axis='Y')
    S.box('clock_hand1', (0.12, 0.05, 1.1), (0, -5.25, 19.9), 'Dark')
    S.box('clock_hand2', (0.8, 0.05, 0.12), (0.3, -5.25, 19.6), 'Dark')
    S.box('door', (3, 0.3, 4), (0, -5.1, 2), 'Dark')
    S.text('sign', 'GEMEENTEHUIS', 1.0, (0, -5.2, 4.6), 'NeonWhite', extrude=0.05)
    # Flag pole with the Dutch flag.
    S.cyl('flagpole', 0.12, 12, (-16, -12, 6), 'White', segments=8)
    for k, col_ in enumerate(('TwenteRed', 'White', 'Blue')):
        S.box(f'flag{k}', (2.4, 0.04, 0.5), (-14.8, -12, 11.4 - k * 0.5), col_)
    return S.finish()


# ---------------------------------------------------------------------------
# Watertoren Wierden
# ---------------------------------------------------------------------------

def watertoren():
    S = Site('Watertoren')
    S.box('base', (24, 24, 0.2), (0, 0, 0.1), 'Concrete')
    S.add(ck.bm_object('shaft', lathe_z([(0.01, 0), (5.2, 0), (4.6, 30), (0.01, 30)], 8), [S.m['Brick']], col=S.col,
                       location=(0, 0, 0)))
    for k in range(5):
        S.add(ck.bm_object(f'band{k}', lathe_z([(5.25 - k * 0.12, 5 + k * 5.5), (5.2 - k * 0.12, 5.6 + k * 5.5)], 8),
                           [S.m['White']], col=S.col))
    S.add(ck.bm_object('tank', lathe_z([(4.6, 30), (7.6, 31.5), (7.6, 39), (6.8, 40), (0.01, 40)], 8), [S.m['White']],
                       col=S.col))
    S.add(ck.bm_object('tank_windows', lathe_z([(7.65, 33.5), (7.65, 36.0)], 8), [S.m['Window']], col=S.col))
    S.add(ck.bm_object('roof', lathe_z([(7.2, 40), (0.6, 45), (0.01, 45.2)], 8), [S.m['Dark']], col=S.col))
    S.cyl('lantern', 0.6, 2, (0, 0, 46.2), 'NeonWhite', segments=8)
    S.box('door', (2, 0.4, 3.2), (0, -4.9, 1.6), 'Dark')
    for k in range(4):
        S.box(f'slit{k}', (0.6, 0.3, 2.2), (0, -4.7 + k * 0.08, 8 + k * 6), 'Window')
    S.text('sign', 'WIERDEN', 1.6, (0, -7.75, 36.3), 'NeonWhite', extrude=0.1)
    return S.finish()


# ---------------------------------------------------------------------------
# Heraklus stadium (Almelo), black and white
# ---------------------------------------------------------------------------

def heraklus():
    S = Site('Heraklus')
    hw, hh, r = 56, 40, 12
    S.box('pitch', (105, 68, 0.3), (0, 0, 0.15), 'Pitch')
    for k in range(9):  # mowing stripes
        S.box(f'mow{k}', (11.6, 68, 0.02), (-52.5 + 5.8 + k * 11.6, 0, 0.31), 'Line' if False else 'Pitch')
    S.add(ring_mesh('stands', [(0, 1.5), (12, 8.5), (14, 9.5), (26, 17)], hw, hh, r, S.m['Dark'], S.col))
    S.add(ring_mesh('stands_rows', [(12.2, 8.7), (13.6, 9.4)], hw, hh, r, S.m['White'], S.col))
    S.add(ring_mesh('facade', [(28, 17), (28.3, 0)], hw, hh, r, S.m['White'], S.col))
    for k, z in enumerate((4.0, 9.0, 14.0)):
        S.add(ring_mesh(f'facade_black{k}', [(28.4, z), (28.4, z + 2.2)], hw, hh, r, S.m['Dark'], S.col))
    S.add(ring_mesh('roof', [(29.5, 23), (6, 24), (6, 23.3), (29.5, 22.2), (29.5, 23)], hw, hh, r, S.m['Dark'], S.col))
    S.add(ring_mesh('roof_lights', [(6.2, 23.2), (7.2, 23.1)], hw, hh, r, S.m['NeonWhite'], S.col))
    n = 22
    for k in range(n):
        (x, y), (nx, ny) = rounded_rect(k / n, hw, hh, r)
        S.cyl(f'column{k}', 0.4, 23, (x + nx * 28.6, y + ny * 28.6, 11.5), 'White', segments=8)
    S.text('sign', 'HERAKLUS ALMELO', 5.0, (0, -(hh + 28.6) - 0.4, 6.8), 'NeonWhite', extrude=0.3)
    S.box('car_park', (200, 26, 0.12), (0, -(hh + 50), 0.06), 'Concrete')
    return S.finish()


# ---------------------------------------------------------------------------
# Nijverdal: Huis voor Cultuur en Bestuur (gemeentehuis), four big brick arches
# ---------------------------------------------------------------------------

def gemeentehuis():
    S = Site('Gemeentehuis')
    yf = -10.0                       # front face of the arches
    span, pier, zs = 10.0, 2.2, 12.5  # opening width, pier width, springline
    bay = span + pier
    W = span / 2 + pier
    xs = [-31 + k * bay for k in range(4)]
    xl, xr = xs[0] - W, xs[-1] + W
    depth = 22
    S.box('body', (xr - xl, depth, 13.6), ((xl + xr) / 2, yf + 1.5 + depth / 2, 6.8), 'Panel')
    for k, cx in enumerate(xs):
        # Brick arch frame: two piers and the round head, one outline.
        outline = [(cx - W, 0), (cx - W, zs)] + arc(cx, zs, W, math.pi, 0, 24) + [(cx + W, 0), (cx + span / 2, 0)] + \
            arc(cx, zs, span / 2, 0, math.pi, 24) + [(cx - span / 2, 0)]
        S.prism(f'arch{k}', outline, yf, yf + 2.2, 'RedBrick')
        # Barrel roof behind each arch, glass fan in the head.
        S.cyl(f'vault{k}', span / 2 + 0.4, depth - 0.5, (cx, yf + 1.5 + depth / 2, zs), 'Panel', segments=28, axis='Y')
        S.prism(f'fan{k}', [(cx - span / 2 + 0.2, zs), (cx + span / 2 - 0.2, zs)] + arc(cx, zs, span / 2 - 0.2, 0, math.pi, 20),
                yf + 1.3, yf + 1.42, 'Glass')
        for dx in (-1.7, 1.7):
            S.box(f'fan_mullion{k}{int(dx * 10)}', (0.18, 0.12, 4.2), (cx + dx, yf + 1.25, zs + 2.0), 'Panel')
        S.box(f'fan_sill{k}', (span, 0.3, 0.35), (cx, yf + 1.3, zs), 'Panel')
        # Window bands and a glass ground floor inside the arch.
        S.windows(f'win{k}', (cx, yf + 1.5, 7.9), span - 1.0, 8.6, 3, 3, face='-Y', size=(0.86, 0.62), lit=0.35, seed=31 + k)
        for z in (5.2, 8.1, 11.0):
            S.box(f'band{k}_{int(z)}', (span, 0.25, 0.5), (cx, yf + 1.4, z - 1.6), 'Panel')
        S.box(f'shop{k}', (span - 0.6, 0.12, 2.9), (cx, yf + 1.45, 1.65), 'Glass')
        # Little white stones where the arches spring and at the crown.
        S.box(f'stone{k}c', (0.6, 0.12, 0.6), (cx, yf - 0.05, zs + W - 0.6), 'White')
    for k in range(5):
        x = xs[0] - span / 2 - pier / 2 + k * bay
        S.box(f'stone_spring{k}', (0.6, 0.12, 0.6), (x, yf - 0.05, zs), 'White')
    S.box('plinth', (xr - xl, 2.6, 0.45), ((xl + xr) / 2, yf - 0.4, 0.22), 'Concrete')

    # East wing: plain brick block with grey framed windows (and a sign, for the road).
    ex0, ex1, eh = xr, xr + 27, 16.0
    S.box('east', (ex1 - ex0, depth - 0.5, eh), ((ex0 + ex1) / 2, yf + 0.5 + (depth - 0.5) / 2, eh / 2), 'RedBrick')
    for r, z in enumerate((5.4, 9.0, 12.6)):
        for c in range(6):
            x = ex0 + 2.6 + c * 4.4
            S.box(f'east_frame{r}{c}', (2.9, 0.16, 2.5), (x, yf + 0.44, z), 'Panel')
    S.windows('east_win', (ex0 + 2.6 + 2.5 * 4.4, yf + 0.5, 9.0), 6 * 4.4, 10.8, 6, 3, face='-Y', size=(0.58, 0.62),
              lit=0.45, seed=7)
    S.box('east_shop', (ex1 - ex0 - 1, 0.12, 3.0), ((ex0 + ex1) / 2, yf + 0.42, 1.7), 'Glass')
    S.box('east_cornice', (ex1 - ex0 + 0.4, depth, 0.5), ((ex0 + ex1) / 2, yf + 0.5 + depth / 2 - 0.25, eh + 0.25), 'Panel')
    S.text('sign', 'GEMEENTEHUIS', 1.5, ((ex0 + ex1) / 2, yf + 0.3, 14.0), 'NeonWhite', extrude=0.08)

    # West neighbour: lower sand-coloured block.
    wx0, wx1 = xl - 17, xl
    S.box('west', (wx1 - wx0, depth - 4, 11.5), ((wx0 + wx1) / 2, yf + 2 + (depth - 4) / 2, 5.75), 'Sand')
    S.windows('west_win', ((wx0 + wx1) / 2, yf + 2, 7.5), wx1 - wx0 - 2, 7, 5, 3, face='-Y', size=(0.6, 0.6), lit=0.5,
              seed=11)
    S.box('west_shop', (wx1 - wx0 - 1, 0.12, 2.8), ((wx0 + wx1) / 2, yf + 1.92, 1.6), 'Glass')
    S.box('square', (wx1 - wx0 + ex1 - xl + 4, 12, 0.12), ((wx0 + ex1) / 2, yf - 6, 0.06), 'Concrete')
    return S.finish()


# ---------------------------------------------------------------------------
# Nijverdal: Het Ravijn, swimming pool and sports hall by the railway
# ---------------------------------------------------------------------------

def rounded_slab(name, hw, hh, r, z0, z1, mat, col, cx=0.0, cy=0.0, n=96):
    pts = [rounded_rect(k / n, hw, hh, r)[0] for k in range(n)]
    verts = [(cx + x, cy + y, z0) for x, y in pts] + [(cx + x, cy + y, z1) for x, y in pts]
    faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    return ck.mesh_object(name, verts, faces, [mat], col=col)


def ravijn():
    from mathutils import Vector
    S = Site('Ravijn')
    yf = -20.0
    # Swimming hall: silver box, glass along the ground, light well on the roof, the blue logo.
    hx0, hx1, hh = -48.0, 30.0, 12.5
    S.box('hall', (hx1 - hx0, 46, hh), ((hx0 + hx1) / 2, yf + 23, hh / 2), 'Cladding')
    for k, z in enumerate((4.6, 7.4, 10.2)):
        S.box(f'seam{k}', (hx1 - hx0 + 0.1, 46.1, 0.08), ((hx0 + hx1) / 2, yf + 23, z), 'Panel')
    S.box('hall_glass', (hx1 - hx0 - 4, 0.12, 3.0), ((hx0 + hx1) / 2 + 2, yf - 0.05, 1.7), 'Glass')
    S.windows('hall_lit', ((hx0 + hx1) / 2 + 2, yf, 1.7), hx1 - hx0 - 4, 3.0, 18, 1, face='-Y', size=(0.9, 0.95),
              lit=0.6, seed=5)
    S.box('roof', (hx1 - hx0 + 0.6, 46.6, 0.5), ((hx0 + hx1) / 2, yf + 23, hh + 0.2), 'White')
    S.box('lightwell', (24, 16, 0.6), (-8, yf + 22, hh + 0.2), 'Concrete')
    S.box('lightwell_glass', (22, 14, 0.2), (-8, yf + 22, hh + 0.55), 'Glass')
    for k in range(3):
        S.cyl(f'dome{k}', 1.3, 0.6, (-36 + k * 16, yf + 34, hh + 0.6), 'Porcelain', segments=12)
    S.text('logo', 'Het Ravijn', 5.6, (-14, yf - 0.25, 5.6), 'LogoBlue', extrude=0.15)
    xs_ = [-34 + i * 0.5 for i in range(81)]
    S.prism('wave', [(x, 4.6 + 0.5 * math.sin(x * 0.5)) for x in xs_] +
            [(x, 4.1 + 0.5 * math.sin(x * 0.5)) for x in reversed(xs_)], yf - 0.2, yf - 0.1, 'LogoBlue')
    # Entrance block in red brick between hall and sports hall.
    S.box('entrance', (12, 12, 10.5), (36, yf + 3, 5.25), 'RedBrick')
    S.box('entrance_glass', (8, 0.12, 4.2), (36, yf - 3.05, 2.3), 'Glass')
    S.box('entrance_canopy', (10, 3, 0.3), (36, yf - 4.5, 4.6), 'Panel')
    S.text('entrance_sign', 'Het Ravijn', 1.2, (36, yf - 3.2, 6.0), 'LogoBlue', extrude=0.06)
    # Sports hall: rounded, dark brick below, sand brick band above, solar panels on the roof.
    cx, cy, w2, h2, rr, sh = 72.0, yf + 17, 30.0, 21.0, 9.0, 9.5
    S.add(rounded_slab('sports_lower', w2, h2, rr, 0, 4.2, S.m['DarkBrick'], S.col, cx, cy))
    S.add(rounded_slab('sports_upper', w2, h2, rr, 4.2, sh, S.m['SandBrick'], S.col, cx, cy))
    S.add(rounded_slab('sports_roof', w2 - 0.4, h2 - 0.4, rr - 0.4, sh, sh + 0.25, S.m['White'], S.col, cx, cy))
    S.add(rounded_slab('sports_slits', w2 + 0.05, h2 + 0.05, rr + 0.05, 2.0, 2.6, S.m['Glass'], S.col, cx, cy))
    for a, (ox, oy, rows, cols) in enumerate(((-6, -8, 6, 1), (8, 6, 5, 1))):
        for r_ in range(rows):
            S.box(f'solar{a}_{r_}', (24, 1.7, 0.1), (cx + ox, cy + oy + r_ * 2.3, sh + 0.8), 'Solar',
                  rot=(math.radians(-12), 0, 0))
    # Outdoor pools behind, with a red slide, and the pine woods of the ravine.
    S.box('lawn', (80, 46, 0.15), (-10, yf + 70, 0.07), 'Grass')
    for k, (px, py, sx_, sy_) in enumerate(((-30, yf + 64, 25, 14), (-2, yf + 70, 16, 12))):
        S.box(f'pool_edge{k}', (sx_ + 2, sy_ + 2, 0.35), (px, py, 0.17), 'Porcelain')
        S.box(f'pool{k}', (sx_, sy_, 0.4), (px, py, 0.2), 'Water')
    S.box('slide_tower', (3, 3, 9), (16, yf + 58, 4.5), 'White')
    pts = []
    for i in range(41):
        a = 1.5 * math.pi * i / 40
        pts.append(Vector((16 + 6 * math.cos(a) - 6, yf + 58 + 6 * math.sin(a), 9.0 - 8.0 * i / 40)))
    for i in range(40):
        p0, p1 = pts[i], pts[i + 1]
        seg = p1 - p0
        o = S.cyl(f'slide{i}', 0.75, seg.length + 0.1, tuple((p0 + p1) / 2), 'SlideRed', segments=10)
        o.rotation_euler = Vector((0, 0, 1)).rotation_difference(seg.normalized()).to_euler()
    import random
    rnd = random.Random(4)
    for k in range(26):
        x, y = -60 + rnd.random() * 150, yf + 95 + rnd.random() * 40
        h = 14 + rnd.random() * 9
        S.cyl(f'pine{k}', 3.2 + rnd.random(), h, (x, y, h / 2), 'Pine', segments=7, r2=0.2)
    S.box('car_park', (40, 30, 0.12), (120, yf + 15, 0.06), 'Concrete')
    return S.finish()


# ---------------------------------------------------------------------------
# Nijverdal: Koninklijke Stoomweverij (Ten Cate), gable with clock and weaving sheds
# ---------------------------------------------------------------------------

def stoomweverij():
    S = Site('Stoomweverij')
    yf, hw = -12.0, 12.0

    def top(x):
        ax = abs(x)
        return 15.0 if ax > 8 else 16.5 + 3.2 * math.cos(ax / 8 * math.pi / 2)

    gable = [(-hw, 0), (hw, 0), (hw, 15), (8, 15)] + [(8 - 16 * i / 32, top(8 - 16 * i / 32)) for i in range(33)] + \
        [(-8, 15), (-hw, 15)]
    S.prism('front', gable, yf, yf + 0.8, 'KswBrick')
    S.box('body', (2 * hw, 29, 13.5), (0, yf + 0.8 + 14.5, 6.75), 'KswBrick')
    S.prism('roof', [(-hw - 0.4, 13.5), (hw + 0.4, 13.5), (0, 18.5)], yf + 0.9, yf + 30.2, 'Slate')
    # Cream pilasters up the gable and cream bands across the facade.
    for i in range(11):
        x = -7.25 + i * 1.45
        h = top(x) - 0.7 - 15.4
        S.box(f'pilaster{i}', (0.55, 0.16, h), (x, yf - 0.06, 15.4 + h / 2), 'Cream')
    for k, (z, hgt) in enumerate(((2.7, 0.35), (8.7, 0.3), (15.1, 0.5))):
        S.box(f'cornice{k}', (2 * hw + 0.3, 0.3, hgt), (0, yf - 0.1, z), 'Cream')
    # Towers at the corners and beside the curved gable.
    for k, (x, z0, z1) in enumerate(((-11.4, 0, 21.0), (11.4, 0, 21.0), (-8.6, 13, 21.8), (8.6, 13, 21.8))):
        S.box(f'tower{k}', (1.7, 1.7, z1 - z0), (x, yf + 0.5, (z0 + z1) / 2), 'KswBrick')
        S.box(f'tower_band{k}', (1.9, 1.9, 0.3), (x, yf + 0.5, z1 - 1.2), 'Cream')
        S.box(f'tower_cap{k}', (2.1, 2.1, 0.35), (x, yf + 0.5, z1 + 0.15), 'Cream')
        S.cyl(f'tower_roof{k}', 1.3, 1.6, (x, yf + 0.5, z1 + 1.1), 'Slate', segments=4, r2=0.05)
        S.objects_rotate_last(math.pi / 4)
    # Three bays: tall windows below, round-headed windows with orange brick arches above.
    for k, x in enumerate((-6.6, 0.0, 6.6)):
        S.box(f'win_frame{k}', (3.6, 0.1, 5.6), (x, yf - 0.05, 5.7), 'White')
        S.box(f'win_glass{k}', (3.2, 0.1, 5.2), (x, yf - 0.1, 5.7), 'Window' if k != 1 else 'Glass')
        S.box(f'win_mullion{k}', (0.12, 0.06, 5.2), (x, yf - 0.16, 5.7), 'White')
        S.box(f'win_transom{k}', (3.2, 0.06, 0.12), (x, yf - 0.16, 7.4), 'White')
        arched_window(S, f'arch_win{k}', x, 9.3, 12.0, 3.0, yf, arch_mat='OrangeBrick')
        S.add(diamonds(f'tiles{k}', x - 1.4, x + 1.5, 0.7, 1.4, 0.3, yf - 0.06, S.m['Cream'], S.col))
    S.box('door', (2.4, 0.12, 2.6), (0, yf - 0.06, 1.3), 'DoorGreen')
    # The clock and the lettering.
    S.box('clock_panel', (3.9, 0.3, 3.9), (0, yf - 0.2, 14.4), 'Cream')
    S.cyl('clock_rim', 1.7, 0.08, (0, yf - 0.38, 14.4), 'Dark', segments=32, axis='Y')
    S.cyl('clock_face', 1.55, 0.08, (0, yf - 0.43, 14.4), 'Porcelain', segments=32, axis='Y')
    for h in range(12):
        a = 2 * math.pi * h / 12
        S.box(f'clock_mark{h}', (0.12, 0.05, 0.3), (1.25 * math.sin(a), yf - 0.49, 14.4 + 1.25 * math.cos(a)), 'Dark',
              rot=(0, a, 0))
    S.box('clock_hour', (0.12, 0.05, 0.85), (0.3, yf - 0.52, 14.4 - 0.25), 'Dark', rot=(0, math.radians(-130), 0))
    S.box('clock_minute', (0.08, 0.05, 1.25), (0.5, yf - 0.55, 14.6), 'Dark', rot=(0, math.radians(-55), 0))
    for k, (x, word) in enumerate(((-6.6, 'KONINKLIJKE'), (6.6, 'STOOMWEVERIJ'))):
        S.box(f'name_border{k}', (7.4, 0.22, 1.8), (x, yf - 0.1, 13.9), 'KswBrick')
        S.box(f'name_panel{k}', (7.0, 0.26, 1.45), (x, yf - 0.14, 13.9), 'Cream')
        S.text(f'name{k}', word, 0.6, (x, yf - 0.3, 13.62), 'Dark', extrude=0.05)

    # Weaving sheds left and right: arched windows, a cream frieze, slate roofs, chimneys.
    def shed(tag, x0, x1, n_win):
        y0, d, h = yf + 4, 28, 7.2
        S.box(f'{tag}_shed', (x1 - x0, d, h), ((x0 + x1) / 2, y0 + d / 2, h / 2), 'KswBrick')
        S.add(ck.extrude_yz(f'{tag}_roof', [(y0 - 0.5, h), (y0 + d + 0.5, h), (y0 + d / 2, h + 2.6)], x0 - 0.3, x1 + 0.3,
                            S.m['Slate'], col=S.col))
        S.box(f'{tag}_frieze', (x1 - x0, 0.2, 0.35), ((x0 + x1) / 2, y0 - 0.08, h - 0.35), 'Cream')
        S.add(diamonds(f'{tag}_teeth', x0 + 0.5, x1 - 0.5, 0.9, h - 1.0, 0.28, y0 - 0.1, S.m['Cream'], S.col))
        S.box(f'{tag}_plinth', (x1 - x0, 0.2, 0.6), ((x0 + x1) / 2, y0 - 0.08, 0.3), 'Cream')
        step = (x1 - x0) / n_win
        for i in range(n_win):
            x = x0 + step * (i + 0.5)
            arched_window(S, f'{tag}_win{i}', x, 1.5, 5.4, 2.4, y0, arch_mat='OrangeBrick',
                          glass='Window' if i % 3 == 1 else 'Glass')
        return y0, d, h

    y0, d, h = shed('east', hw, 80.0, 10)
    shed('west', -40.0, -hw, 4)
    for k, x in enumerate((44.0, 77.0, -38.0)):
        S.box(f'chimney{k}', (1.5, 1.5, 7), (x, y0 + d - 3, h + 3.5), 'KswBrick')
        S.box(f'chimney_cap{k}', (1.8, 1.8, 0.3), (x, y0 + d - 3, h + 7.1), 'Cream')
    S.box('lawn', (130, 14, 0.12), (20, yf - 7, 0.06), 'Grass')
    return S.finish()


BUILDERS = {
    'gemeentehuis': gemeentehuis,
    'ravijn': ravijn,
    'stoomweverij': stoomweverij,
    'raadhuis': raadhuis,
    'watertoren': watertoren,
    'heraklus': heraklus,
    'metropool': metropool,
    'utwente': utwente,
    'veste': veste,
    'brouwerij': brouwerij,
    'thuisbesteld': thuisbesteld,
    'barge': barge,
}
