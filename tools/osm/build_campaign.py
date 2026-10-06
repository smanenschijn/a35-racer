"""
The whole race: N35 from Raalte, past Nijverdal, Wierden and Almelo onto the A35, through
Hengelo to Enschede, as one continuous road split into five stages at the towns.

Builds the whole route over the full road network:
  * the path is found with Dijkstra over the OSM road graph (dual carriageways only in the
    direction of travel, single carriageways both ways),
  * every metre carries its cross-section: 'dual' (separate carriageways, a median) or
    'single' (one carriageway, oncoming traffic in the left lane), plus tunnels and bridges,
  * straights are compressed, bends keep their real angle.

  python3 tools/osm/build_campaign.py  -> src/track/routes/campaign.json

Inputs (OSM snapshots in this folder): n35_raw.json, n35_features_raw.json, a35_raw.json,
features_raw.json. Map data (c) OpenStreetMap contributors, ODbL.
"""

import heapq
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'src', 'track', 'routes', 'campaign.json')

STRAIGHT_COMPRESS = 0.5
STRAIGHT_RADIUS = 1400
LEAD_IN = 300
LEAD_OUT = 160
HENGELO_WEST = (52.2701288, 6.7497857)  # where stage 5 (the original stage) begins

LAT0, LON0 = 52.33, 6.55
KX = math.cos(math.radians(LAT0)) * 111320.0
KY = 110540.0


def load(name):
    with open(os.path.join(HERE, name)) as f:
        return json.load(f)


def xy(lat, lon):
    return ((lon - LON0) * KX, (lat - LAT0) * KY)


def key(p):
    return (round(p['lat'], 7), round(p['lon'], 7))


n35 = load('n35_raw.json')
snapshot = n35['osm3s']['timestamp_osm_base']
elements = n35['elements'] + [e for e in load('a35_raw.json')['elements'] if e['type'] == 'way']
features = load('n35_features_raw.json')['elements'] + load('features_raw.json')['elements']

ROADS = ('motorway', 'trunk', 'primary')


def usable(w):
    t = w['tags']
    ref = t.get('ref', '')
    return (w['type'] == 'way' and t.get('highway') in ROADS and
            any(r in ref.split(';') for r in ('N35', 'A35')))


ways = {}
for w in elements:
    if usable(w):
        ways[w['id']] = w

# ---- 1. Graph and shortest path ------------------------------------------------------
graph = {}
coords = {}
for w in ways.values():
    g = w['geometry']
    oneway = w['tags'].get('oneway') in ('yes', '1', 'true') or w['tags'].get('highway') == 'motorway'
    for i in range(len(g) - 1):
        a, b = key(g[i]), key(g[i + 1])
        coords[a], coords[b] = g[i], g[i + 1]
        pa, pb = xy(*a), xy(*b)
        length = math.dist(pa, pb)
        graph.setdefault(a, []).append((b, length, w['id']))
        if not oneway:
            graph.setdefault(b, []).append((a, length, w['id']))


def nearest(lat, lon):
    p = xy(lat, lon)
    return min(graph, key=lambda k: math.dist(xy(*k), p))


raalte = next(e for e in features + n35['elements'] if e['type'] == 'node' and e.get('tags', {}).get('name') == 'Raalte')
start = nearest(raalte['lat'], raalte['lon'])
end = nearest(*HENGELO_WEST)

dist = {start: 0.0}
prev = {}
pq = [(0.0, start)]
while pq:
    d, u = heapq.heappop(pq)
    if u == end:
        break
    if d > dist.get(u, 1e18):
        continue
    for v, length, wid in graph.get(u, []):
        nd = d + length
        if nd < dist.get(v, 1e18):
            dist[v] = nd
            prev[v] = (u, wid)
            heapq.heappush(pq, (nd, v))
assert end in prev, 'no path from Raalte to Hengelo-West'

path = [end]
path_ways = []
while path[-1] != start:
    u, wid = prev[path[-1]]
    path.append(u)
    path_ways.append(wid)
path.reverse()
path_ways.reverse()

# ---- 2. Stage 5: the original A35 chain from Hengelo-West ----------------------------
a35 = [w for w in load('a35_raw.json')['elements'] if w['type'] == 'way' and w['tags'].get('highway') == 'motorway']
by_start = {}
for w in a35:
    by_start.setdefault(key(w['geometry'][0]), []).append(w)


