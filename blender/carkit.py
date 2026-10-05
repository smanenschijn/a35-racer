"""
Car building kit for Blender (bpy). Builds detailed low-poly cars out of many small,
named parts so they stay editable in Blender and can be dented / torn off in the game.

Conventions (match the game):
  * metres, Z up, the car's FRONT points to -Y and its LEFT side to +X.
    The glTF exporter turns that into +Z forward / +Y up, which is what the game expects.
  * origin at ground level, halfway along the car's length.
  * object custom properties are exported as glTF "extras":
      zone       front | rear | left | right   (damage zone)
      deform     1 = panel gets dented
      detach     1 = may break off when its zone is badly damaged
  * material names are a contract with the game:
      Paint (recoloured per car), Glass, Trim, Chrome, Tyre, Rim, Caliper,
      HeadLight, BrakeLight, Indicator, Plate
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector


# ---------------------------------------------------------------------------
# Scene & materials
# ---------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def collection(name, parent=None):
    col = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(col)
    return col


def material(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0, coat=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if coat:
        bsdf.inputs['Coat Weight'].default_value = coat
        bsdf.inputs['Coat Roughness'].default_value = 0.08
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1.0)
        bsdf.inputs['Emission Strength'].default_value = strength
    m.diffuse_color = (*color, 1.0)
    m.use_backface_culling = False  # exported as double sided: detached panels stay visible from inside
    return m


def standard_materials(paint=(0.62, 0.02, 0.02)):
    return {
        'Paint': material('Paint', paint, metallic=0.55, roughness=0.32, coat=1.0),
        'Glass': material('Glass', (0.015, 0.022, 0.028), metallic=0.9, roughness=0.06),
        'Trim': material('Trim', (0.018, 0.018, 0.02), roughness=0.65),
        'Chrome': material('Chrome', (0.8, 0.8, 0.82), metallic=1.0, roughness=0.15),
        'Tyre': material('Tyre', (0.012, 0.012, 0.012), roughness=0.92),
        'Rim': material('Rim', (0.62, 0.63, 0.66), metallic=0.9, roughness=0.28),
        'Caliper': material('Caliper', (0.75, 0.05, 0.03), roughness=0.4),
        'HeadLight': material('HeadLight', (0.9, 0.88, 0.8), roughness=0.1, emission=(1.0, 0.95, 0.82), strength=3.0),
        'BrakeLight': material('BrakeLight', (0.35, 0.0, 0.0), roughness=0.15, emission=(1.0, 0.06, 0.04), strength=1.5),
        'Indicator': material('Indicator', (0.9, 0.45, 0.05), roughness=0.15, emission=(1.0, 0.45, 0.05), strength=0.6),
        'Plate': material('Plate', (0.95, 0.75, 0.05), roughness=0.5),
    }


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

def mesh_object(name, verts, faces, mats, face_mats=None, smooth=False, col=None, props=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.validate()
    me.update()
    for m in mats:
        me.materials.append(m)
    if face_mats:
        for poly, mi in zip(me.polygons, face_mats):
            poly.material_index = mi
    for poly in me.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, me)
    (col or bpy.context.scene.collection).objects.link(obj)
    for k, v in (props or {}).items():
        obj[k] = v
    return obj


def bm_object(name, bm, mats, col=None, smooth=False, props=None, location=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for poly in me.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    (col or bpy.context.scene.collection).objects.link(obj)
    for k, v in (props or {}).items():
        obj[k] = v
    return obj


def bevel(obj, width=0.01, segments=2):
    mod = obj.modifiers.new('Bevel', 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    return obj


def box(name, size, location, mat, col=None, bevel_width=0.0, rotation=(0, 0, 0), props=None, segments=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    obj = bm_object(name, bm, [mat], col=col, props=props, location=location)
    obj.rotation_euler = rotation
    if bevel_width:
        bevel(obj, bevel_width, segments)
    return obj


def cylinder(name, radius, depth, location, mat, col=None, axis='X', segments=24, radius2=None, props=None, bevel_width=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius, radius2=radius if radius2 is None else radius2, depth=depth)
    if axis == 'X':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    elif axis == 'Y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'X'))
    obj = bm_object(name, bm, [mat], col=col, smooth=True, props=props, location=location)
    if bevel_width:
        bevel(obj, bevel_width, 2)
    return obj


def ellipsoid(name, radii, location, mat, col=None, props=None, segments=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    bmesh.ops.scale(bm, vec=Vector(radii), verts=bm.verts)
    return bm_object(name, bm, [mat], col=col, smooth=True, props=props, location=location)


def plane(name, size, location, mat, col=None, rotation=(0, 0, 0), props=None):
    w, h = size
    verts = [(-w / 2, 0, -h / 2), (w / 2, 0, -h / 2), (w / 2, 0, h / 2), (-w / 2, 0, h / 2)]
    obj = mesh_object(name, verts, [(0, 1, 2, 3)], [mat], col=col, props=props)
    me = obj.data
    uv = me.uv_layers.new(name='UVMap')
    for loop, co in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop.uv = co
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def lathe(profile, segments=32):
    """Spin a (radius, x) profile around the X axis. Returns bmesh."""
    bm = bmesh.new()
    rings = []
    for k in range(segments):
        a = 2 * math.pi * k / segments
        ring = [bm.verts.new((x, r * math.cos(a), r * math.sin(a))) for r, x in profile]
        rings.append(ring)
    for k in range(segments):
        r0, r1 = rings[k], rings[(k + 1) % segments]
        for i in range(len(profile) - 1):
            bm.faces.new((r0[i], r0[i + 1], r1[i + 1], r1[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ---------------------------------------------------------------------------
# Smooth 1-D curves through key points (monotone cubic, no overshoot)
# ---------------------------------------------------------------------------

class Curve:
    def __init__(self, keys):
        self.xs = [k[0] for k in keys]
        self.ys = [k[1] for k in keys]
        n = len(keys)
        h = [self.xs[i + 1] - self.xs[i] for i in range(n - 1)]
        d = [(self.ys[i + 1] - self.ys[i]) / h[i] for i in range(n - 1)]
        # PCHIP (Fritsch-Butland): weighted harmonic mean of the neighbouring slopes, so the
        # curve never overshoots, even next to a steep drop.
        m = [0.0] * n
        for i in range(1, n - 1):
            if d[i - 1] * d[i] <= 0:
                m[i] = 0.0
            else:
                w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        m[0] = d[0] if n == 2 else self._end_slope(h[0], h[1], d[0], d[1])
        m[-1] = d[-1] if n == 2 else self._end_slope(h[-1], h[-2], d[-1], d[-2])
        self.m = m

    @staticmethod
    def _end_slope(h0, h1, d0, d1):
        m = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if m * d0 <= 0:
            return 0.0
        if d0 * d1 <= 0 and abs(m) > abs(3 * d0):
            return 3 * d0
        return m

    def __call__(self, x):
        xs, ys, m = self.xs, self.ys, self.m
        if x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        i = max(k for k in range(len(xs) - 1) if xs[k] <= x)
        h = xs[i + 1] - xs[i]
        t = (x - xs[i]) / h
        h00 = 2 * t ** 3 - 3 * t ** 2 + 1
        h10 = t ** 3 - 2 * t ** 2 + t
        h01 = -2 * t ** 3 + 3 * t ** 2
        h11 = t ** 3 - t ** 2
        return h00 * ys[i] + h10 * h * m[i] + h01 * ys[i + 1] + h11 * h * m[i + 1]


# ---------------------------------------------------------------------------
# Lofted body, split into panels
# ---------------------------------------------------------------------------

def loft_parts(ts, sections, section_fn, classify, close_front=True, close_rear=True):
    """
    ts:         ring positions (0 = nose, 1 = tail)
    sections:   number of points around each ring (closed loop)
    section_fn: (t, j) -> (x, y, z)
    classify:   (t_mid, j, i) -> part name, or None to drop the face
    Returns {part: (verts, faces)} with vertices duplicated per part (clean panel edges).
    """
    grid = [[section_fn(t, j) for j in range(sections)] for t in ts]
    parts = {}

    def add(part, quad):
        verts, faces, index = parts.setdefault(part, ([], [], {}))
        f = []
        for key in quad:
            if key not in index:
                index[key] = len(verts)
                verts.append(grid[key[0]][key[1]] if key[0] >= 0 else key[2])
            f.append(index[key])
        faces.append(tuple(f))

    for i in range(len(ts) - 1):
        tm = (ts[i] + ts[i + 1]) / 2
        for j in range(sections):
            jn = (j + 1) % sections
            part = classify(tm, j, i)
            if part:
                add(part, [(i, j), (i, jn), (i + 1, jn), (i + 1, j)])
    # End caps as triangle fans around the ring centre.
    for cap, i, flip in ((close_front, 0, True), (close_rear, len(ts) - 1, False)):
        if not cap:
            continue
        ring = grid[i]
        c = tuple(sum(p[k] for p in ring) / len(ring) for k in range(3))
        part = classify(ts[i], -1, i)
        for j in range(sections):
            jn = (j + 1) % sections
            tri = [(i, j), (i, jn), (-1, -1, c)]
            if flip:
                tri = tri[::-1]
            add(part, tri)
    return {k: (v, f) for k, (v, f, _) in parts.items()}


def join(objs, name):
    """Join objects into one mesh (keeps materials). Returns the joined object."""
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


def apply_modifiers(objs):
    for o in objs:
        if o.type != 'MESH' or not o.modifiers:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)


def wheel(name, radius, width, mats, col, rim_style='fivespoke'):
    """Tyre + rim + brake disc as one spinning object (origin at the hub, axis = X)."""
    r, w = radius, width
    rim_r = r * 0.66
    tyre = lathe([
        (rim_r, -w / 2 + 0.01), (r - 0.03, -w / 2), (r - 0.008, -w / 2 + 0.02), (r, -w / 4),
        (r, w / 4), (r - 0.008, w / 2 - 0.02), (r - 0.03, w / 2), (rim_r, w / 2 - 0.01),
    ], segments=36)
    t_obj = bm_object(name + '_tyre', tyre, [mats['Tyre']], col=col, smooth=True)

    parts = [t_obj]
    # Rim barrel and lip
    barrel = lathe([(rim_r, -w / 2 + 0.01), (rim_r - 0.015, -w / 2 + 0.03), (rim_r - 0.015, w / 2 - 0.05), (rim_r, w / 2 - 0.01)], 36)
    parts.append(bm_object(name + '_barrel', barrel, [mats['Rim']], col=col, smooth=True))
    face_x = w / 2 - 0.035  # outer face of the rim (towards +X, flipped for the right side later)
    hub = cylinder(name + '_hub', rim_r * 0.28, 0.05, (face_x - 0.01, 0, 0), mats['Rim'], col=col, segments=16)
    nut = cylinder(name + '_cap', rim_r * 0.12, 0.03, (face_x + 0.012, 0, 0), mats['Chrome'], col=col, segments=12)
    parts += [hub, nut]
    spokes = 5
    for k in range(spokes):
        a = 2 * math.pi * k / spokes
        s = box(name + f'_spoke{k}', (0.03, 0.05, rim_r * 0.78), (face_x - 0.012, 0, 0), mats['Rim'], col=col)
        # spoke runs radially in the YZ plane
        s.rotation_euler = (a, 0, 0)
        s.location = (face_x - 0.012, -math.sin(a) * rim_r * 0.5, math.cos(a) * rim_r * 0.5)
        parts.append(s)
    disc = cylinder(name + '_disc', rim_r * 0.82, 0.025, (-0.02, 0, 0), mats['Chrome'], col=col, segments=28)
    parts.append(disc)
    bpy.context.view_layer.update()
    apply_transforms(parts)
    return join(parts, name)


def apply_transforms(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def mirror_x(obj, name):
    """Duplicate an object mirrored across the car's centre line."""
    dup = obj.copy()
    dup.data = obj.data.copy()
    dup.name = name
    dup.data.name = name
    for c in obj.users_collection:
        c.objects.link(dup)
    me = dup.data
    for v in me.vertices:
        v.co.x = -v.co.x
    dup.location.x = -obj.location.x
    me.flip_normals()
    for k in obj.keys():
        dup[k] = obj[k]
    return dup


