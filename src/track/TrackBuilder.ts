import * as THREE from 'three';
import type { Track } from './Track';
import { chunkInstances, freezeStatic, mergeStaticByCell } from './chunks';
import {
  facadeTextures,
  singleRoadTexture,
  roadTexture, grassTexture, fieldTexture, concreteTexture, checkerTexture, signTexture,
  placeSignTexture, bannerTexture,
} from './textures';

// Builds the grey-box A35 environment: two carriageways, rails, verges, embankments,
// a canal bridge, overpasses, sign gantries, lamps, trees and farms.

type Fn = (s: number) => number;

interface RibbonOpts {
  s0?: number;
  s1?: number;
  step?: number;
  dL: Fn | number;
  dR: Fn | number;
  yL: Fn;
  yR: Fn;
  uL?: number;
  uR?: number;
  vScale?: number; // meters per texture repeat along the road
}

const fn = (v: Fn | number): Fn => (typeof v === 'number' ? () => v : v);

// Median between the carriageways.
const OPP_IN = -8.5; // inner edge of the opposite carriageway surface
const OPP_OUT = -20.5;

export class TrackBuilder {
  readonly group = new THREE.Group();
  private track: Track;
  private spans: { c: number; half: number; canal: boolean }[] = [];
  /** Canal water planes (s, transform, width), used to sail the barge. */
  readonly canals: { s: number; holder: THREE.Group; width: number }[] = [];
  private tmp = new THREE.Vector3();

  constructor(track: Track) {
    this.track = track;
  }

