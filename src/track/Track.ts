import * as THREE from 'three';
import { ROAD } from '../config';

// Heading convention: forward = (sin θ, cos θ) in the XZ plane, so θ = 0 faces +Z.
// Increasing θ turns left; the right vector is (-cos θ, sin θ).

export interface TrackSegment {
  length: number;
  /** Total heading change in degrees. Positive = right turn. */
  turn?: number;
}

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

export interface TrackFeatures {
  startS: number;
  finishS: number;
  viaducts: number[];
  bridge: { center: number; rampLength: number; topLength: number; height: number };
  gantries: { s: number; text: string[]; route: string }[];
}

// Testbed: an A35-like stretch (Hengelo-Zuid → Enschede-West, grey box).
const SEGMENTS: TrackSegment[] = [
  { length: 320 },
  { length: 360, turn: 24 },
  { length: 240 },
  { length: 320, turn: -42 },
  { length: 220 },
  { length: 200, turn: 28 },
  { length: 200, turn: -28 },
  { length: 360 },
  { length: 360, turn: 46 },
  { length: 160 },
  { length: 260, turn: -18 },
  { length: 380 },
];

export const FEATURES: TrackFeatures = {
  startS: 70,
  finishS: 0, // filled in after build
  viaducts: [1190, 2780],
  bridge: { center: 2050, rampLength: 190, topLength: 80, height: 7.5 },
  gantries: [
    { s: 420, text: ['Enschede', 'Hengelo-Zuid'], route: 'A35' },
    { s: 1650, text: ['Enschede-West', 'Boekelo'], route: 'A35' },
    { s: 2600, text: ['Enschede', 'Gronau (D)'], route: 'A35' },
  ],
};

const smoothstep = (e0: number, e1: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
  return t * t * (3 - 2 * t);
};

export class Track {
  readonly spacing = ROAD.sampleSpacing;
  readonly count: number;
  readonly length: number;
  readonly features: TrackFeatures;
  private xs: Float32Array;
  private zs: Float32Array;
  private ys: Float32Array;
  private hs: Float32Array;
  private ks: Float32Array;

  constructor(segments: TrackSegment[] = SEGMENTS) {
    // Build per-meter curvature with clothoid-like ramps in and out of each curve.
    const curv: number[] = [];
    for (const seg of segments) {
      const n = Math.round(seg.length / ROAD.sampleSpacing);
      const turnRad = (-(seg.turn ?? 0) * Math.PI) / 180; // right turn = decreasing heading
      const ramp = Math.min(70, seg.length / 3);
      const peak = turnRad / (seg.length - ramp);
      for (let i = 0; i < n; i++) {
        const s = i * ROAD.sampleSpacing;
        let k = peak;
        if (s < ramp) k = peak * (s / ramp);
        else if (s > seg.length - ramp) k = peak * ((seg.length - s) / ramp);
        curv.push(seg.turn ? k : 0);
      }
    }
    this.count = curv.length;
    this.length = (this.count - 1) * this.spacing;
    this.xs = new Float32Array(this.count);
    this.zs = new Float32Array(this.count);
    this.ys = new Float32Array(this.count);
    this.hs = new Float32Array(this.count);
    this.ks = new Float32Array(curv);

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
    this.features = { ...FEATURES, finishS: this.length - 120 };
  }

  private elevation(s: number): number {
    const b = FEATURES.bridge;
    const half = b.topLength / 2;
    const up = smoothstep(b.center - half - b.rampLength, b.center - half, s);
    const down = 1 - smoothstep(b.center + half, b.center + half + b.rampLength, s);
    const bridge = b.height * Math.min(up, down);
    const roll = 0.9 * Math.sin(s / 240) + 0.5 * Math.sin(s / 97 + 1.3);
    // Flatten the undulation near the bridge so the deck stays level.
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