def export_glb(path, objs=None):
    if objs:
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
    kwargs = dict(filepath=path, export_format='GLB', export_extras=True, export_yup=True,
                  use_selection=bool(objs), export_apply=True)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    kwargs = {k: v for k, v in kwargs.items() if k in props}
    bpy.ops.export_scene.gltf(**kwargs)


def studio(target_height=0.6, cam_loc=(4.6, -5.4, 1.9), resolution=(1400, 800)):
    """Simple preview stage: ground, sun, sky colour and a 3/4 camera."""
    scene = bpy.context.scene
    for engine in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = resolution
    world = bpy.data.worlds.new('World')
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (0.55, 0.42, 0.36, 1)
    bg.inputs['Strength'].default_value = 0.7

    ground = mesh_object('Ground', [(-30, -30, 0), (30, -30, 0), (30, 30, 0), (-30, 30, 0)], [(0, 1, 2, 3)],
                         [material('Ground', (0.16, 0.16, 0.17), roughness=0.8)])
    ground['preview_only'] = 1
    sun = bpy.data.lights.new('Sun', 'SUN')
    sun.energy = 3.2
    sun.color = (1.0, 0.82, 0.62)
    sun_obj = bpy.data.objects.new('Sun', sun)
    sun_obj.rotation_euler = (math.radians(55), 0, math.radians(35))
    scene.collection.objects.link(sun_obj)
    fill = bpy.data.lights.new('Fill', 'AREA')
    fill.energy = 400
    fill.size = 6
    fill_obj = bpy.data.objects.new('Fill', fill)
    fill_obj.location = (-4, 3, 4)
    fill_obj.rotation_euler = (math.radians(-45), math.radians(-35), 0)
    scene.collection.objects.link(fill_obj)

    cam = bpy.data.cameras.new('Camera')
    cam.lens = 50
    cam_obj = bpy.data.objects.new('Camera', cam)
    cam_obj.location = cam_loc
    scene.collection.objects.link(cam_obj)
    target = Vector((0, 0, target_height))
    direction = target - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam_obj
    for o in (ground, sun_obj, fill_obj, cam_obj):
        o['preview_only'] = 1
    return cam_obj