  private ribbon(o: RibbonOpts, material: THREE.Material): THREE.Mesh {
    const t = this.track;
    const s0 = o.s0 ?? 0;
    const s1 = o.s1 ?? t.length;
    const step = o.step ?? 2;
    const dL = fn(o.dL);
    const dR = fn(o.dR);
    const rows = Math.max(2, Math.ceil((s1 - s0) / step) + 1);
    const pos = new Float32Array(rows * 2 * 3);
    const uv = new Float32Array(rows * 2 * 2);
    const idx: number[] = [];
    const vScale = o.vScale ?? 12;
    for (let r = 0; r < rows; r++) {
      const s = Math.min(s1, s0 + r * step);
      t.pointAt(s, dL(s), 0, this.tmp);
      pos.set([this.tmp.x, o.yL(s), this.tmp.z], r * 6);
      t.pointAt(s, dR(s), 0, this.tmp);
      pos.set([this.tmp.x, o.yR(s), this.tmp.z], r * 6 + 3);
      uv.set([o.uL ?? 0, s / vScale, o.uR ?? 1, s / vScale], r * 4);
      if (r > 0) {
        const a = (r - 1) * 2;
        const b = r * 2;
        idx.push(a, a + 1, b, a + 1, b + 1, b);
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    const mesh = new THREE.Mesh(geo, material);
    mesh.receiveShadow = true;
    this.group.add(mesh);
    return mesh;
  }

  build(): THREE.Group {
    const t = this.track;
    const h = (s: number) => t.heightAt(s);
    const f = t.features;
    // Open spans under each bridge (no embankment there: water or a road passes underneath).
    const spans = f.bridges.map((b) => {
      const c = (b.s0 + b.s1) / 2;
      const half = Math.max(24, (b.s1 - b.s0) / 2 + 4);
      return { c, half, canal: b.canal };
    });
    this.spans = spans;

    // --- Materials ---
    const roadTex = roadTexture();
    const road = new THREE.MeshStandardMaterial({ map: roadTex, roughness: 0.82, metalness: 0.05 });
    const grassTex = grassTexture();
    grassTex.repeat.set(1, 1);
    const grass = new THREE.MeshStandardMaterial({ map: grassTex, roughness: 1 });
    const concreteTex = concreteTexture();
    const concrete = new THREE.MeshStandardMaterial({ map: concreteTex, roughness: 0.9 });
    const metal = new THREE.MeshStandardMaterial({ color: 0xb8bcc0, metalness: 0.85, roughness: 0.35, side: THREE.DoubleSide });

    // Cross-section runs: 'dual' (motorway-style, separate carriageways) and 'single'
    // (one carriageway, oncoming traffic in the left lane, no median).
    const singles = f.single;
    const duals: [number, number][] = [];
    let at = 0;
    for (const r of singles) {
      if (r.s0 > at) duals.push([at, r.s0]);
      at = r.s1;
    }
    if (at < t.length) duals.push([at, t.length]);
    const roadSingle = new THREE.MeshStandardMaterial({ map: singleRoadTexture(), roughness: 0.82, metalness: 0.05 });

    // --- Road surfaces ---
    for (const [s0, s1] of duals) {
      this.ribbon({ s0, s1, dL: -6, dR: 6, yL: h, yR: h, step: 2 }, road);
      // Left edge must have the smaller d, otherwise the surface faces down and gets culled.
      // u runs 1→0 so the markings mirror for traffic in the other direction.
      this.ribbon({ s0, s1, dL: OPP_OUT, dR: OPP_IN, yL: h, yR: h, uL: 1, uR: 0, step: 2 }, road);
    }
    for (const r of singles) this.ribbon({ s0: r.s0, s1: r.s1, dL: -6, dR: 6, yL: h, yR: h, step: 2 }, roadSingle);

    // --- Median and verges ---
    const verge = (s: number) => h(s) - 0.06;
    this.ribbon({ dL: 6, dR: 9.5, yL: verge, yR: verge, vScale: 8, uR: 0.4, step: 4 }, grass);
    for (const [s0, s1] of duals) {
      this.ribbon({ s0, s1, dL: -8.5, dR: -6, yL: verge, yR: verge, vScale: 8, uR: 0.3, step: 4 }, grass);
      this.ribbon({ s0, s1, dL: -24, dR: OPP_OUT, yL: verge, yR: verge, vScale: 8, uR: 0.4, step: 4 }, grass);
    }
    for (const r of singles) this.ribbon({ s0: r.s0, s1: r.s1, dL: -9.5, dR: -6, yL: verge, yR: verge, vScale: 8, uR: 0.4, step: 4 }, grass);

    // --- Embankments down to the fields (with a gap for the canal) ---
    const segmentsOutsideBridge: [number, number][] = [];
    let from = 0;
    for (const sp of [...spans].sort((a, b) => a.c - b.c)) {
      segmentsOutsideBridge.push([from, sp.c - sp.half]);
      from = sp.c + sp.half;
    }
    segmentsOutsideBridge.push([from, t.length]);
    const clip = (a: number, b: number, runs: [number, number][]) =>
      runs.map(([c, d]) => [Math.max(a, c), Math.min(b, d)] as [number, number]).filter(([c, d]) => d - c > 2);
    const singleRuns = singles.map((r) => [r.s0, r.s1] as [number, number]);
    for (const [s0, s1] of segmentsOutsideBridge) {
      this.ribbon({ s0, s1, dL: 9.5, dR: (s) => 12 + h(s) * 1.8, yL: verge, yR: () => 0, vScale: 8, uR: 1, step: 4 }, grass);
      for (const [a, b] of clip(s0, s1, duals)) {
        this.ribbon({ s0: a, s1: b, dL: (s) => -26.5 - h(s) * 1.8, dR: -24, yL: () => 0, yR: verge, vScale: 8, uR: 1, step: 4 }, grass);
      }
      for (const [a, b] of clip(s0, s1, singleRuns)) {
        this.ribbon({ s0: a, s1: b, dL: (s) => -12 - h(s) * 1.8, dR: -9.5, yL: () => 0, yR: verge, vScale: 8, uR: 1, step: 4 }, grass);
      }
    }

    // --- Guard rails (vangrail) ---
    const railY0 = (s: number) => h(s) + 0.42;
    const railY1 = (s: number) => h(s) + 0.78;
    for (const d of [5.6, -5.6]) {
      this.ribbon({ dL: d, dR: d, yL: railY0, yR: railY1, step: 2 }, metal).castShadow = true;
    }
    for (const [s0, s1] of duals) {
      for (const d of [-9.0, -20.0]) this.ribbon({ s0, s1, dL: d, dR: d, yL: railY0, yR: railY1, step: 2 }, metal).castShadow = true;
    }
    const postGeo = new THREE.BoxGeometry(0.12, 0.8, 0.12);
    this.posts([5.6, -5.6], 4, postGeo, metal, 0.4);
    this.posts([-9.0, -20.0], 4, postGeo, metal, 0.4, (s) => !t.isSingle(s));

    for (const sp of spans) this.bridge(sp.c, sp.half, concrete);
    for (const s of f.viaducts) this.overpass(s, concrete, grass, metal);
    for (const g of f.gantries) this.gantry(g.s, g.text, g.route, metal);
    this.lamps(metal);
    this.hectometerPosts();
    // Noise barriers where the road passes the towns.
    for (const st of f.stages) {
      this.noiseBarrier(st.startS + 200, st.startS + 800, 11);
      this.noiseBarrier(st.finishS - 800, st.finishS - 150, 11);
      const left = (s: number) => (t.isSingle(s) ? -12 : -27);
      this.noiseBarrier(st.startS + 300, st.startS + 700, left(st.startS + 500));
      this.noiseBarrier(st.finishS - 650, st.finishS - 150, left(st.finishS - 400));
    }
    for (const tu of f.tunnels) this.tunnel(tu.s0, tu.s1, concrete, grass);
    for (const lm of f.landmarks) if (lm.id === 'heuvelrug') this.hills(lm.s, lm.d);
    this.startFinish();
    this.ground();
    for (const sp of spans) this.underpass(sp.c, sp.half, sp.canal);
    this.trees();
    this.farms();
    this.cityBlocks();
    chunkInstances(this.group);
    mergeStaticByCell(this.group);
    freezeStatic(this.group);
    return this.group;
  }

  private placeOnTrack(obj: THREE.Object3D, s: number, d: number, up = 0, yaw = 0): void {
    const fr = this.track.frame(s);
    obj.position.set(fr.x + fr.rx * d, fr.y + up, fr.z + fr.rz * d);
    obj.rotation.y = fr.heading + yaw;
  }

  private posts(ds: number[], spacing: number, geo: THREE.BufferGeometry, mat: THREE.Material, up: number,
    keep: (s: number) => boolean = () => true): void {
    const t = this.track;
    const n = Math.floor(t.length / spacing) * ds.length;
    const inst = new THREE.InstancedMesh(geo, mat, n);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const one = new THREE.Vector3(1, 1, 1);
    let i = 0;
    for (let s = 0; s < t.length && i < n; s += spacing) {
      if (!keep(s)) continue;
      const fr = t.frame(s);
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), fr.heading);
      for (const d of ds) {
        m.compose(new THREE.Vector3(fr.x + fr.rx * d, fr.y + up, fr.z + fr.rz * d), q, one);
        inst.setMatrixAt(i++, m);
      }
    }
    inst.count = i;
    inst.castShadow = true;
    this.group.add(inst);
  }

