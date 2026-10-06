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

    def finish(self):
        for o in self.parts:
            if o.parent is None:
                o.parent = self.root
        return self.root


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


BUILDERS = {
    'metropool': metropool,
    'utwente': utwente,
    'veste': veste,
    'brouwerij': brouwerij,
    'thuisbesteld': thuisbesteld,
    'barge': barge,
}
