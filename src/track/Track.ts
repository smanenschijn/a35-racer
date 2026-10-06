import * as THREE from 'three';
import { ROAD } from '../config';

// Heading convention: forward = (sin θ, cos θ) in the XZ plane, so θ = 0 faces +Z.
// Increasing θ turns left; the right vector is (-cos θ, sin θ).

export interface TrackFrame {
  x: number;
  y: number;
  z: number;
  heading: number;
  fx: number;
  fz: number;
  rx: number;
  rz: number;
  curvature: number;
  slope: number; // dy/ds
}

export interface Projection {
  idx: number;
  s: number;
  d: number;
}

export interface Bridge {
  s0: number;
  s1: number;
  /** Over the Twentekanaal (water underneath) rather than over a road. */
  canal: boolean;
  height: number;
  ramp: number;
}

export interface Gantry {
  s: number;
  text: string[];
  route: string;
}

export interface Landmark {
  id: string;
  s: number;
  d: number;
  /** Real distance to the motorway in metres (they're pulled in so you can see them). */
  realDistance: number;
}

export interface TrackFeatures {
  startS: number;
  finishS: number;
  bridges: Bridge[];
  /** Roads crossing over the motorway. */
  viaducts: number[];
  gantries: Gantry[];
  exits: { s: number; name: string; ref: string }[];
  landmarks: Landmark[];
  /** Checkpoint gates (s) of the current stage, each one buys extra time. */
  checkpoints: number[];
  stages: Stage[];
  tunnels: { s0: number; s1: number }[];
  /** Single-carriageway stretches (oncoming traffic in the left lane). */
  single: { s0: number; s1: number }[];
  waters: { s: number; name: string; kind: string }[];
}

export interface Stage {
  id: number;
  from: string;
  to: string;
  startS: number;
  finishS: number;
}

/** Route file produced by tools/osm/build_campaign.py from OpenStreetMap data. */
export interface RouteData {
  name: string;
  source: string;
  realLength: number;
  length: number;
  curvature: number[];
  profile: { s0: number; s1: number; type: string }[];
  tunnels: { s0: number; s1: number }[];
  bridges: { s0: number; s1: number; canal: boolean; water: string }[];
  waters: { s: number; name: string; kind: string }[];
  overpasses: number[];
  exits: { s: number; name: string; ref: string }[];
  landmarks: Landmark[];
  stages: Stage[];
}

const smoothstep = (e0: number, e1: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
  return t * t * (3 - 2 * t);
};

/** Overhead signs ~350 m before each exit: the through destination and the exit itself. */
function gantriesFor(route: RouteData): Gantry[] {
  const out: Gantry[] = [];
  route.exits.forEach((e, i) => {
    const s = e.s - 350;
    if (s < route.stages[0].startS + 80 || out.some((g) => Math.abs(g.s - s) < 300)) return;
    // Through destination: the next big town further along the route.
    const ahead = route.stages.find((st) => st.finishS > e.s);
    const through = i >= route.exits.length - 1 ? 'Gronau (D)' : ahead && ahead.to !== e.name ? ahead.to : 'Enschede';
    const exitName = e.name.split(';')[0].trim();
    out.push({ s, text: [through, `${exitName}  ${e.ref.split(';')[0]}`], route: 'A35' });
  });
  return out;
}

export class Track {
  readonly spacing = ROAD.sampleSpacing;
  readonly count: number;
  readonly length: number;
  readonly features: TrackFeatures;
  readonly name: string;
  private xs: Float32Array;
  private zs: Float32Array;
  private ys: Float32Array;
  private hs: Float32Array;
  private ks: Float32Array;

  constructor(route: RouteData) {
    this.name = route.name;
    // Bridges before the first start line are left out so the grid stands on flat road.
    const bridges: Bridge[] = route.bridges
      .filter((b) => b.s0 > route.stages[0].startS + 150)
      .map((b) => ({ s0: b.s0, s1: b.s1, canal: b.canal, height: b.canal ? 7.5 : 6.5, ramp: b.canal ? 200 : 170 }));
    const st = route.stages[route.stages.length - 1];
    this.features = {
      startS: st.startS,
      finishS: st.finishS,
      bridges,
      viaducts: route.overpasses.filter((s) => s > 40 && s < route.length - 40 && !route.tunnels.some((t) => s > t.s0 - 30 && s < t.s1 + 30)),
      gantries: gantriesFor(route),
      exits: route.exits,
      landmarks: route.landmarks,
      checkpoints: [],
      stages: route.stages,
      tunnels: route.tunnels,
      single: route.profile.filter((p) => p.type === 'single').map((p) => ({ s0: p.s0, s1: p.s1 })),
      waters: route.waters,
    };
    this.singleMask = new Uint8Array(route.length + 2);
    for (const p of this.features.single) this.singleMask.fill(1, Math.max(0, p.s0), Math.min(route.length + 1, p.s1));
    this.setStage(route.stages.length - 1);

    // Integrate the curvature profile into a centreline (x/z), with heading and height.
    this.ks = new Float32Array(route.curvature);
    this.count = this.ks.length;
    this.length = (this.count - 1) * this.spacing;
    this.xs = new Float32Array(this.count);
    this.zs = new Float32Array(this.count);
    this.ys = new Float32Array(this.count);
    this.hs = new Float32Array(this.count);
    let x = 0;
    let z = 0;
    let h = 0;
    for (let i = 0; i < this.count; i++) {
      this.xs[i] = x;
      this.zs[i] = z;
      this.hs[i] = h;
      this.ys[i] = this.elevation(i * this.spacing);
      h += this.ks[i] * this.spacing;
      x += Math.sin(h) * this.spacing;
      z += Math.cos(h) * this.spacing;
    }
  }

