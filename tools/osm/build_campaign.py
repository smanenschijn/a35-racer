"""
The whole race: N35 from Raalte, past Nijverdal, Wierden and Almelo onto the A35, through
Hengelo to Enschede, as one continuous road split into five stages at the towns.

Builds the whole route over the full road network:
  * the path is found with Dijkstra over the OSM road graph (dual carriageways only in the
    direction of travel, single carriageways both ways),
  * every metre carries its cross-section: 'dual' (separate carriageways, a median) or
    'single' (one carriageway, oncoming traffic in the left lane), plus tunnels and bridges,
  * straights are compressed, bends keep their real angle.

  python3 tools/osm/build_campaign.py  -> godot/assets/route/campaign.json

Inputs (OSM snapshots in this folder): n35_raw.json, n35_features_raw.json, a35_raw.json,
features_raw.json. Map data (c) OpenStreetMap contributors, ODbL.
"""

import heapq
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'godot', 'assets', 'route', 'campaign.json')

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
    lm('tokkolocco', 52.3710, 6.3757, near=34, scale=0.02),  # next to the BP in Haarle
    lm('ravijn', 52.3677, 6.4485),
    lm('gemeentehuis', 52.3643, 6.4614, shift=85),  # out of the tunnel's shadow
    lm('stoomweverij', 52.3635, 6.4700),
    lm('watertoren', 52.3577, 6.5955),
    lm('heraklus', *poi('Asito'), scale=0.02),
    lm('bauhaus', 52.28698, 6.76177, near=50, shift=-220),  # Westermaat: one after the other
    lm('ikea', 52.28876, 6.76785, near=50, shift=200),
    lm('metropool', *poi('Metropool') if False else (52.26122, 6.79458)),
    lm('veste', *poi('Grolsch Veste'), scale=0.02),
    lm('brouwerij', *poi('Koninklijke Grolsch')),
    lm('utwente', *poi('Universiteit Twente')),
    lm('thuisbesteld', 52.2230948, 6.8867369, scale=0.02),
]
# Keep landmarks inside their stage, away from the start/finish lines.
for item in landmarks:
    st = next((st for st in stages if st['startS'] <= item['s'] <= st['finishS']),
              stages[0] if item['s'] < stages[0]['startS'] else stages[-1] if item['s'] > stages[-1]['finishS'] else None)
    if st:
        item['s'] = min(max(item['s'], st['startS'] + 150), st['finishS'] - 80)

# ---- 7. Junctions, slip roads, railways and roadside points of interest ------------------
# junctions_raw.json: Overpass (junctions_query.overpassql) for traffic lights, side roads, slip roads and
# railways near the route; pois_raw.json: windmills, churches, towers, petrol stations... (pois_query).
extra = load('junctions_raw.json')['elements']
pois_raw = load('pois_raw.json')['elements']


