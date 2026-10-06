"""
Turns OpenStreetMap data of the A35 (Hengelo -> Enschede, eastbound carriageway) into the
game's route file: a per-metre curvature profile plus features (bridges, overpasses, canal,
exits, landmarks) in track coordinates.

Real geometry, shortened: long near-straight stretches are compressed while every bend
keeps its real angle, so the road is recognisable but a stage still takes ~2 minutes.

  python3 tools/osm/build_route.py            -> src/track/routes/hengelo-enschede.json

Input snapshots (refresh with fetch.sh): tools/osm/a35_raw.json, tools/osm/features_raw.json
Map data (c) OpenStreetMap contributors, ODbL.
"""

import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'src', 'track', 'routes', 'hengelo-enschede.json')

START_WAY = 6672614          # southbound A35 at Hengelo-West, signed "Münster; Enschede; Hengelo-Zuid"
STRAIGHT_COMPRESS = 0.5      # near-straight road is shown at this fraction of its real length
STRAIGHT_RADIUS = 1400       # bends gentler than this radius count as "straight"
LEAD_IN = 420                # metres of road before the start line
LEAD_OUT = 160               # metres after the finish line


def load(name):
    with open(os.path.join(HERE, name)) as f:
        return json.load(f)['elements']


ways = [e for e in load('a35_raw.json') if e['type'] == 'way']
features = load('features_raw.json')

LAT0, LON0 = 52.235, 6.81
KX = math.cos(math.radians(LAT0)) * 111320.0
KY = 110540.0


def xy(p):
    """lat/lon -> local metres (x east, y north)."""
    return ((p['lon'] - LON0) * KX, (p['lat'] - LAT0) * KY)


# ---- 1. Chain the eastbound carriageway -----------------------------------------------
motorway = [w for w in ways if w['tags'].get('highway') == 'motorway']
by_start = {}
for w in motorway:
    g = w['geometry']
    by_start.setdefault((round(g[0]['lat'], 7), round(g[0]['lon'], 7)), []).append(w)


def heading(a, b):
    return math.atan2(b[0] - a[0], b[1] - a[1])  # compass: 0 = north, +90deg = east


chain = [next(w for w in motorway if w['id'] == START_WAY)]
used = {START_WAY}
while True:
    g = chain[-1]['geometry']
    key = (round(g[-1]['lat'], 7), round(g[-1]['lon'], 7))
    nxt = [w for w in by_start.get(key, []) if w['id'] not in used]
    if not nxt:
        break
    h0 = heading(xy(g[-2]), xy(g[-1]))

    def turn(w):
        gg = w['geometry']
        d = heading(xy(gg[0]), xy(gg[1])) - h0
        return abs(math.atan2(math.sin(d), math.cos(d)))

    w = min(nxt, key=turn)
    chain.append(w)
    used.add(w['id'])

pts = []
bridge_flags = []
for w in chain:
    for i, p in enumerate(w['geometry']):
        if pts and i == 0:
            continue
        pts.append(xy(p))
        bridge_flags.append(bool(w['tags'].get('bridge')))

# ---- 2. Resample at 1 m and smooth the heading ----------------------------------------
dense, dense_bridge = [pts[0]], [bridge_flags[0]]
for (a, b), fb in zip(zip(pts, pts[1:]), bridge_flags[1:]):
    seg = math.dist(a, b)
    n = max(1, int(seg))
    for k in range(1, n + 1):
        f = k / n
        dense.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
        dense_bridge.append(fb)
real_len = len(dense) - 1

head = [heading(dense[i], dense[i + 1]) for i in range(real_len)]
head.append(head[-1])
unwrapped = [head[0]]
for h in head[1:]:
    d = h - unwrapped[-1]
    unwrapped.append(unwrapped[-1] + math.atan2(math.sin(d), math.cos(d)))


def smooth(values, radius):
    out, n, acc = [], len(values), [0.0]
    for v in values:
        acc.append(acc[-1] + v)
    for i in range(n):
        a, b = max(0, i - radius), min(n, i + radius + 1)
        out.append((acc[b] - acc[a]) / (b - a))
    return out


psi = smooth(smooth(unwrapped, 40), 40)  # OSM nodes are kinked; smooth over ~80 m
k_real = [psi[i + 1] - psi[i] for i in range(real_len)] + [0.0]   # +: turning right (compass)

# ---- 3. Compress straights, keep bend angles ----------------------------------------
k_sm = smooth([abs(k) for k in k_real], 60)
factor = []
for k in k_sm:
    f = min(1.0, STRAIGHT_COMPRESS + (1 - STRAIGHT_COMPRESS) * (k * STRAIGHT_RADIUS))
    factor.append(f)
s_game = [0.0]
for f in factor[:-1]:
    s_game.append(s_game[-1] + f)
game_len = s_game[-1]

# Per game metre: curvature (track convention: right turn = negative heading change).
n_game = int(game_len)
curv = []
j = 0
for sg in range(n_game):
    while j < real_len - 1 and s_game[j + 1] < sg:
        j += 1
    curv.append(-k_real[j] / factor[j])


def to_game_s(i_real):
    return s_game[max(0, min(real_len, int(i_real)))]


def project(p):
    """Nearest point on the real route: (index, signed lateral offset, + = right of travel)."""
    best, bi = 1e18, 0
    for i in range(0, real_len, 3):
        d = (dense[i][0] - p[0]) ** 2 + (dense[i][1] - p[1]) ** 2
        if d < best:
            best, bi = d, i
    h = psi[bi]
    fx, fy = math.sin(h), math.cos(h)
    rx, ry = fy, -fx  # right of travel on the map (x east, y north)
    dx, dy = p[0] - dense[bi][0], p[1] - dense[bi][1]
    return bi, dx * rx + dy * ry