  private singleMask: Uint8Array;
  stage: Stage = { id: 0, from: '', to: '', startS: 0, finishS: 0 };

  /** Make stage i (0-based) the current one: start/finish lines and checkpoints. */
  setStage(i: number): void {
    const st = this.features.stages[i];
    this.stage = st;
    this.features.startS = st.startS;
    this.features.finishS = st.finishS;
    this.features.checkpoints = [0.27, 0.52, 0.77].map((f) => Math.round(st.startS + (st.finishS - st.startS) * f));
  }

  /** One carriageway with oncoming traffic in the left lane? */
  isSingle(s: number): boolean {
    return this.singleMask[Math.max(0, Math.min(this.singleMask.length - 1, Math.round(s)))] === 1;
  }

  inTunnel(s: number, margin = 0): boolean {
    return this.features.tunnels.some((t) => s > t.s0 - margin && s < t.s1 + margin);
  }

  /** How much a bridge lifts the road at s (0..height). */
  bridgeLift(s: number): number {
    let lift = 0;
    for (const b of this.features.bridges) {
      const up = smoothstep(b.s0 - b.ramp, b.s0, s);
      const down = 1 - smoothstep(b.s1, b.s1 + b.ramp, s);
      lift = Math.max(lift, b.height * Math.min(up, down));
    }
    return lift;
  }

  private elevation(s: number): number {
    const bridge = this.bridgeLift(s);
    const roll = 0.9 * Math.sin(s / 240) + 0.5 * Math.sin(s / 97 + 1.3);
    // Flatten the gentle undulation where the road climbs onto a bridge.
    const flat = 1 - Math.min(1, bridge / 2);
    return 1.4 + roll * flat + bridge;
  }

  /** Interpolated frame at distance s along the centerline. */
  frame(s: number, out: TrackFrame = {} as TrackFrame): TrackFrame {
    const f = Math.min(Math.max(s / this.spacing, 0), this.count - 1.0001);
    const i = Math.floor(f);
    const t = f - i;
    const lerp = (a: Float32Array) => a[i] + (a[i + 1] - a[i]) * t;
    out.x = lerp(this.xs);
    out.z = lerp(this.zs);
    out.y = lerp(this.ys);
    out.heading = lerp(this.hs);
    out.curvature = lerp(this.ks);
    out.slope = (this.ys[i + 1] - this.ys[i]) / this.spacing;
    out.fx = Math.sin(out.heading);
    out.fz = Math.cos(out.heading);
    out.rx = -out.fz;
    out.rz = out.fx;
    return out;
  }

  heightAt(s: number): number {
    const f = Math.min(Math.max(s / this.spacing, 0), this.count - 1.0001);
    const i = Math.floor(f);
    return this.ys[i] + (this.ys[i + 1] - this.ys[i]) * (f - i);
  }

  curvatureAt(s: number): number {
    const i = Math.min(Math.max(Math.round(s / this.spacing), 0), this.count - 1);
    return this.ks[i];
  }

  /** World position for track coordinates (s, d), with optional height offset. */
  pointAt(s: number, d: number, up = 0, out = new THREE.Vector3()): THREE.Vector3 {
    const fr = this.frame(s, tmpFrame);
    return out.set(fr.x + fr.rx * d, fr.y + up, fr.z + fr.rz * d);
  }

  /**
   * Project a world XZ point onto the track. Uses hill climbing from the hint index,
   * which is safe because the road never comes close to itself.
   */
  project(x: number, z: number, hint = -1, out: Projection = { idx: 0, s: 0, d: 0 }): Projection {
    let i = hint;
    if (i < 0 || i >= this.count) {
      let best = Infinity;
      for (let j = 0; j < this.count; j += 4) {
        const dd = (this.xs[j] - x) ** 2 + (this.zs[j] - z) ** 2;
        if (dd < best) {
          best = dd;
          i = j;
        }
      }
    }
    const dist = (j: number) => (this.xs[j] - x) ** 2 + (this.zs[j] - z) ** 2;
    let cur = dist(i);
    for (let guard = 0; guard < 4000; guard++) {
      if (i + 1 < this.count && dist(i + 1) < cur) {
        i++;
        cur = dist(i);
      } else if (i > 0 && dist(i - 1) < cur) {
        i--;
        cur = dist(i);
      } else break;
    }
    // Refine within the segment around i.
    const h = this.hs[i];
    const fx = Math.sin(h);
    const fz = Math.cos(h);
    const dx = x - this.xs[i];
    const dz = z - this.zs[i];
    const along = dx * fx + dz * fz;
    out.idx = i;
    out.s = Math.min(Math.max(i * this.spacing + along, 0), this.length);
    out.d = dx * -fz + dz * fx;
    return out;
  }
}

const tmpFrame = {} as TrackFrame;
