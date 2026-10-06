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
    # Twente landmarks
    mk('GreenGlass', (0.04, 0.32, 0.14), metallic=0.6, roughness=0.08, emission=(0.02, 0.22, 0.08), strength=0.35)
    mk('BrightRed', (0.72, 0.015, 0.015), roughness=0.45)
    mk('IkeaBlue', (0.0, 0.07, 0.38), roughness=0.5)
    mk('Yellow', (0.95, 0.68, 0.0), roughness=0.45)
    mk('Timber', (0.33, 0.2, 0.1), roughness=0.85)
    mk('RoofRed', (0.62, 0.1, 0.045), roughness=0.55)
    mk('Terracotta', (0.6, 0.24, 0.11), roughness=0.85)
    mk('Render', (0.74, 0.68, 0.56), roughness=0.85)
    mk('Gabion', (0.2, 0.2, 0.19), roughness=1.0)
    mk('Paving', (0.32, 0.12, 0.1), roughness=0.95)
    mk('Tile', (0.42, 0.06, 0.035), roughness=0.75)
    mk('SeatGrey', (0.035, 0.035, 0.04), roughness=0.6)
    mk('Asphalt', (0.06, 0.06, 0.065), roughness=0.95)
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


def tubes(name, segs, r, mat, col, sides=6):
    """Many steel tubes (space frames, trusses) as one mesh. segs: [(p0, p1), ...]."""
    from mathutils import Matrix
    bm = bmesh.new()
    for p0, p1 in segs:
        p0, p1 = Vector(p0), Vector(p1)
        v = p1 - p0
        if v.length < 1e-4:
            continue
        res = bmesh.ops.create_cone(bm, cap_ends=False, segments=sides, radius1=r, radius2=r, depth=v.length)
        rot = Vector((0, 0, 1)).rotation_difference(v.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation((p0 + p1) / 2) @ rot, verts=res['verts'])
    return ck.bm_object(name, bm, [mat], col=col)


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
# Stadium helpers (rounded rectangles)
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


# ---------------------------------------------------------------------------
# De Grolsj Veste (FC Twente, Enschede): red roofs under a white space frame
# ---------------------------------------------------------------------------

def veste():
    S = Site('Veste')
    hw, hh, r = 56, 38, 10           # rectangle the stands are swept around
    S.box('pitch', (105, 68, 0.3), (0, 0, 0.15), 'Pitch')
    for k in range(10):
        if k % 2:
            S.box(f'mow{k}', (10.5, 68, 0.02), (-52.5 + 5.25 + k * 10.5, 0, 0.31), 'Grass')
    S.add(ring_mesh('stands', [(0, 1.2), (13, 9.0), (14.5, 10.0), (26, 18.5)], hw, hh, r, S.m['Seats'], S.col))
    S.add(ring_mesh('stand_rail', [(14.0, 10.0), (14.6, 10.6)], hw, hh, r, S.m['White'], S.col))
    S.add(ring_mesh('facade_low', [(28, 0), (28, 7.5)], hw, hh, r, S.m['Glass'], S.col))
    S.add(ring_mesh('facade_red', [(28.6, 7.5), (28.6, 19.5)], hw, hh, r, S.m['BrightRed'], S.col))
    S.add(ring_mesh('facade_band', [(28.8, 12.8), (28.8, 13.6)], hw, hh, r, S.m['TwenteRed'], S.col))
    S.add(ring_mesh('roof', [(31, 24.0), (5, 22.0), (5, 21.4), (31, 23.4), (31, 24.0)], hw, hh, r, S.m['RoofRed'], S.col))
    # Columns around the bowl and the white space frame on the roof.
    n = 48
    segs = []
    pts = [rounded_rect(k / n, hw, hh, r) for k in range(n)]

    def at(k, o, z):
        (x, y), (nx, ny) = pts[k % n]
        return (x + nx * o, y + ny * o, z)

    for k in range(n):
        segs.append((at(k, 29.6, 0), at(k, 29.6, 24.2)))                     # columns
        segs.append((at(k, 30.5, 24.3), at(k, 18, 28.5)))                    # rafter up
        segs.append((at(k, 18, 28.5), at(k, 6, 22.6)))                       # rafter down
        segs.append((at(k, 18, 28.5), at(k + 1, 18, 28.5)))                  # ridge chord
        segs.append((at(k, 30.5, 24.3), at(k + 1, 18, 28.5)))                # diagonals
        segs.append((at(k, 6, 22.6), at(k + 1, 18, 28.5)))
        segs.append((at(k, 18, 28.5), at(k, 18, 23.0)))                      # strut to the roof
    S.add(tubes('space_frame', segs, 0.22, S.m['White'], S.col))
    # Stair towers in white concrete, two grey silos at the back.
    for k, (x, y) in enumerate(((-38, -(hh + 31)), (38, -(hh + 31)), (-(hw + 31), 0), (hw + 31, 0))):
        S.box(f'stairs{k}', (6, 6, 23), (x, y, 11.5), 'White')
        for z in range(3, 22, 4):
            S.box(f'stairs{k}_{z}', (6.2, 6.2, 1.2), (x, y, z), 'Concrete')
    for k, x in enumerate((-60, 60)):
        S.cyl(f'silo{k}', 3.2, 22, (x, hh + 30, 11), 'Steel', segments=16)
    # Brick entrance building with the green name and the club's nickname.
    ey = -(hh + 29)
    S.box('entrance', (44, 10, 12), (0, ey - 5, 6), 'Terracotta')
    S.box('entrance_glass', (30, 0.2, 4.5), (0, ey - 10.05, 2.6), 'Glass')
    S.windows('entrance_lit', (0, ey - 10, 2.6), 30, 4.5, 10, 1, face='-Y', size=(0.9, 0.9), lit=0.7, seed=9)
    S.text('sign', 'De Grolsj Veste', 3.0, (0, ey - 10.15, 7.6), 'NeonGreen', extrude=0.15)
    S.text('club', 'TUKKERS', 4.0, (0, -(hh + 28.9), 14.4), 'White', extrude=0.12)
    S.box('car_park', (150, 30, 0.12), (0, ey - 26, 0.06), 'Asphalt')
    return S.finish()