def intersections(geom):
    """Indices along the route where a polyline crosses it."""
    hits = []
    pts2 = [xy(p) for p in geom]
    for a, b in zip(pts2, pts2[1:]):
        for i in range(0, real_len - 2, 2):
            p, q = dense[i], dense[i + 2]
            d = (b[0] - a[0]) * (q[1] - p[1]) - (b[1] - a[1]) * (q[0] - p[0])
            if abs(d) < 1e-9:
                continue
            t = ((p[0] - a[0]) * (q[1] - p[1]) - (p[1] - a[1]) * (q[0] - p[0])) / d
            u = ((p[0] - a[0]) * (b[1] - a[1]) - (p[1] - a[1]) * (b[0] - a[0])) / d
            if 0 <= t <= 1 and 0 <= u <= 1:
                hits.append(i)
    return hits


# ---- 4. Features ----------------------------------------------------------------------
# Our own bridges (the A35 goes over something).
bridges, inside = [], False
for i, fb in enumerate(dense_bridge):
    if fb and not inside:
        start, inside = i, True
    elif not fb and inside:
        bridges.append([start, i])
        inside = False

canal_hits = []
for e in features:
    t = e.get('tags', {})
    if t.get('waterway') == 'canal' and t.get('name') in ('Twentekanaal', None) and 'geometry' in e:
        canal_hits += [(i, t.get('name')) for i in intersections(e['geometry'])]

# Roads crossing over us.
chain_ids = {w['id'] for w in chain}
overpasses = []
for e in features:
    t = e.get('tags', {})
    if e['type'] != 'way' or not t.get('bridge') or 'highway' not in t or e['id'] in chain_ids:
        continue
    if t.get('highway') in ('motorway', 'motorway_link') and 'A35' in t.get('ref', ''):
        continue
    if int(t.get('layer', '1')) < 1:
        continue
    for i in intersections(e['geometry']):
        if not dense_bridge[i]:
            overpasses.append((i, t.get('name') or t.get('ref') or t.get('highway')))

junctions = []
for e in features:
    t = e.get('tags', {})
    if e['type'] == 'node' and t.get('highway') == 'motorway_junction':
        i, d = project(xy(e))
        # Only our own carriageway's junctions (the other side's nodes sit ~20 m to the left).
        if -8 < d < 25 and 50 < i < real_len - 50:
            junctions.append((i, t.get('name'), t.get('ref')))


def first(name_part, key=None):
    for e in features:
        t = e.get('tags', {})
        if name_part in t.get('name', '') and (key is None or key(t)):
            if e['type'] == 'node':
                return (e['lat'], e['lon'])
            b = e['bounds']
            return ((b['minlat'] + b['maxlat']) / 2, (b['minlon'] + b['maxlon']) / 2)
    raise KeyError(name_part)


POIS = {
    'metropool': first('Metropool', lambda t: t.get('amenity') == 'nightclub' or t.get('building')),
    'utwente': first('Universiteit Twente'),
    'veste': first('Grolsch Veste'),
    'brouwerij': first('Koninklijke Grolsch'),
    'thuisbesteld': (52.2230948, 6.8867369),  # De Ruyterlaan 25, Enschede
}

# ---- 5. Start / finish window -----------------------------------------------------------
start_s = LEAD_IN
finish_s = n_game - LEAD_OUT

out_landmarks = []
for name, (lat, lon) in POIS.items():
    i, d = project(xy({'lat': lat, 'lon': lon}))
    sg = to_game_s(i)
    side = 1 if d > 0 else -1
    # Pull far-away landmarks in so they're visible from the motorway (arcade licence).
    dist = 70 + min(abs(d), 4000) * 0.045
    sg = min(max(sg, start_s + 120), finish_s - 60)
    out_landmarks.append({'id': name, 's': round(sg, 1), 'd': round(side * dist, 1), 'realDistance': round(abs(d)),
                          'realS': i})

route = {
    'name': 'A35 Hengelo → Enschede',
    'source': 'OpenStreetMap contributors (ODbL), snapshot ' + json.load(open(os.path.join(HERE, 'a35_raw.json')))['osm3s']['timestamp_osm_base'],
    'realLength': real_len,
    'length': n_game,
    'startS': start_s,
    'finishS': finish_s,
    'curvature': [round(k, 6) for k in curv],
    # Bridges before the start line are left out so the grid stands on flat road.
    'bridges': [{'s0': round(to_game_s(a)), 's1': round(to_game_s(b)), 'canal': any(a - 60 <= c <= b + 60 for c, _ in canal_hits)}
                for a, b in bridges if to_game_s(a) > start_s + 150],
    'canal': sorted({round(to_game_s(c)) for c, _ in canal_hits}),
    'overpasses': sorted({round(to_game_s(i)) for i, _ in overpasses}),
    'exits': sorted({(round(to_game_s(i)), n or '', r or '') for i, n, r in junctions}),
    'landmarks': out_landmarks,
}
route['exits'] = [{'s': s, 'name': n, 'ref': r} for s, n, r in route['exits']]
# Merge overpasses that are the same structure (two carriageways of a crossing road).
merged = []
for s in route['overpasses']:
    if not merged or s - merged[-1] > 25:
        merged.append(s)
route['overpasses'] = merged

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w') as f:
    json.dump(route, f, separators=(',', ':'))

print(f'chain: {len(chain)} ways, real length {real_len} m -> game length {n_game} m')
print('bridges', route['bridges'])
print('canal crossings', route['canal'])
print('overpasses', route['overpasses'])
print('exits', route['exits'])
for lm in out_landmarks:
    print('landmark', lm)
total_turn = sum(curv)
print(f'total heading change {math.degrees(total_turn):.1f} deg')