def heading(a, b):
    return math.atan2(b[0] - a[0], b[1] - a[1])


chain = [next(w for w in a35 if w['id'] == 6672614)]
used = {6672614}
while True:
    g = chain[-1]['geometry']
    nxt = [w for w in by_start.get(key(g[-1]), []) if w['id'] not in used]
    if not nxt:
        break
    h0 = heading(xy(*key(g[-2])), xy(*key(g[-1])))
    w = min(nxt, key=lambda w: abs(math.atan2(math.sin(heading(xy(*key(w['geometry'][0])), xy(*key(w['geometry'][1]))) - h0),
                                              math.cos(heading(xy(*key(w['geometry'][0])), xy(*key(w['geometry'][1]))) - h0))))
    chain.append(w)
    used.add(w['id'])

# Assemble points with the tags of the way each segment belongs to.
pts, seg_tags = [xy(*path[0])], []
for node, wid in zip(path[1:], path_ways):
    pts.append(xy(*node))
    seg_tags.append(ways[wid]['tags'])
join_index_points = len(pts) - 1
for w in chain:
    g = w['geometry']
    for p in g[1:]:
        pts.append(xy(*key(p)))
        seg_tags.append(w['tags'])

# ---- 3. Resample at 1 m ------------------------------------------------------------------
dense = [pts[0]]
dense_tags = [seg_tags[0]]
join_real = 0
for idx, ((a, b), t) in enumerate(zip(zip(pts, pts[1:]), seg_tags)):
    n = max(1, int(math.dist(a, b)))
    for k in range(1, n + 1):
        f = k / n
        dense.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
        dense_tags.append(t)
    if idx == join_index_points - 1:
        join_real = len(dense) - 1
real_len = len(dense) - 1

head = [heading(dense[i], dense[i + 1]) for i in range(real_len)] + [0.0]
head[-1] = head[-2]
unwrapped = [head[0]]
for h in head[1:]:
    d = h - unwrapped[-1]
    unwrapped.append(unwrapped[-1] + math.atan2(math.sin(d), math.cos(d)))


def smooth(values, radius):
    acc = [0.0]
    for v in values:
        acc.append(acc[-1] + v)
    n = len(values)
    return [(acc[min(n, i + radius + 1)] - acc[max(0, i - radius)]) / (min(n, i + radius + 1) - max(0, i - radius))
            for i in range(n)]


psi = smooth(smooth(unwrapped, 40), 40)
k_real = [psi[i + 1] - psi[i] for i in range(real_len)] + [0.0]

# ---- 4. Compression ----------------------------------------------------------------------
k_sm = smooth([abs(k) for k in k_real], 60)
factor = [min(1.0, STRAIGHT_COMPRESS + (1 - STRAIGHT_COMPRESS) * (k * STRAIGHT_RADIUS)) for k in k_sm]
s_game = [0.0]
for f in factor[:-1]:
    s_game.append(s_game[-1] + f)
n_game = int(s_game[-1])
curv = []
j = 0
for sg in range(n_game):
    while j < real_len - 1 and s_game[j + 1] < sg:
        j += 1
    curv.append(round(-k_real[j] / factor[j], 6))


def gs(i):
    return s_game[max(0, min(real_len, int(i)))]


def project(p):
    best, bi = 1e18, 0
    for i in range(0, real_len, 3):
        d = (dense[i][0] - p[0]) ** 2 + (dense[i][1] - p[1]) ** 2
        if d < best:
            best, bi = d, i
    h = psi[bi]
    fx, fy = math.sin(h), math.cos(h)
    dx, dy = p[0] - dense[bi][0], p[1] - dense[bi][1]
    return bi, dx * fy + dy * (-fx)


def runs(flag):
    """[s0, s1] ranges (game metres) where flag(tags) holds."""
    out, inside, s0 = [], False, 0
    for i, t in enumerate(dense_tags):
        f = flag(t)
        if f and not inside:
            s0, inside = i, True
        elif not f and inside:
            out.append([round(gs(s0)), round(gs(i))])
            inside = False
    if inside:
        out.append([round(gs(s0)), round(gs(real_len))])
    return out


def is_dual(t):
    return t.get('highway') == 'motorway' or t.get('oneway') in ('yes', '1', 'true')