# ---------------------------------------------------------------------------
# Angular modelling helpers
# ---------------------------------------------------------------------------

def densify(points, steps):
    """Polyline through `points` with `steps[i]` subdivisions per segment (keeps the corners)."""
    out = [points[0]]
    for (a, b), n in zip(zip(points, points[1:]), steps):
        for k in range(1, n + 1):
            f = k / n
            out.append(tuple(a[i] + (b[i] - a[i]) * f for i in range(len(a))))
    return out


def mark_sharp(obj, angle_deg=28):
    """Mark edges sharper than `angle_deg` so creases render crisp (exported as split normals)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    limit = math.radians(angle_deg)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > limit:
            e.smooth = False
        elif len(e.link_faces) < 2:
            e.smooth = False
    bm.to_mesh(obj.data)
    bm.free()
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def extrude_yz(name, profile, x0, x1, mat, col=None, props=None, location=(0, 0, 0)):
    """Extrude a closed (y, z) polygon along X from x0 to x1 (spoilers, splitters, sills)."""
    n = len(profile)
    verts = [(x0, y, z) for y, z in profile] + [(x1, y, z) for y, z in profile]
    faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    obj = mesh_object(name, verts, faces, [mat], col=col, props=props)
    obj.location = location
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def arc_band(name, center_yz, radius, thick, a0, a1, x_in, x_out, mat, col=None, steps=18, props=None):
    """A rectangular-section band following a circular arc in the YZ plane (wheel-arch flares)."""
    cy, cz = center_yz
    verts, faces = [], []
    for k in range(steps + 1):
        a = a0 + (a1 - a0) * k / steps
        ca, sa = math.cos(a), math.sin(a)
        for r, x in ((radius, x_in), (radius, x_out), (radius + thick, x_out), (radius + thick, x_in)):
            verts.append((x, cy + ca * r, cz + sa * r))
    for k in range(steps):
        b, c = k * 4, (k + 1) * 4
        for i in range(4):
            j = (i + 1) % 4
            faces.append((b + i, b + j, c + j, c + i))
    faces.append((0, 1, 2, 3)[::-1])
    faces.append(tuple(range(steps * 4, steps * 4 + 4)))
    obj = mesh_object(name, verts, faces, [mat], col=col, props=props)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return mark_sharp(obj, 40)


def torus_x(name, major, minor, location, mat, col=None, segments=32, ring=8, props=None):
    """Torus around the X axis (steering wheel, lamp bezels after rotation)."""
    profile = [(major + minor * math.cos(2 * math.pi * k / ring), minor * math.sin(2 * math.pi * k / ring))
               for k in range(ring + 1)]
    bm = lathe(profile, segments)
    return bm_object(name, bm, [mat], col=col, smooth=True, props=props, location=location)


def set_transparent(mat, alpha):
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Alpha'].default_value = alpha
    for attr, value in (('surface_render_method', 'BLENDED'), ('blend_method', 'BLEND')):
        try:
            setattr(mat, attr, value)
        except Exception:
            pass