# ---------------------------------------------------------------------------
# Grolsj brewery (Boekelo): white high-bay warehouse with green glass, right by the A35
# ---------------------------------------------------------------------------

def brouwerij():
    S = Site('Brouwerij')
    x0, x1, yf, d, h = -36.0, 36.0, -22.0, 44.0, 32.0
    S.box('base', (x1 - x0, d, 7), (0, yf + d / 2, 3.5), 'Concrete')
    S.box('warehouse', (x1 - x0, d, h - 7), (0, yf + d / 2, 7 + (h - 7) / 2), 'White')
    S.box('roof_edge', (x1 - x0 + 0.4, d + 0.4, 0.6), (0, yf + d / 2, h + 0.3), 'Concrete')
    for k in range(13):  # vertical panel joints on the white parts
        x = x0 + 1.5 + k * 1.6
        S.box(f'joint{k}', (0.08, 0.1, h - 7.2), (x, yf - 0.05, 7 + (h - 7) / 2), 'Concrete')
    # Three green curtain walls between grey corrugated strips on the road side.
    for k, (a, b) in enumerate(((-15.0, 3.0), (6.0, 20.0), (23.0, 35.0))):
        S.box(f'glass{k}', (b - a, 0.3, 21), ((a + b) / 2, yf - 0.1, 7.2 + 10.5), 'GreenGlass')
        for i in range(1, int(b - a) // 2):
            S.box(f'mullion{k}_{i}', (0.1, 0.2, 21), (a + i * 2, yf - 0.3, 17.7), 'Panel')
        for z in range(9, 28, 3):
            S.box(f'transom{k}_{z}', (b - a, 0.2, 0.1), ((a + b) / 2, yf - 0.3, z), 'Panel')
    for k, x in enumerate((4.5, 21.5)):
        S.box(f'strip{k}', (2.6, 0.4, h - 7), (x, yf - 0.1, 7 + (h - 7) / 2), 'Panel')
    # Advertising on the first glass panel: two bottles clinking.
    S.box('ad', (13, 0.2, 18), (-6, yf - 0.4, 18.5), 'TwenteRed' if False else 'Pitch')
    for k, (x, a) in enumerate(((-8.0, 0.25), (-4.0, -0.25))):
        b = S.cyl(f'bottle{k}', 1.0, 7, (x, yf - 0.8, 20), 'BottleGlass', segments=12)
        b.rotation_euler = (0, a, 0)
        n = S.cyl(f'neck{k}', 0.4, 2.4, (x - math.sin(a) * 4.6, yf - 0.8, 20 + math.cos(a) * 4.6), 'BottleGlass', segments=10)
        n.rotation_euler = (0, a, 0)
        S.box(f'label{k}', (1.6, 0.2, 1.6), (x, yf - 1.85, 19.4), 'Porcelain', rot=(0, a, 0))
    S.text('ad_text', 'Rap op hoes an', 1.7, (-6, yf - 0.6, 12.0), 'White', extrude=0.06)
    # The name, big, on the white part facing the road and on the short side.
    S.text('logo', 'Grolsj', 5.5, (-25.5, yf - 0.15, 18.5), 'NeonGreen', extrude=0.25)
    S.cyl('crest', 2.2, 0.3, (-25.5, yf - 0.2, 27.5), 'Cream', segments=24, axis='Y')
    S.text('logo_side', 'Grolsj', 5.5, (x0 - 0.15, yf + d / 2, 18.5), 'NeonGreen', rot=(math.pi / 2, 0, -math.pi / 2),
           extrude=0.25)
    S.box('door', (2, 0.2, 3), (-30, yf - 0.1, 1.5), 'BrightRed')
    # Brew house to the left, joined by a red pipe bridge.
    S.box('brewhouse', (34, 36, 13), (x0 - 24, yf + 24, 6.5), 'Panel')
    S.box('brewhouse_glass', (34, 0.2, 3), (x0 - 24, yf + 5.9, 9.5), 'Glass')
    S.box('brewhouse_white', (26, 20, 9), (x0 - 20, yf + 8, 4.5), 'White')
    segs = []
    for k in range(9):
        x = x0 - 6 - k * 2.5
        segs += [((x, yf - 2, 0), (x, yf - 2, 6)), ((x, yf + 1, 0), (x, yf + 1, 6))]
        if k < 8:
            segs += [((x, yf - 2, 6), (x - 2.5, yf - 2, 6)), ((x, yf + 1, 6), (x - 2.5, yf + 1, 6)),
                     ((x, yf - 2, 6), (x - 2.5, yf - 2, 4.5))]
    S.add(tubes('pipe_bridge', segs, 0.18, S.m['BrightRed'], S.col))
    S.cyl('pipe', 0.45, 20, (x0 - 16, yf - 0.5, 5.6), 'Steel', axis='X', segments=10)
    # Distribution centre to the right with red masts and stay cables over the loading docks.
    S.box('dc', (90, 50, 12), (x1 + 52, yf + 40, 6), 'White')
    S.box('dock_roof', (90, 9, 0.5), (x1 + 52, yf + 10.5, 6.5), 'Concrete')
    segs = []
    for k in range(5):
        x = x1 + 14 + k * 18
        top = (x, yf + 15, 22)
        segs += [((x - 1.5, yf + 15, 12), top), ((x + 1.5, yf + 15, 12), top), (top, (x, yf + 7, 6.7)),
                 (top, (x - 6, yf + 7, 6.7)), (top, (x + 6, yf + 7, 6.7))]
    S.add(tubes('masts', segs, 0.3, S.m['BrightRed'], S.col))
    # Flags with the brand on them.
    for k in range(3):
        x = x0 - 6 + k * 4
        S.cyl(f'flagpole{k}', 0.1, 12, (x, yf - 14, 6), 'White', segments=6)
        S.box(f'flag{k}', (0.05, 1.4, 3.6), (x, yf - 14.75, 9.9), 'White')
        S.box(f'flag_logo{k}', (0.07, 0.4, 2.6), (x, yf - 14.75, 9.9), 'NeonGreen')
    S.box('lawn', (150, 30, 0.12), (10, yf - 15, 0.06), 'Grass')
    return S.finish()


# ---------------------------------------------------------------------------
# Thuisbesteld HQ (Enschede): terracotta centre block between two round-ended cream wings
# ---------------------------------------------------------------------------

def thuisbesteld():
    S = Site('Thuisbesteld')
    yf = -8.0
    # Centre block with punched windows, glass entrance and a floating white roof.
    S.box('centre', (34, 22, 21), (0, yf + 11, 10.5), 'Terracotta')
    S.windows('centre_win', (0, yf, 12.5), 31, 13, 11, 5, face='-Y', size=(0.55, 0.62), lit=0.45, seed=14)
    S.box('entrance', (20, 0.2, 5.0), (0, yf - 0.05, 2.6), 'Glass')
    for k in range(6):
        S.cyl(f'pillar{k}', 0.3, 5.2, (-9 + k * 3.6, yf - 1.6, 2.6), 'White', segments=10)
    S.box('canopy_low', (22, 3.4, 0.4), (0, yf - 1.6, 5.4), 'White')
    S.box('roof', (38, 25, 0.5), (0, yf + 11, 22.0), 'White')
    S.box('roof_lip', (38, 0.8, 1.2), (0, yf - 1.2, 22.2), 'White')
    S.box('tower', (8, 8, 26), (13, yf + 18, 13), 'RedBrick')
    S.box('tower2', (6, 6, 25), (-14, yf + 19, 12.5), 'RedBrick')
    # Round-ended wings: cream render, ribbon windows, a wide white roof disc on top.
    for side in (-1, 1):
        cx, cy = side * 33.0, yf + 12.0
        hw_, hh_ = 17.0, 10.0
        S.add(rounded_slab(f'wing{side}', hw_, hh_, hh_ - 0.1, 0, 23.0, S.m['Render'], S.col, cx, cy))
        for f in range(7):
            z = 2.2 + f * 3.0
            S.add(rounded_slab(f'wing{side}_win{f}', hw_ + 0.06, hh_ + 0.06, hh_ - 0.04, z, z + 1.35,
                               S.m['Window' if (f + side) % 3 == 0 else 'Glass'], S.col, cx, cy))
        S.add(rounded_slab(f'wing{side}_roof', hw_ + 2.2, hh_ + 2.2, hh_ + 2.1, 23.6, 24.1, S.m['White'], S.col, cx, cy))
        S.add(rounded_slab(f'wing{side}_top', hw_ - 1.0, hh_ - 1.0, hh_ - 1.1, 23.0, 23.6, S.m['Glass'], S.col, cx, cy))
    # Gabion walls along the street, steps up to the entrance.
    for side in (-1, 1):
        S.box(f'gabion{side}', (38, 2.0, 3.2), (side * 27, yf - 9, 1.6), 'Gabion')
    for k in range(8):
        S.box(f'step{k}', (14, 1.1, 0.4 * (k + 1)), (0, yf - 12 + k * 1.1, 0.2 * (k + 1)), 'Concrete')
    # The brand, in orange neon, on the roof edge.
    S.text('sign', 'Thuisbesteld.nl', 2.4, (0, yf - 1.7, 22.9), 'NeonOrange', extrude=0.12)
    S.prism('logo_house', [(-1.6, 0), (1.6, 0), (1.6, 2.0), (0, 3.4), (-1.6, 2.0)], yf - 0.2, yf + 0.2, 'NeonOrange')
    S.parts[-1].location = (-12.5, 0, 17.0)
    S.box('street', (120, 12, 0.1), (0, yf - 20, 0.05), 'Asphalt')
    return S.finish()


# ---------------------------------------------------------------------------
# Heraklus stadium (Almelo): white roof with tube trusses, silver corners, the club name in the seats
# ---------------------------------------------------------------------------

def heraklus():
    S = Site('Heraklus')
    hw, hh, r = 54, 36, 14
    S.box('pitch', (105, 68, 0.3), (0, 0, 0.15), 'Pitch')
    for k in range(10):
        if k % 2:
            S.box(f'mow{k}', (10.5, 68, 0.02), (-52.5 + 5.25 + k * 10.5, 0, 0.31), 'Grass')
    S.add(ring_mesh('stands', [(0, 1.2), (12, 8.5), (13.5, 9.4), (24, 16.5)], hw, hh, r, S.m['SeatGrey'], S.col))
    S.text('seat_letters', 'HERAKLUS', 4.2, (0, hh + 1.6, 2.3), 'White', rot=(math.atan2(7.3, 12), 0, 0), extrude=0.05)
    S.add(ring_mesh('facade', [(26.5, 0), (26.5, 8)], hw, hh, r, S.m['White'], S.col))
    S.add(ring_mesh('facade_glass', [(26.6, 2.5), (26.6, 6.0)], hw, hh, r, S.m['Glass'], S.col))
    S.add(ring_mesh('cladding', [(26.5, 8), (28.5, 14), (28.5, 18), (27, 21)], hw, hh, r, S.m['Cladding'], S.col))
    S.add(ring_mesh('roof', [(28, 21.2), (6, 19.8), (6, 19.3), (28, 20.6), (28, 21.2)], hw, hh, r, S.m['White'], S.col))
    n = 40
    pts = [rounded_rect(k / n, hw, hh, r) for k in range(n)]

    def at(k, o, z):
        (x, y), (nx, ny) = pts[k % n]
        return (x + nx * o, y + ny * o, z)

    segs = []
    for k in range(n):  # triangular trusses that lean in over the roof
        segs += [(at(k, 28, 21.2), at(k, 12, 26.5)), (at(k, 12, 26.5), at(k, 6, 20.2)),
                 (at(k, 22, 21.3), at(k, 12, 26.5))]
    S.add(tubes('trusses', segs, 0.25, S.m['White'], S.col))
    for k, (sx, sy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):  # floodlights in the corners
        x, y = sx * (hw + 14), sy * (hh + 14)
        S.cyl(f'mast{k}', 0.45, 34, (x, y, 17), 'Steel', segments=8)
        S.box(f'lamps{k}', (4.5, 0.8, 2.6), (x, y, 34.5), 'NeonWhite', rot=(math.radians(25), 0, math.atan2(sy, sx) + math.pi / 2))
    # Main stand front: offices with the stadium sign, and the dark wedge-shaped office building.
    fy = -(hh + 27)
    S.box('offices', (76, 12, 7.5), (0, fy - 6, 3.75), 'White')
    S.windows('office_win', (0, fy - 12, 4.6), 70, 2.4, 22, 1, face='-Y', size=(0.8, 0.8), lit=0.55, seed=21)
    S.box('entrance', (20, 13, 10), (0, fy - 6.5, 5), 'Dark')
    S.text('sign', 'HERAKLUS STADION', 1.6, (0, fy - 13.1, 7.2), 'NeonWhite', extrude=0.08)
    S.text('crest', 'H', 3.0, (0, fy - 13.1, 2.0), 'White', extrude=0.08)
    wedge = [(-14, 0), (14, 0), (14, 13), (-14, 22)]
    S.prism('wedge', wedge, fy - 40, fy - 26, 'Dark')
    S.parts[-1].location = (34, 0, 0)
    S.windows('wedge_win', (34, fy - 40, 9.5), 24, 15, 9, 5, face='-Y', size=(0.55, 0.5), lit=0.5, seed=8)
    S.box('car_park', (110, 34, 0.12), (0, fy - 30, 0.06), 'Asphalt')
    return S.finish()


# ---------------------------------------------------------------------------
# Bouwhaus (Westermaat, Hengelo): huge red DIY box, wooden sign tower
# ---------------------------------------------------------------------------

def bauhaus():
    S = Site('Bauhaus')
    x0, x1, yf, d, h = -70.0, 70.0, -40.0, 90.0, 11.0
    S.box('hall', (x1 - x0, d, h), (0, yf + d / 2, h / 2), 'BrightRed')
    S.box('roof', (x1 - x0 - 0.6, d - 0.6, 0.3), (0, yf + d / 2, h + 0.1), 'Concrete')
    S.box('parapet', (x1 - x0 + 0.2, 0.5, 0.6), (0, yf - 0.05, h - 0.3), 'White')
    for k in range(6):  # rows of barrel roof lights
        S.cyl(f'rooflight{k}', 1.3, 110, (0, yf + 12 + k * 13, h + 0.2), 'Glass', axis='X', segments=12)
    # Drive-in in white on the left, glass entrance with the big red house frames, garden centre right.
    S.box('drivein', (24, 0.6, 9), (x0 + 12, yf - 0.3, 4.5), 'White')
    for k in range(3):
        S.box(f'drivein_door{k}', (5, 0.2, 4.5), (x0 + 4.5 + k * 7.5, yf - 0.7, 2.25), 'Dark')
    S.text('drivein_sign', 'Drive-In', 1.5, (x0 + 12, yf - 0.7, 6.0), 'BrightRed', extrude=0.06)
    S.box('entrance', (44, 0.3, 6.5), (-2, yf - 0.15, 3.25), 'Glass')
    S.windows('entrance_lit', (-2, yf, 3.25), 44, 6.5, 12, 2, face='-Y', size=(0.85, 0.85), lit=0.6, seed=4)
    S.text('name', 'BOUWHAUS', 4.2, (2, yf - 0.4, 6.9), 'White', extrude=0.15)
    frames = []
    for (cx, w, top) in ((-25.0, 10.0, 15.0), (-19.0, 8.0, 12.5)):
        frames += [((cx - w / 2, yf - 2.5, 0), (cx - w / 2, yf - 2.5, top - w / 2)),
                   ((cx + w / 2, yf - 2.5, 0), (cx + w / 2, yf - 2.5, top - w / 2)),
                   ((cx - w / 2, yf - 2.5, top - w / 2), (cx, yf - 2.5, top)),
                   ((cx, yf - 2.5, top), (cx + w / 2, yf - 2.5, top - w / 2))]
    S.add(tubes('house_frames', frames, 0.6, S.m['BrightRed'], S.col, sides=4))
    S.box('garden', (26, 0.3, 7), (44, yf - 0.15, 3.5), 'GreenGlass')
    S.text('garden_sign', 'De Stadstuin', 2.0, (44, yf - 0.4, 7.6), 'NeonGreen', extrude=0.08)
    S.box('side_windows', (0.2, 60, 1.2), (x1 + 0.05, yf + d / 2, 8.5), 'Glass')
    # Sign tower: timber slats around a frame, a red sign box on top (seen from far down the road).
    tx, ty = -20.0, yf + d + 6
    for k, sx in enumerate((-1, 1)):
        S.box(f'tower_leg{k}', (3, 6, 12), (tx + sx * 3.5, ty, 6), 'Timber')
    S.box('tower_body', (10, 6, 18), (tx, ty, 21), 'Timber')
    slats = []
    for i in range(21):
        x = tx - 5.2 + i * 0.52
        slats += [((x, ty - 3.15, 12), (x, ty - 3.15, 30)), ((x, ty + 3.15, 12), (x, ty + 3.15, 30))]
    S.add(tubes('tower_slats', slats, 0.09, S.m['Timber'], S.col, sides=4))
    S.box('tower_sign', (13, 3.2, 3.2), (tx, ty, 31.6), 'BrightRed')
    for side in (-1, 1):
        S.text(f'tower_name{side}', 'BOUWHAUS', 1.9, (tx, ty + side * 1.65, 30.8), 'White', extrude=0.06,
               rot=(math.pi / 2, 0, 0 if side < 0 else math.pi))
    # Car park with red paving stripes.
    S.box('car_park', (150, 40, 0.1), (0, yf - 22, 0.05), 'Asphalt')
    for k in range(5):
        S.box(f'paving{k}', (130, 3, 0.12), (0, yf - 8 - k * 8, 0.07), 'Paving')
    return S.finish()


# ---------------------------------------------------------------------------
# Ikeo (Westermaat, Hengelo): the blue box, yellow trim, the sign pylon, solar carports
# ---------------------------------------------------------------------------

def ikea():
    S = Site('Ikea')
    x0, x1, yf, d, h = -75.0, 75.0, -40.0, 85.0, 16.0
    S.box('store', (x1 - x0, d, h), (0, yf + d / 2, h / 2), 'IkeaBlue')
    S.box('roof', (x1 - x0 - 0.6, d - 0.6, 0.3), (0, yf + d / 2, h + 0.1), 'Concrete')
    S.box('trim', (x1 - x0 + 0.2, d + 0.2, 0.9), (0, yf + d / 2, h - 0.45), 'Yellow')
    for k in range(10):
        S.box(f'roof_unit{k}', (6, 4, 2.5), (-50 + k * 11, yf + 30 + (k % 3) * 12, h + 1.4), 'Steel')
    # Yellow entrance block with flags, glass band, and the logo high on the facade.
    S.box('entrance_block', (22, 4, 13), (-38, yf - 1.5, 6.5), 'Yellow')
    S.box('entrance_glass', (14, 0.3, 4.5), (-38, yf - 3.6, 2.3), 'Glass')
    for k in range(6):
        x = -46 + k * 3.2
        S.cyl(f'flagpole{k}', 0.08, 9, (x, yf - 6, 4.5), 'White', segments=6)
        S.box(f'flag{k}', (1.6, 0.05, 2.4), (x + 0.8, yf - 6, 7.6), ('BrightRed', 'Yellow', 'Blue', 'NeonGreen', 'White', 'Orange')[k])
    S.box('glass_band', (80, 0.3, 4.0), (22, yf - 0.1, 8.5), 'Glass')
    S.windows('glass_lit', (22, yf, 8.5), 80, 4.0, 20, 1, face='-Y', size=(0.9, 0.85), lit=0.55, seed=12)
    S.box('logo_back', (24, 0.4, 9), (0, yf - 0.3, 10.8), 'IkeaBlue')
    oval = S.cyl('logo_oval', 4.0, 0.3, (0, yf - 0.6, 10.8), 'Yellow', segments=32, axis='Y')
    oval.scale = (2.6, 1, 1)
    S.text('logo', 'IKEO', 5.2, (0, yf - 0.85, 8.6), 'IkeaBlue', extrude=0.12)
    S.box('stair_tower', (6, 6, 20), (x0 + 3, yf + 3, 10), 'Glass')
    S.box('stair_tower_frame', (6.3, 6.3, 0.5), (x0 + 3, yf + 3, 20), 'Yellow')
    # Sign pylon by the road.
    px, py = x0 - 14, yf - 18
    segs = []
    for (dx, dy) in ((-1.5, -1.5), (1.5, -1.5), (-1.5, 1.5), (1.5, 1.5)):
        segs.append(((px + dx, py + dy, 0), (px + dx * 0.6, py + dy * 0.6, 26)))
    for z in range(2, 26, 3):
        segs += [((px - 1.4, py - 1.4, z), (px + 1.4, py - 1.4, z + 2.5)), ((px + 1.4, py - 1.4, z), (px - 1.4, py - 1.4, z + 2.5))]
    S.add(tubes('pylon', segs, 0.12, S.m['Steel'], S.col, sides=4))
    S.box('pylon_sign', (8, 1.4, 4.4), (px, py, 28), 'IkeaBlue')
    pov = S.cyl('pylon_oval', 1.8, 1.5, (px, py, 28), 'Yellow', segments=24, axis='Y')
    pov.scale = (1.9, 1, 1)
    for side in (-1, 1):
        S.text(f'pylon_logo{side}', 'IKEO', 2.0, (px, py + side * 0.78, 27.1), 'IkeaBlue', extrude=0.05,
               rot=(math.pi / 2, 0, 0 if side < 0 else math.pi))
    # Solar carports on the car park beside the store.
    for k in range(5):
        y = yf - 8 - k * 9
        S.box(f'carport{k}', (60, 6, 0.25), (x1 - 25, y, 4.2), 'Solar', rot=(math.radians(-8), 0, 0))
        S.box(f'carport_frame{k}', (60.4, 6.4, 0.15), (x1 - 25, y, 4.0), 'White', rot=(math.radians(-8), 0, 0))
        for j in range(5):
            S.cyl(f'carport_post{k}_{j}', 0.15, 4.0, (x1 - 52 + j * 13.5, y, 2.0), 'White', segments=6)
    S.box('car_park', (160, 52, 0.1), (5, yf - 26, 0.05), 'Asphalt')
    return S.finish()


# ---------------------------------------------------------------------------
# Tokko Locco and the fuel station on the N35 at Haarle
# ---------------------------------------------------------------------------

def tokkolocco():
    S = Site('TokkoLocco')
    yf = -5.0
    # Brick house with a big red hipped roof and two white dormers.
    S.box('house', (18, 12, 4.2), (0, yf + 7, 2.1), 'RedBrick')
    # Hipped roof with a short ridge, steep like the real one.
    W, D, z0, z1, cy = 9.6, 6.6, 4.2, 10.8, yf + 7
    verts = [(-W, cy - D, z0), (W, cy - D, z0), (W, cy + D, z0), (-W, cy + D, z0), (-W + D, cy, z1), (W - D, cy, z1)]
    faces = [(0, 1, 5, 4), (2, 3, 4, 5), (1, 2, 5), (3, 0, 4), (3, 2, 1, 0)]
    S.add(ck.mesh_object('roof', verts, faces, [S.m['Tile']], col=S.col))
    for k, x in enumerate((-4.0, 4.0)):
        S.box(f'dormer{k}', (2.6, 3.0, 2.4), (x, yf + 3.6, 7.3), 'White')
        S.box(f'dormer_glass{k}', (1.6, 0.1, 1.5), (x, yf + 2.05, 7.2), 'Window' if k else 'Glass')
        S.box(f'dormer_roof{k}', (3.0, 3.4, 0.25), (x, yf + 3.6, 8.6), 'Dark')
    S.box('chimney', (1.0, 1.0, 3.5), (5.5, yf + 9, 9.5), 'RedBrick')
    S.windows('house_win', (0, yf + 1, 2.1), 16, 2.0, 4, 1, face='-Y', size=(0.6, 0.8), lit=0.8, seed=2)
    # Front annex: dark green timber with picture banners and white end panels.
    S.box('annex', (16, 5, 3.4), (-1, yf - 1.5, 1.7), 'DoorGreen')
    S.box('annex_roof', (16.6, 5.6, 0.35), (-1, yf - 1.5, 3.55), 'Dark')
    for k, x in enumerate((-6.0, -2.0, 2.0, 5.0)):
        S.box(f'banner{k}', (3.2, 0.1, 2.4), (x, yf - 4.05, 1.8), 'Window' if k % 2 else 'Terracotta')
    for k, x in enumerate((-8.4, 6.6)):
        S.box(f'end_panel{k}', (1.6, 0.12, 2.6), (x, yf - 4.07, 1.8), 'White')
    S.box('name_board', (8, 0.3, 1.0), (3, yf - 4.1, 4.3), 'White')
    S.text('name', 'TOKKO LOCCO', 0.62, (3, yf - 4.3, 4.02), 'Pine', extrude=0.04)
    # Parking sign and flags.
    S.cyl('r_pole', 0.12, 8, (12, yf - 6, 4), 'Steel', segments=6)
    S.box('r_sign', (1.4, 0.2, 2.0), (12, yf - 6, 8.5), 'Blue')
    S.text('r_letter', 'R', 1.4, (12, yf - 6.15, 7.9), 'White', extrude=0.04)
    for k in range(3):
        x = -16 - k * 1.6
        S.cyl(f'flagpole{k}', 0.07, 7, (x, yf - 4, 3.5), 'White', segments=6)
        S.box(f'flag{k}', (0.05, 0.9, 3.2), (x, yf - 4.5, 5.2), 'White')
        S.box(f'flag_logo{k}', (0.07, 0.4, 0.4), (x, yf - 4.5, 5.6), 'NeonGreen')
    # Fuel station a little further on: green canopy, pumps and a price totem.
    fx = -34.0
    S.box('canopy', (16, 10, 0.9), (fx, yf + 1, 5.2), 'White')
    S.box('canopy_band', (16.2, 10.2, 0.4), (fx, yf + 1, 4.9), 'NeonGreen')
    for dx in (-5, 5):
        S.cyl(f'canopy_post{dx}', 0.25, 4.8, (fx + dx, yf + 1, 2.4), 'White', segments=8)
        S.box(f'pump{dx}', (0.8, 1.4, 1.8), (fx + dx, yf + 1, 0.9), 'NeonGreen')
    S.box('shop', (10, 6, 3.5), (fx, yf + 10, 1.75), 'White')
    S.box('shop_glass', (8, 0.1, 2.2), (fx, yf + 6.95, 1.4), 'Glass')
    S.box('totem', (1.6, 0.5, 6), (fx + 11, yf - 4, 3), 'White')
    S.cyl('totem_logo', 0.65, 0.12, (fx + 11, yf - 4.28, 5.2), 'Yellow', segments=16, axis='Y')
    S.cyl('totem_ring', 0.8, 0.1, (fx + 11, yf - 4.25, 5.2), 'NeonGreen', segments=16, axis='Y')
    S.box('totem_prices', (1.3, 0.1, 2.6), (fx + 11, yf - 4.3, 2.6), 'NeonGreen')
    S.box('forecourt', (64, 22, 0.08), (-14, yf + 3, 0.04), 'Asphalt')
    import random
    rnd = random.Random(3)
    for k in range(7):  # the tall trees behind
        x = -45 + k * 9 + rnd.random() * 3
        hgt = 10 + rnd.random() * 6
        S.cyl(f'tree{k}', 3.0 + rnd.random(), hgt, (x, yf + 20 + rnd.random() * 4, hgt / 2), 'Pine', segments=7, r2=0.4)
    return S.finish()


BUILDERS = {
    'bauhaus': bauhaus,
    'ikea': ikea,
    'tokkolocco': tokkolocco,
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