# Cross-section runs: merge very short single/dual flickers (slip roads, junction islands).
profile = []
for a, b in runs(lambda t: not is_dual(t)):
    # Junction islands make short "dual" flickers inside single stretches: bridge gaps < 400 m.
    if profile and a - profile[-1]['s1'] < 400:
        profile[-1]['s1'] = b
    else:
        profile.append({'s0': a, 's1': b, 'type': 'single'})
profile = [p for p in profile if p['s1'] - p['s0'] >= 300]
tunnels = [{'s0': a, 's1': b} for a, b in runs(lambda t: t.get('tunnel') in ('yes', 'building_passage')) if b - a > 15]
bridges_real = runs(lambda t: bool(t.get('bridge')))


CELL = 50.0
grid = {}
for i in range(0, real_len - 2, 2):
    grid.setdefault((int(dense[i][0] // CELL), int(dense[i][1] // CELL)), []).append(i)


def intersections(geom):
    hits = []
    p2 = [xy(p['lat'], p['lon']) for p in geom]
    for a, b in zip(p2, p2[1:]):
        cx0, cx1 = int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 1
        cy0, cy1 = int(min(a[1], b[1]) // CELL) - 1, int(max(a[1], b[1]) // CELL) + 1
        if (cx1 - cx0) * (cy1 - cy0) > 4000:
            continue
        cand = [i for cx in range(cx0, cx1 + 1) for cy in range(cy0, cy1 + 1) for i in grid.get((cx, cy), ())]
        for i in cand:
            p, q = dense[i], dense[i + 2]
            d = (b[0] - a[0]) * (q[1] - p[1]) - (b[1] - a[1]) * (q[0] - p[0])
            if abs(d) < 1e-9:
                continue
            t = ((p[0] - a[0]) * (q[1] - p[1]) - (p[1] - a[1]) * (q[0] - p[0])) / d
            u = ((p[0] - a[0]) * (b[1] - a[1]) - (p[1] - a[1]) * (b[0] - a[0])) / d
            if 0 <= t <= 1 and 0 <= u <= 1:
                hits.append(i)
    return hits


route_way_ids = set(path_ways) | {w['id'] for w in chain}
waters = []
overpasses = []
seen = set()
for e in features:
    if e['type'] != 'way' or e['id'] in seen or 'geometry' not in e:
        continue
    seen.add(e['id'])
    t = e.get('tags', {})
    if t.get('waterway') in ('canal', 'river') and t.get('name'):
        for i in intersections(e['geometry']):
            waters.append((round(gs(i)), t['name'], t['waterway']))
    elif t.get('bridge') and 'highway' in t and e['id'] not in route_way_ids and int(t.get('layer', '1')) >= 1:
        if 'A35' in t.get('ref', '') or 'N35' in t.get('ref', ''):
            continue
        for i in intersections(e['geometry']):
            if not dense_tags[i].get('bridge') and not dense_tags[i].get('tunnel'):
                overpasses.append(round(gs(i)))
overpasses = sorted(set(overpasses))
merged = []
for s in overpasses:
    if not merged or s - merged[-1] > 30:
        merged.append(s)

# Our bridges: water underneath if a waterway crosses within the span.
bridges = []
for a, b in bridges_real:
    names = [n for s, n, _ in waters if a - 60 <= s <= b + 60]
    bridges.append({'s0': a, 's1': b, 'canal': bool(names), 'water': names[0] if names else ''})

junctions = []
for e in features:
    t = e.get('tags', {})
    if e['type'] == 'node' and t.get('highway') == 'motorway_junction':
        i, d = project(xy(e['lat'], e['lon']))
        if -8 < d < 25 and 50 < i < real_len - 50:
            junctions.append((round(gs(i)), t.get('name') or '', t.get('ref') or ''))
exits = []
for s, n, r in sorted(set(junctions)):
    if n and not n.startswith('Knooppunt') and not any(abs(s - e['s']) < 250 for e in exits):
        exits.append({'s': s, 'name': n, 'ref': r})

# ---- 5. Stages -------------------------------------------------------------------------
towns = {e['tags']['name']: (e['lat'], e['lon']) for e in features + n35['elements']
         if e['type'] == 'node' and e.get('tags', {}).get('place') and 'name' in e.get('tags', {})}


def town_s(name):
    i, _ = project(xy(*towns[name]))
    return round(gs(i))


hengelo_s = round(gs(join_real)) + 420


def clear_spot(s):
    """Move a stage boundary forward until the grid isn't on a bridge ramp or in a tunnel."""
    for _ in range(30):
        busy = any(b['s0'] - 260 < s < b['s1'] + 240 for b in bridges) or \
            any(t['s0'] - 150 < s < t['s1'] + 150 for t in tunnels)
        if not busy:
            return s
        s += 50
    return s


bounds = [clear_spot(LEAD_IN), clear_spot(town_s('Nijverdal')), clear_spot(town_s('Wierden')),
          clear_spot(town_s('Almelo')), hengelo_s, n_game - LEAD_OUT]
names = ['Raalte', 'Nijverdal', 'Wierden', 'Almelo', 'Hengelo', 'Enschede']
stages = []
for k in range(5):
    stages.append({'id': k + 1, 'from': names[k], 'to': names[k + 1], 'startS': bounds[k] + (0 if k == 0 else 40),
                   'finishS': bounds[k + 1] - (0 if k == 4 else 20)})

# ---- 6. Landmarks ------------------------------------------------------------------------


def lm(id_, lat, lon, near=70, scale=0.045, shift=0):
    i, d = project(xy(lat, lon))
    side = 1 if d > 0 else -1
    return {'id': id_, 's': round(gs(i) + shift, 1), 'd': round(side * (near + min(abs(d), 4000) * scale), 1),
            'realDistance': round(abs(d))}


def poi(name_part):
    for e in features:
        t = e.get('tags', {})
        if name_part in t.get('name', ''):
            if e['type'] == 'node':
                return e['lat'], e['lon']
            b = e['bounds']
            return (b['minlat'] + b['maxlat']) / 2, (b['minlon'] + b['maxlon']) / 2
    raise KeyError(name_part)


landmarks = [
    lm('raadhuis', *poi('Gemeentehuis Raalte')),
    lm('heuvelrug', 52.343, 6.462, near=380, scale=0.02),
    lm('ravijn', 52.3677, 6.4485),
    lm('gemeentehuis', 52.3643, 6.4614, shift=85),  # out of the tunnel's shadow
    lm('stoomweverij', 52.3635, 6.4700),
    lm('watertoren', 52.3577, 6.5955),
    lm('heraklus', *poi('Asito')),
    lm('metropool', *poi('Metropool') if False else (52.26122, 6.79458)),
    lm('veste', *poi('Grolsch Veste')),
    lm('brouwerij', *poi('Koninklijke Grolsch')),
    lm('utwente', *poi('Universiteit Twente')),
    lm('thuisbesteld', 52.2230948, 6.8867369),
]
# Keep landmarks inside their stage, away from the start/finish lines.
for item in landmarks:
    st = next((st for st in stages if st['startS'] <= item['s'] <= st['finishS']), stages[0] if item['s'] < stages[0]['startS'] else None)
    if st:
        item['s'] = min(max(item['s'], st['startS'] + 150), st['finishS'] - 80)

route = {
    'name': 'N35 / A35 Raalte → Enschede',
    'source': 'OpenStreetMap contributors (ODbL), snapshot ' + snapshot,
    'realLength': real_len,
    'length': n_game,
    'curvature': curv,
    'profile': profile,
    'tunnels': tunnels,
    'bridges': bridges,
    'waters': [{'s': s, 'name': n, 'kind': k} for s, n, k in sorted(set(waters))],
    'overpasses': merged,
    'exits': exits,
    'landmarks': landmarks,
    'stages': stages,
}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w') as f:
    json.dump(route, f, separators=(',', ':'))

print(f'path: {len(path_ways)} segments + {len(chain)} A35 ways; real {real_len} m -> game {n_game} m')
for st in stages:
    print(f"stage {st['id']} {st['from']} -> {st['to']}: {st['startS']}..{st['finishS']} ({st['finishS'] - st['startS']} m)")
single = sum(p['s1'] - p['s0'] for p in profile)
print(f'single carriageway: {single} m in {len(profile)} runs; tunnels {tunnels}')
print('bridges', bridges)
print('waters', route['waters'][:12])
print('overpasses', len(merged), 'exits', [(e['s'], e['name']) for e in exits])
for l in landmarks:
    print('landmark', l)