def near_index(p, reach=150.0):
    """(i, d) of the closest centreline point, using the 50 m grid; None if further than reach."""
    cx, cy = int(p[0] // CELL), int(p[1] // CELL)
    r = int(reach // CELL) + 1
    best, bi = reach * reach, None
    for gx in range(cx - r, cx + r + 1):
        for gy in range(cy - r, cy + r + 1):
            for i in grid.get((gx, gy), ()):
                dd = (dense[i][0] - p[0]) ** 2 + (dense[i][1] - p[1]) ** 2
                if dd < best:
                    best, bi = dd, i
    if bi is None:
        return None
    h = psi[bi]
    fx, fy = math.sin(h), math.cos(h)
    dx, dy = p[0] - dense[bi][0], p[1] - dense[bi][1]
    return bi + int(dx * fx + dy * fy), dx * fy + dy * (-fx)


def far_index(p):
    """(i, d) for points kilometres away (brute force over every 10th point)."""
    best, bi = 1e18, 0
    for i in range(0, real_len, 10):
        dd = (dense[i][0] - p[0]) ** 2 + (dense[i][1] - p[1]) ** 2
        if dd < best:
            best, bi = dd, i
    h = psi[bi]
    fx, fy = math.sin(h), math.cos(h)
    dx, dy = p[0] - dense[bi][0], p[1] - dense[bi][1]
    return bi, dx * fy + dy * (-fx)


signals = []
for e in extra:
    if e['type'] == 'node' and e.get('tags', {}).get('highway') == 'traffic_signals':
        loc = near_index(xy(e['lat'], e['lon']), 60)
        if loc and abs(loc[1]) < 45 and 60 < loc[0] < real_len - 60:
            signals.append(loc[0])

ROAD_W = {'primary': 8.0, 'secondary': 7.5, 'tertiary': 6.5, 'unclassified': 5.5}
raw_j = []
for e in extra:
    t = e.get('tags', {})
    hw = t.get('highway')
    if e['type'] != 'way' or hw not in ROAD_W or e['id'] in route_way_ids:
        continue
    if t.get('bridge') or t.get('tunnel') or t.get('layer', '0') != '0':
        continue
    if 'N35' in t.get('ref', '') or 'A35' in t.get('ref', ''):
        continue
    loc = [near_index(xy(p['lat'], p['lon']), 220) for p in e['geometry']]
    on = [l for l in loc if l and abs(l[1]) < 9 and 60 < l[0] < real_len - 60]
    if not on:
        continue
    i0 = on[0][0]
    tg = dense_tags[min(real_len - 1, i0)]
    if tg.get('highway') == 'motorway' or tg.get('bridge') or tg.get('tunnel'):
        continue
    right = [l for l in loc if l and l[1] > 14 and abs(l[0] - i0) < 160]
    left = [l for l in loc if l and l[1] < -14 and abs(l[0] - i0) < 160]
    if not right and not left:
        continue
    # Skew of the side road: how far it runs along the route per metre away from it.
    far = (right or left)[-1]
    skew = math.atan2(far[0] - i0, abs(far[1]))
    raw_j.append({'i': i0, 'right': bool(right), 'left': bool(left), 'w': ROAD_W[hw], 'name': t.get('name', ''),
                  'skew': max(-0.6, min(0.6, skew))})

raw_j.sort(key=lambda j: j['i'])
junction_list = []
for j in raw_j:
    last = junction_list[-1] if junction_list else None
    if last and j['i'] - last['i'] < 45:
        last['right'] |= j['right']
        last['left'] |= j['left']
        last['w'] = max(last['w'], j['w'])
        if j['name'] and j['name'] not in last['names']:
            last['names'].append(j['name'])
        continue
    junction_list.append({**j, 'names': [j['name']] if j['name'] else []})

junctions = []
used_signals = set()
for j in junction_list:
    lit = [i for i in signals if abs(i - j['i']) < 70]
    used_signals.update(lit)
    junctions.append({'s': round(gs(j['i'])), 'right': j['right'], 'left': j['left'], 'width': j['w'],
                      'lights': bool(lit), 'skew': round(j['skew'], 3), 'kind': 'road', 'names': j['names'][:2]})
# Traffic lights with no side road: a signalled cycle/pedestrian crossing.
for i in sorted(set(signals) - used_signals):
    if dense_tags[i].get('highway') == 'motorway':
        continue
    s = round(gs(i))
    if not any(abs(s - j['s']) < 60 for j in junctions):
        junctions.append({'s': s, 'right': False, 'left': False, 'width': 4.0, 'lights': True, 'skew': 0.0,
                          'kind': 'cycle', 'names': []})
junctions.sort(key=lambda j: j['s'])

# Slip roads: links that leave (off) or join (on) our carriageway.
ramps = []
for e in extra:
    t = e.get('tags', {})
    if e['type'] != 'way' or t.get('highway') not in ('motorway_link', 'trunk_link', 'primary_link'):
        continue
    loc = [near_index(xy(p['lat'], p['lon']), 300) for p in e['geometry']]
    if not loc[0] or not loc[-1] or len(loc) < 2:
        continue
    kind = None
    if abs(loc[0][1]) < 12 and loc[-1][1] > 15 and loc[1][0] >= loc[0][0]:
        kind, at = 'off', loc[0][0]
    elif abs(loc[-1][1]) < 12 and loc[0][1] > 15 and loc[-1][0] >= loc[-2][0]:
        kind, at = 'on', loc[-1][0]
    if not kind or not (100 < at < real_len - 100) or dense_tags[at].get('tunnel'):
        continue
    s = round(gs(at))
    if not any(r['kind'] == kind and abs(r['s'] - s) < 150 for r in ramps):
        ramps.append({'s': s, 'kind': kind, 'side': 1})
# Not every slip road touches the route in the snapshot: every motorway exit has an off ramp where the
# junction node is, and (for a diamond) an on ramp a few hundred metres on.
for e in exits:
    if not any(r['kind'] == 'off' and abs(r['s'] - e['s']) < 250 for r in ramps):
        ramps.append({'s': e['s'], 'kind': 'off', 'side': 1})
    on_s = e['s'] + 420
    if on_s < n_game - 300 and not any(r['kind'] == 'on' and abs(r['s'] - on_s) < 350 for r in ramps):
        ramps.append({'s': on_s, 'kind': 'on', 'side': 1})
# Two exits close together (Enschede-West): no on ramp squeezed in between.
ramps = [r for r in ramps if r['kind'] == 'off' or not any(o['kind'] == 'off' and abs(o['s'] - r['s']) < 260 for o in ramps)]
ramps.sort(key=lambda r: r['s'])

# Railways crossing the route: over it, under it (our bridge) or at grade.
railways = []
for e in extra:
    t = e.get('tags', {})
    if e['type'] != 'way' or t.get('railway') not in ('rail', 'light_rail'):
        continue
    for i in intersections(e['geometry']):
        s = round(gs(i))
        if any(abs(s - r['s']) < 40 for r in railways):
            continue
        if t.get('bridge') or t.get('layer', '0') not in ('0', '-1'):
            kind = 'over'
        elif dense_tags[i].get('bridge'):
            kind = 'under'
        elif t.get('tunnel'):
            continue
        else:
            kind = 'level'
        railways.append({'s': s, 'kind': kind, 'name': t.get('name', '')})
railways.sort(key=lambda r: r['s'])
for b in bridges:
    if not b['canal'] and any(r['kind'] == 'under' and b['s0'] - 60 <= r['s'] <= b['s1'] + 60 for r in railways):
        b['rail'] = True

FUEL = {'Shell': 'Shall', 'BP': 'BV', 'Esso': 'Esse', 'TotalEnergies': 'TotaalEnergie', 'Total': 'TotaalEnergie',
        'Tinq': 'Tanq', 'Tango': 'Tanga', 'Texaco': 'Texako', 'Avia': 'Avio', 'Gulf': 'Golf', 'Argos': 'Argus',
        'Firezone': 'Vuurzone', 'Q8': 'K8'}
FOOD = {"McDonald's": "McDuck's", 'Burger King': 'Burger Koning', 'KFC': 'TFC', 'Subway': 'Subwee'}
pois = []
for e in pois_raw:
    t = e.get('tags', {})
    c = e.get('center') or ({'lat': e['lat'], 'lon': e['lon']} if 'lat' in e else None)
    if not c:
        continue
    kind, reach, name = None, 0, t.get('name', '')
    if t.get('man_made') == 'windmill' or t.get('historic') == 'windmill':
        kind, reach = 'molen', 5000
    elif (t.get('building') == 'church' or (t.get('amenity') == 'place_of_worship' and t.get('religion') == 'christian')) and name:
        kind, reach = 'kerk', 1400
    elif t.get('man_made') == 'water_tower':
        kind, reach = 'watertoren', 2600
    elif t.get('amenity') == 'fuel':
        kind, reach, name = 'tank', 160, FUEL.get(t.get('brand', ''), 'Tankstation')
    elif t.get('amenity') == 'fast_food' and t.get('brand') in FOOD:
        kind, reach, name = 'snack', 450, FOOD[t['brand']]
    elif t.get('man_made') in ('mast', 'tower') and float((t.get('height') or '0').split()[0].replace(',', '.') or 0) >= 60:
        kind, reach = 'mast', 4000
    elif t.get('man_made') == 'chimney':
        kind, reach = 'schoorsteen', 2200
    elif t.get('tourism') == 'theme_park' and name in ('Avonturenpark Hellendoorn', 'De Waarbeek'):
        kind, reach = 'pretpark', 6000
    if not kind:
        continue
    loc = near_index(xy(c['lat'], c['lon']), reach) if reach <= 500 else far_index(xy(c['lat'], c['lon']))
    if not loc or abs(loc[1]) > reach or not (150 < loc[0] < real_len - 150):
        continue
    i, d = loc
    side = 1 if d > 0 else -1
    if kind in ('tank', 'snack'):
        gd = side * (24 + min(abs(d), 400) * 0.08)
    elif kind in ('mast', 'pretpark'):
        gd = side * (220 + min(abs(d), 6000) * 0.04)
    elif kind == 'molen':
        gd = side * (90 + min(abs(d), 5000) * 0.04)
    else:
        gd = side * (70 + min(abs(d), 3000) * 0.06)
    pois.append({'kind': kind, 's': round(gs(i)), 'd': round(gd, 1), 'name': name, 'real': round(abs(d))})
# Keep it readable: one of each kind per 600 m (the closest wins), and not on top of a landmark.
pois.sort(key=lambda p: p['real'])
kept = []
for p in pois:
    if any(k['kind'] == p['kind'] and abs(k['s'] - p['s']) < 600 for k in kept):
        continue
    if any(abs(l['s'] - p['s']) < 220 and (l['d'] > 0) == (p['d'] > 0) for l in landmarks):
        continue
    if p['kind'] == 'watertoren' and any(l['id'] == 'watertoren' and abs(l['s'] - p['s']) < 900 for l in landmarks):
        continue
    kept.append(p)
pois = sorted(kept, key=lambda p: p['s'])

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
    'junctions': junctions,
    'ramps': ramps,
    'railways': railways,
    'pois': pois,
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
print('junctions', len(junctions), [(j['s'], j['kind'], 'L' if j['left'] else '', 'R' if j['right'] else '', 'lights' if j['lights'] else '', j['names']) for j in junctions])
print('ramps', ramps)
print('railways', railways)
from collections import Counter
print('pois', Counter(p['kind'] for p in pois))
for p in pois:
    print('  poi', p)