  /** Is s in an open span, or near a viaduct or a landmark on that side? (keeps trees/farms clear) */
  private blocked(s: number, d: number, margin = 45): boolean {
    const f = this.track.features;
    if (this.spans.some((sp) => Math.abs(s - sp.c) < sp.half + margin)) return true;
    if (f.viaducts.some((v) => Math.abs(s - v) < 24)) return true;
    if (this.track.inTunnel(s, 30)) return true;
    return f.landmarks.some((lm) => Math.abs(s - lm.s) < (lm.id === 'heuvelrug' ? 700 : 190) && Math.sign(lm.d) === Math.sign(d));
  }

  private bridge(c: number, half: number, concrete: THREE.Material): void {
    const t = this.track;
    const h = (s: number) => t.heightAt(s);
    const under = (s: number) => h(s) - 1.6;
    const s0 = c - half - 2;
    const s1 = c + half + 2;
    const mat = (concrete as THREE.MeshStandardMaterial).clone();
    mat.side = THREE.DoubleSide;
    this.ribbon({ s0, s1, dL: -24, dR: 9.5, yL: under, yR: under, step: 2 }, mat);
    this.ribbon({ s0, s1, dL: 9.5, dR: 9.5, yL: under, yR: (s) => h(s) - 0.06, step: 2 }, mat);
    this.ribbon({ s0, s1, dL: -24, dR: -24, yL: under, yR: (s) => h(s) - 0.06, step: 2 }, mat);
    // Abutments at both ends.
    for (const s of [c - half, c + half]) {
      const hh = h(s);
      const box = new THREE.Mesh(new THREE.BoxGeometry(38, hh, 3), concrete);
      this.placeOnTrack(box, s, -7.25, -hh / 2);
      box.castShadow = box.receiveShadow = true;
      this.group.add(box);
    }
    // Middle piers
    for (const d of [3, -7.25, -17]) {
      const hh = h(c);
      const pier = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 0.8, hh, 12), concrete);
      this.placeOnTrack(pier, c, d, -hh / 2 - 1);
      pier.castShadow = true;
      this.group.add(pier);
    }
  }

  private overpass(s: number, concrete: THREE.Material, grass: THREE.Material, metal: THREE.Material): void {
    const t = this.track;
    const fr = t.frame(s);
    const base = fr.y;
    const clearance = 6.4;
    const g = new THREE.Group();
    // Deck spans across both carriageways, perpendicular to the road.
    const deckLen = 64;
    const deck = new THREE.Mesh(new THREE.BoxGeometry(deckLen, 1.3, 12), concrete);
    deck.position.set(0, clearance + 0.65, 0);
    deck.castShadow = deck.receiveShadow = true;
    const asphalt = new THREE.Mesh(
      new THREE.BoxGeometry(deckLen, 0.06, 10),
      new THREE.MeshStandardMaterial({ color: 0x333438, roughness: 0.85 }),
    );
    asphalt.position.set(0, clearance + 1.33, 0);
    g.add(deck, asphalt);
    for (const side of [-1, 1]) {
      const rail = new THREE.Mesh(new THREE.BoxGeometry(deckLen, 0.9, 0.15), metal);
      rail.position.set(0, clearance + 1.8, side * 5.6);
      g.add(rail);
    }
    // Piers: right verge, median, left verge (local x = -d because right = -X when yaw = heading).
    for (const d of [10.5, -7.25, -25]) {
      for (const zz of [-3.5, 3.5]) {
        const pier = new THREE.Mesh(new THREE.BoxGeometry(1, clearance, 1), concrete);
        pier.position.set(-(d + 7.25), clearance / 2, zz);
        pier.castShadow = true;
        g.add(pier);
      }
    }
    // Earth ramps at both ends (wedges sloping down to the fields).
    for (const side of [-1, 1]) {
      const rampLen = 70;
      const H = clearance + 1.4 + base;
      const geo = new THREE.BoxGeometry(rampLen, H, 16, 4, 1, 1);
      const p = geo.attributes.position as THREE.BufferAttribute;
      for (let i = 0; i < p.count; i++) {
        const x = p.getX(i);
        if (p.getY(i) > 0) {
          const k = side * x > 0 ? 1 - (side * x) / (rampLen / 2) : 1; // slope away from the deck
          p.setY(i, -H / 2 + H * Math.max(0.02, k));
        }
      }
      geo.computeVertexNormals();
      const ramp = new THREE.Mesh(geo, grass);
      ramp.position.set(side * (deckLen / 2 + rampLen / 2), H / 2 - base, 0);
      ramp.receiveShadow = true;
      g.add(ramp);
    }
    // Position: centre on the median, rotated so local X runs across the road.
    const cx = fr.x + fr.rx * -7.25;
    const cz = fr.z + fr.rz * -7.25;
    g.position.set(cx, base, cz);
    g.rotation.y = fr.heading;
    this.group.add(g);
  }

  private gantry(s: number, text: string[], route: string, metal: THREE.Material): void {
    const g = new THREE.Group();
    const height = 7;
    for (const d of [7.2, -7.0]) {
      const post = new THREE.Mesh(new THREE.BoxGeometry(0.35, height + 1.2, 0.35), metal);
      post.position.set(-d, (height + 1.2) / 2, 0);
      post.castShadow = true;
      g.add(post);
    }
    const beam = new THREE.Mesh(new THREE.BoxGeometry(15, 0.9, 0.6), metal);
    beam.position.set(-0.1, height + 0.6, 0);
    g.add(beam);
    // Two signs: through-route on the left lane, exit on the right.
    const signs: [string[], string, number][] = [
      [[text[0]], route, -2.75],
      [[text[1]], route, 2.0],
    ];
    for (const [lines, r, d] of signs) {
      const sign = new THREE.Mesh(
        new THREE.PlaneGeometry(5.2, 2.6),
        new THREE.MeshStandardMaterial({ map: signTexture(lines, r), roughness: 0.4, emissive: 0x0a1a3a, emissiveIntensity: 0.4 }),
      );
      sign.position.set(-d, height + 0.6, -0.35);
      sign.rotation.y = Math.PI; // face oncoming traffic
      sign.castShadow = true;
      g.add(sign);
    }
    this.placeOnTrack(g, s, 0);
    this.group.add(g);
  }

  private lamps(metal: THREE.Material): void {
    const t = this.track;
    const spacing = 55;
    const n = Math.floor(t.length / spacing);
    const pole = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.1, 0.14, 11, 6), metal, n);
    const arm = new THREE.InstancedMesh(new THREE.BoxGeometry(5.5, 0.12, 0.12), metal, n);
    const head = new THREE.InstancedMesh(
      new THREE.BoxGeometry(0.9, 0.18, 0.4),
      new THREE.MeshStandardMaterial({ color: 0xffe2a8, emissive: 0xffb84d, emissiveIntensity: 3 }),
      n * 2,
    );
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const one = new THREE.Vector3(1, 1, 1);
    const up = new THREE.Vector3(0, 1, 0);
    let i = 0;
    for (let k = 0; k < n; k++) {
      const s = k * spacing + 20;
      // Median lamps only where there is a median (and not inside the tunnel).
      if (t.isSingle(s) || t.inTunnel(s, 15)) continue;
      const fr = t.frame(s);
      q.setFromAxisAngle(up, fr.heading);
      const p = t.pointAt(s, -7.25, 5.5);
      m.compose(p, q, one);
      pole.setMatrixAt(i, m);
      m.compose(t.pointAt(s, -7.25, 10.9), q, one);
      arm.setMatrixAt(i, m);
      m.compose(t.pointAt(s, -5.0, 10.8), q, one);
      head.setMatrixAt(i * 2, m);
      m.compose(t.pointAt(s, -9.5, 10.8), q, one);
      head.setMatrixAt(i * 2 + 1, m);
      i++;
    }
    pole.count = arm.count = i;
    head.count = i * 2;
    this.group.add(pole, arm, head);
  }

  private hectometerPosts(): void {
    const t = this.track;
    const n = Math.floor(t.length / 100);
    const inst = new THREE.InstancedMesh(
      new THREE.BoxGeometry(0.14, 0.9, 0.14),
      new THREE.MeshStandardMaterial({ color: 0x1f7a3a, roughness: 0.6 }),
      n,
    );
    const m = new THREE.Matrix4();
    for (let i = 0; i < n; i++) {
      const fr = t.frame(i * 100);
      m.compose(t.pointAt(i * 100, 6.6, 0.45), new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), fr.heading), new THREE.Vector3(1, 1, 1));
      inst.setMatrixAt(i, m);
    }
    this.group.add(inst);
  }

  private noiseBarrier(s0: number, s1: number, d: number): void {
    const t = this.track;
    // Leave a gap in front of landmarks on this side: they should be seen from the road.
    for (const lm of t.features.landmarks) {
      if (lm.id === 'heuvelrug' || Math.sign(lm.d) !== Math.sign(d)) continue;
      const a = lm.s - 170;
      const b = lm.s + 170;
      if (b <= s0 || a >= s1) continue;
      if (a - s0 > 40) this.noiseBarrier(s0, a, d);
      if (s1 - b > 40) this.noiseBarrier(b, s1, d);
      return;
    }
    const mat = new THREE.MeshStandardMaterial({ color: 0x6b5a45, roughness: 0.9, side: THREE.DoubleSide });
    const glass = new THREE.MeshStandardMaterial({
      color: 0x9fc4d0, roughness: 0.1, metalness: 0.2, transparent: true, opacity: 0.35, side: THREE.DoubleSide,
    });
    this.ribbon({ s0, s1, dL: d, dR: d, yL: (s) => t.heightAt(s) - 0.1, yR: (s) => t.heightAt(s) + 2.6, step: 4 }, mat).castShadow = true;
    this.ribbon({ s0, s1, dL: d, dR: d, yL: (s) => t.heightAt(s) + 2.6, yR: (s) => t.heightAt(s) + 4.2, step: 4 }, glass);
  }

  private startFinish(): void {
    const t = this.track;
    const f = t.features;
    const checker = new THREE.MeshStandardMaterial({ map: checkerTexture(), roughness: 0.7 });
    const postMat = new THREE.MeshStandardMaterial({ color: 0x222222, metalness: 0.6, roughness: 0.4 });
    const gate = (s: number, text: string) => {
      const g = new THREE.Group();
      for (const d of [6.6, -6.4]) {
        const post = new THREE.Mesh(new THREE.BoxGeometry(0.5, 7.5, 0.5), postMat);
        post.position.set(-d, 3.75, 0);
        g.add(post);
      }
      const cloth = new THREE.Mesh(
        new THREE.PlaneGeometry(13.5, 2.1),
        new THREE.MeshStandardMaterial({ map: bannerTexture(text), emissive: 0xffffff, emissiveIntensity: 0.25, side: THREE.DoubleSide }),
      );
      cloth.position.set(0, 6.6, 0);
      cloth.rotation.y = Math.PI;
      g.add(cloth);
      this.placeOnTrack(g, s, 0);
      this.group.add(g);
    };
    const line = (s: number) => {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(11, 1.4), checker);
      m.rotation.x = -Math.PI / 2;
      m.receiveShadow = true;
      const holder = new THREE.Group();
      holder.add(m);
      this.placeOnTrack(holder, s, 0, 0.02);
      this.group.add(holder);
    };
    // Place-name signs: leaving a town at the start, entering the next before the finish.
    const sign = (s: number, name: string, sub: string, ended: boolean) => {
      const g = new THREE.Group();
      const tex = placeSignTexture(name, sub);
      const board = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 1.15), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.4 }));
      board.position.set(0, 2.6, 0);
      board.rotation.y = Math.PI;
      g.add(board);
      if (ended) {
        const stripe = new THREE.Mesh(new THREE.PlaneGeometry(2.9, 0.14), new THREE.MeshStandardMaterial({ color: 0xc4161c }));
        stripe.position.set(0, 2.6, -0.01);
        stripe.rotation.set(0, Math.PI, 0.38);
        g.add(stripe);
      }
      for (const x of [-0.9, 0.9]) {
        const p = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 2.2), new THREE.MeshStandardMaterial({ color: 0x888888 }));
        p.position.set(x, 1.1, 0.02);
        g.add(p);
      }
      this.placeOnTrack(g, s, 7.6);
      this.group.add(g);
    };
    for (const st of f.stages) {
      line(st.startS);
      line(st.finishS);
      gate(st.finishS, `FINISH  •  ${st.to.toUpperCase()}`);
      for (const k of [0.27, 0.52, 0.77]) gate(Math.round(st.startS + (st.finishS - st.startS) * k), 'CHECKPOINT');
      sign(st.startS + 30, st.from, `Etappe ${st.id}`, true);
      sign(st.finishS - 160, st.to, '', false);
    }
  }

  /** Cut-and-cover tunnel (Nijverdal): walls, roof with grass on top, ceiling lights, portals. */
  private tunnel(s0: number, s1: number, concrete: THREE.Material, grass: THREE.Material): void {
    const t = this.track;
    const h = (s: number) => t.heightAt(s);
    const roofY = (s: number) => h(s) + 6.4;
    const wall = (concrete as THREE.MeshStandardMaterial).clone();
    wall.side = THREE.DoubleSide;
    wall.color.setHex(0xb8b4ac);
    const dual = !t.isSingle((s0 + s1) / 2);
    const outer = dual ? [-22, 7] : [-7, 7];
    for (const d of dual ? [...outer, -7.3] : outer) {
      this.ribbon({ s0, s1, dL: d, dR: d, yL: (s) => h(s) - 0.2, yR: roofY, step: 4 }, wall);
    }
    // Concrete kerbs over the grass verges inside the tube.
    const kerb = (concrete as THREE.MeshStandardMaterial).clone();
    kerb.color.setHex(0x8f8b84);
    const kerbY = (s: number) => h(s) - 0.03;
    this.ribbon({ s0, s1, dL: 6, dR: outer[1], yL: kerbY, yR: kerbY, vScale: 8, step: 4 }, kerb);
    this.ribbon({ s0, s1, dL: dual ? -7.3 : outer[0], dR: -6, yL: kerbY, yR: kerbY, vScale: 8, step: 4 }, kerb);
    const roof = this.ribbon({ s0, s1, dL: outer[0], dR: outer[1], yL: roofY, yR: roofY, step: 4 }, wall);
    roof.castShadow = true;
    const cover = this.ribbon({ s0: s0 - 4, s1: s1 + 4, dL: outer[0] - 6, dR: outer[1] + 6, yL: (s) => roofY(s) + 0.7, yR: (s) => roofY(s) + 0.7, vScale: 8, step: 4 }, grass);
    cover.castShadow = true;
    // Earth slopes over the portal walls, so the tunnel reads as a park on top.
    for (const side of [outer[0] - 6, outer[1] + 6]) {
      const out = side < 0 ? side - 10 : side + 10;
      this.ribbon({ s0: s0 - 4, s1: s1 + 4, dL: side < 0 ? out : side, dR: side < 0 ? side : out, yL: side < 0 ? () => 0 : (s) => roofY(s) + 0.7, yR: side < 0 ? (s) => roofY(s) + 0.7 : () => 0, vScale: 8, step: 4 }, grass);
    }
    // Ceiling light strips
    const n = Math.floor((s1 - s0) / 8);
    const lights = new THREE.InstancedMesh(
      new THREE.BoxGeometry(0.5, 0.08, 4),
      new THREE.MeshStandardMaterial({ color: 0xfff1d0, emissive: 0xffe2a8, emissiveIntensity: 3.5 }),
      n * 2,
    );
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    for (let i = 0; i < n; i++) {
      const s = s0 + 4 + i * 8;
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), t.frame(s).heading);
      for (const [k, d] of [[0, -2.5], [1, 2.5]] as const) {
        m.compose(t.pointAt(s, d, 6.3), q, new THREE.Vector3(1, 1, 1));
        lights.setMatrixAt(i * 2 + k, m);
      }
    }
    this.group.add(lights);
    // Portal headers with the road number.
    for (const [s, yaw] of [[s0, 0], [s1, Math.PI]] as const) {
      const header = new THREE.Mesh(new THREE.BoxGeometry(outer[1] - outer[0] + 1, 1.6, 0.8), wall);
      this.placeOnTrack(header, s, (outer[0] + outer[1]) / 2, 7.0, yaw);
      header.castShadow = true;
      this.group.add(header);
    }
  }

  /** Sallandse Heuvelrug: soft heather-and-pine hills beside the road. */
  private hills(sCentre: number, dCentre: number): void {
    const t = this.track;
    const lenAlong = 1600;
    const width = 520;
    const segA = 64;
    const segW = 26;
    const geo = new THREE.PlaneGeometry(lenAlong, width, segA, segW);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position as THREE.BufferAttribute;
    const colors = new Float32Array(pos.count * 3);
    const heather = new THREE.Color(0x6b4a6e);
    const green = new THREE.Color(0x3f5f2a);
    const sand = new THREE.Color(0x9c8a5c);
    const c = new THREE.Color();
    const bumps = [
      { x: -380, z: 40, r: 260, h: 48 }, { x: 120, z: 90, r: 300, h: 62 }, { x: 520, z: 10, r: 220, h: 38 },
      { x: -40, z: -60, r: 180, h: 22 },
    ];
    const side = Math.sign(dCentre) || 1;
    for (let i = 0; i < pos.count; i++) {
      const lx = pos.getX(i); // along the road
      const lz = pos.getZ(i); // away from the road (+ = further)
      let y = 0;
      for (const b of bumps) y += b.h * Math.exp(-((lx - b.x) ** 2 + (lz - b.z) ** 2) / (b.r * b.r));
      // Fade to flat at the edges so it meets the fields.
      const edge = Math.min(1, (lenAlong / 2 - Math.abs(lx)) / 220) * Math.min(1, (width / 2 - Math.abs(lz)) / 120);
      y *= Math.max(0, edge);
      // Place: centre at (s, d), along-road axis follows the heading at the centre.
      const s = sCentre + lx;
      const d = dCentre + side * lz;
      const fr = t.frame(Math.max(0, Math.min(t.length, s)));
      const wx = fr.x + fr.rx * d;
      const wz = fr.z + fr.rz * d;
      pos.setXYZ(i, wx, y, wz);
      const k = y / 60;
      c.copy(green).lerp(heather, Math.min(1, Math.max(0, (Math.sin(lx / 90) + Math.cos(lz / 70)) * 0.35 + k)));
      if (y < 3) c.lerp(sand, 0.15);
      colors.set([c.r, c.g, c.b], i * 3);
    }
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geo.computeVertexNormals();
    const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, flatShading: true }));
    mesh.receiveShadow = true;
    mesh.castShadow = true;
    mesh.userData.hills = true;
    this.group.add(mesh);
    // Pines on the slopes.
    const n = 260;
    const pine = new THREE.InstancedMesh(new THREE.ConeGeometry(2.2, 9, 6), new THREE.MeshStandardMaterial({ color: 0x24401f, roughness: 1, flatShading: true }), n);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    let placed = 0;
    const tmp = new THREE.Vector3();
    for (let i = 0; i < n * 3 && placed < n; i++) {
      const vi = Math.floor(Math.random() * pos.count);
      tmp.set(pos.getX(vi), pos.getY(vi), pos.getZ(vi));
      if (tmp.y < 6 || Math.random() < 0.3) continue;
      m.compose(tmp.clone().setY(tmp.y + 4), q, new THREE.Vector3(1, 0.8 + Math.random() * 0.6, 1));
      pine.setMatrixAt(placed++, m);
    }
    pine.count = placed;
    pine.castShadow = true;
    this.group.add(pine);
  }

  private ground(): void {
    const t = this.track;
    const box = new THREE.Box3();
    for (let s = 0; s <= t.length; s += 50) box.expandByPoint(t.pointAt(s, 0));
    const size = new THREE.Vector3();
    const center = new THREE.Vector3();
    box.getSize(size);
    box.getCenter(center);
    const extent = Math.max(size.x, size.z) + 6000;
    const tex = fieldTexture();
    tex.repeat.set(extent / 900, extent / 900);
    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(extent, extent),
      new THREE.MeshStandardMaterial({ map: tex, roughness: 1 }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(center.x, 0, center.z);
    ground.receiveShadow = true;
    this.group.add(ground);
  }

  /** What passes under a bridge: the Twentekanaal, or a local road. */
  private underpass(c: number, half: number, canal: boolean): void {
    const t = this.track;
    const fr = t.frame(c);
    const holder = new THREE.Group();
    holder.position.set(fr.x, 0, fr.z);
    // Long axis is local X; laid across the motorway with a slight skew.
    holder.rotation.y = fr.heading + 0.25;
    if (canal) {
      const width = Math.min(34, half * 2 - 10);
      const water = new THREE.Mesh(
        new THREE.PlaneGeometry(3000, width),
        new THREE.MeshStandardMaterial({ color: 0x1d3f55, roughness: 0.08, metalness: 0.6 }),
      );
      water.rotation.x = -Math.PI / 2;
      water.position.y = 0.08;
      holder.add(water);
      for (const side of [-1, 1]) {
        const bank = new THREE.Mesh(new THREE.BoxGeometry(3000, 0.5, 1.2), new THREE.MeshStandardMaterial({ color: 0x7a776f }));
        bank.position.set(0, 0.1, side * (width / 2 + 0.5));
        holder.add(bank);
      }
      holder.userData.dynamic = true; // the barge sails here
      this.canals.push({ s: c, holder, width });
    } else {
      const road = new THREE.Mesh(
        new THREE.PlaneGeometry(1600, 7.5),
        new THREE.MeshStandardMaterial({ color: 0x38393c, roughness: 0.85 }),
      );
      road.rotation.x = -Math.PI / 2;
      road.position.y = 0.06;
      const line = new THREE.Mesh(new THREE.PlaneGeometry(1600, 0.15), new THREE.MeshStandardMaterial({ color: 0xdddddd }));
      line.rotation.x = -Math.PI / 2;
      line.position.y = 0.07;
      holder.add(road, line);
    }
    this.group.add(holder);
  }

  private trees(): void {
    const t = this.track;
    const spots: { x: number; z: number; y: number; scale: number }[] = [];
    const tmp = new THREE.Vector3();
    // Clumps of trees ("houtwallen") with gaps for fields.
    for (let s = 0; s < t.length; s += 4) {
      for (const side of [1, -1]) {
        if (this.blocked(s, side)) continue;
        const density = 0.5 + 0.5 * Math.sin(s / 70 + side * 2.1) * Math.sin(s / 23 + side);
        if (Math.random() > density * 0.55) continue;
        const leftNear = t.isSingle(s) ? -16 : -30;
        const near = side > 0 ? 16 + t.heightAt(s) * 1.8 : leftNear - t.heightAt(s) * 1.8;
        const d = near + side * Math.random() ** 1.6 * 70;
        t.pointAt(s + Math.random() * 4, d, 0, tmp);
        spots.push({ x: tmp.x, z: tmp.z, y: 0, scale: 0.8 + Math.random() * 0.9 });
      }
    }
    const n = spots.length;
    const trunk = new THREE.InstancedMesh(
      new THREE.CylinderGeometry(0.18, 0.28, 3, 5),
      new THREE.MeshStandardMaterial({ color: 0x4a3626, roughness: 1 }),
      n,
    );
    const crownGeo = new THREE.IcosahedronGeometry(2.4, 1);
    crownGeo.scale(1, 1.25, 1);
    const crown = new THREE.InstancedMesh(
      crownGeo,
      new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.95, flatShading: true }),
      n,
    );
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const col = new THREE.Color();
    spots.forEach((sp, i) => {
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), Math.random() * Math.PI);
      const sc = new THREE.Vector3(sp.scale, sp.scale, sp.scale);
      m.compose(new THREE.Vector3(sp.x, 1.5 * sp.scale, sp.z), q, sc);
      trunk.setMatrixAt(i, m);
      m.compose(new THREE.Vector3(sp.x, 4.6 * sp.scale, sp.z), q, sc);
      crown.setMatrixAt(i, m);
      col.setHSL(0.22 + Math.random() * 0.08, 0.45 + Math.random() * 0.2, 0.2 + Math.random() * 0.12);
      crown.setColorAt(i, col);
    });
    crown.castShadow = true;
    trunk.castShadow = true;
    this.group.add(trunk, crown);
  }

  /** Apartment and office blocks where the motorway passes Hengelo and enters Enschede. */
  private cityBlocks(): void {
    const t = this.track;
    const f = t.features;
    const zones: [number, number][] = [];
    for (const st of f.stages) {
      zones.push([Math.max(0, st.startS - 300), st.startS + 900], [st.finishS - 1300, st.finishS + 250]);
    }
    const kinds = [
      { wall: '#8c7c6c', n: 110 },
      { wall: '#b9b2a6', n: 110 },
      { wall: '#5e4a40', n: 110 },
    ];
    const box = new THREE.BoxGeometry(1, 1, 1);
    box.translate(0, 0.5, 0);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const p = new THREE.Vector3();
    const up = new THREE.Vector3(0, 1, 0);
    kinds.forEach((k, ki) => {
      const tex = facadeTextures(ki + 1, k.wall);
      const mat = new THREE.MeshStandardMaterial({
        map: tex.map, emissiveMap: tex.glow, emissive: 0xffffff, emissiveIntensity: 1.4, roughness: 0.85,
      });
      const inst = new THREE.InstancedMesh(box, mat, k.n);
      let placed = 0;
      for (let tries = 0; tries < k.n * 8 && placed < k.n; tries++) {
        const [a, b] = zones[Math.floor(Math.random() * zones.length)];
        const s = a + Math.random() * (b - a);
        const side = Math.random() < 0.5 ? 1 : -1;
        if (this.blocked(s, side, 60)) continue;
        const d = side > 0 ? 75 + Math.random() * 260 : -85 - Math.random() * 260;
        t.pointAt(s, d, 0, p);
        p.y = 0;
        const fr = t.frame(s);
        q.setFromAxisAngle(up, fr.heading + (Math.random() < 0.5 ? 0 : Math.PI / 2));
        const h = 9 + Math.random() ** 2 * 38;
        m.compose(p, q, new THREE.Vector3(14 + Math.random() * 22, h, 12 + Math.random() * 14));
        inst.setMatrixAt(placed++, m);
      }
      inst.count = placed;
      inst.castShadow = inst.receiveShadow = true;
      this.group.add(inst);
    });
  }

  private farms(): void {
    const t = this.track;
    const n = 60;
    const walls = new THREE.InstancedMesh(
      new THREE.BoxGeometry(10, 4, 18),
      new THREE.MeshStandardMaterial({ color: 0x8e4a32, roughness: 0.9 }),
      n,
    );
    const roofGeo = new THREE.CylinderGeometry(6.2, 6.2, 18.6, 3, 1);
    roofGeo.rotateX(Math.PI / 2);
    roofGeo.rotateZ(Math.PI / 2);
    roofGeo.scale(1, 0.7, 1);
    const roof = new THREE.InstancedMesh(
      roofGeo,
      new THREE.MeshStandardMaterial({ color: 0x2f2a28, roughness: 0.8 }),
      n,
    );
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const one = new THREE.Vector3(1, 1, 1);
    const p = new THREE.Vector3();
    let placed = 0;
    for (let tries = 0; tries < n * 4 && placed < n; tries++) {
      const s = 100 + Math.random() * (t.length - 200);
      const side = Math.random() < 0.5 ? 1 : -1;
      if (this.blocked(s, side, 80)) continue;
      const i = placed++;
      const d = side > 0 ? 90 + Math.random() * 180 : -110 - Math.random() * 180;
      t.pointAt(s, d, 0, p);
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), Math.random() * Math.PI);
      m.compose(p.clone().setY(2), q, one);
      walls.setMatrixAt(i, m);
      m.compose(p.clone().setY(4 + 2.1), q, one);
      roof.setMatrixAt(i, m);
    }
    walls.count = roof.count = placed;
    walls.castShadow = roof.castShadow = true;
    this.group.add(walls, roof);
  }
}
