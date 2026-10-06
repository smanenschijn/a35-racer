import * as THREE from 'three';
import type { Track } from './Track';
import {
  facadeTextures,
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

    // --- Road surfaces ---
    this.ribbon({ dL: -6, dR: 6, yL: h, yR: h, step: 2 }, road);
    // Left edge must have the smaller d, otherwise the surface faces down and gets culled.
    // u runs 1→0 so the markings mirror for traffic in the other direction.
    this.ribbon({ dL: OPP_OUT, dR: OPP_IN, yL: h, yR: h, uL: 1, uR: 0, step: 2 }, road);

    // --- Median and verges ---
    const verge = (s: number) => h(s) - 0.06;
    this.ribbon({ dL: -8.5, dR: -6, yL: verge, yR: verge, vScale: 8, uR: 0.3, step: 4 }, grass);
    this.ribbon({ dL: 6, dR: 9.5, yL: verge, yR: verge, vScale: 8, uR: 0.4, step: 4 }, grass);
    this.ribbon({ dL: -24, dR: OPP_OUT, yL: verge, yR: verge, vScale: 8, uR: 0.4, step: 4 }, grass);

    // --- Embankments down to the fields (with a gap for the canal) ---
    const segmentsOutsideBridge: [number, number][] = [];
    let from = 0;
    for (const sp of [...spans].sort((a, b) => a.c - b.c)) {
      segmentsOutsideBridge.push([from, sp.c - sp.half]);
      from = sp.c + sp.half;
    }
    segmentsOutsideBridge.push([from, t.length]);
    for (const [s0, s1] of segmentsOutsideBridge) {
      this.ribbon({ s0, s1, dL: 9.5, dR: (s) => 12 + h(s) * 1.8, yL: verge, yR: () => 0, vScale: 8, uR: 1, step: 4 }, grass);
      this.ribbon({ s0, s1, dL: (s) => -26.5 - h(s) * 1.8, dR: -24, yL: () => 0, yR: verge, vScale: 8, uR: 1, step: 4 }, grass);
    }

    // --- Guard rails (vangrail) ---
    const railY0 = (s: number) => h(s) + 0.42;
    const railY1 = (s: number) => h(s) + 0.78;
    for (const d of [5.6, -5.6, -9.0, -20.0]) {
      this.ribbon({ dL: d, dR: d, yL: railY0, yR: railY1, step: 2 }, metal).castShadow = true;
    }
    this.posts([5.6, -5.6, -9.0, -20.0], 4, new THREE.BoxGeometry(0.12, 0.8, 0.12), metal, 0.4);

    for (const sp of spans) this.bridge(sp.c, sp.half, concrete);
    for (const s of f.viaducts) this.overpass(s, concrete, grass, metal);
    for (const g of f.gantries) this.gantry(g.s, g.text, g.route, metal);
    this.lamps(metal);
    this.hectometerPosts();
    // Noise barriers where the motorway passes Hengelo and enters Enschede.
    this.noiseBarrier(f.startS + 200, f.startS + 900, 11);
    this.noiseBarrier(f.startS + 300, f.startS + 800, -27);
    this.noiseBarrier(f.finishS - 900, f.finishS - 150, 11);
    this.noiseBarrier(f.finishS - 700, f.finishS - 100, -27);
    this.startFinish();
    this.ground();
    for (const sp of spans) this.underpass(sp.c, sp.half, sp.canal);
    this.trees();
    this.farms();
    this.cityBlocks();
    return this.group;
  }

  private placeOnTrack(obj: THREE.Object3D, s: number, d: number, up = 0, yaw = 0): void {
    const fr = this.track.frame(s);
    obj.position.set(fr.x + fr.rx * d, fr.y + up, fr.z + fr.rz * d);
    obj.rotation.y = fr.heading + yaw;
  }

  private posts(ds: number[], spacing: number, geo: THREE.BufferGeometry, mat: THREE.Material, up: number): void {
    const t = this.track;
    const n = Math.floor(t.length / spacing) * ds.length;
    const inst = new THREE.InstancedMesh(geo, mat, n);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const one = new THREE.Vector3(1, 1, 1);
    let i = 0;
    for (let s = 0; s < t.length && i < n; s += spacing) {
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
    return f.landmarks.some((lm) => Math.abs(s - lm.s) < 190 && Math.sign(lm.d) === Math.sign(d));
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
    for (let i = 0; i < n; i++) {
      const s = i * spacing + 20;
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
    }
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
    for (const s of [f.startS, f.finishS]) {
      const line = new THREE.Mesh(new THREE.PlaneGeometry(11, 1.4), checker);
      line.rotation.x = -Math.PI / 2;
      const holder = new THREE.Group();
      holder.add(line);
      this.placeOnTrack(holder, s, 0, 0.02);
      line.receiveShadow = true;
      this.group.add(holder);
    }
    // Finish banner gantry
    const banner = new THREE.Group();
    const metal = new THREE.MeshStandardMaterial({ color: 0x222222, metalness: 0.6, roughness: 0.4 });
    for (const d of [6.6, -6.4]) {
      const post = new THREE.Mesh(new THREE.BoxGeometry(0.5, 7.5, 0.5), metal);
      post.position.set(-d, 3.75, 0);
      banner.add(post);
    }
    const cloth = new THREE.Mesh(
      new THREE.PlaneGeometry(13.5, 2.1),
      new THREE.MeshStandardMaterial({ map: bannerTexture('FINISH  •  ENSCHEDE'), emissive: 0xffffff, emissiveIntensity: 0.25, emissiveMap: null, side: THREE.DoubleSide }),
    );
    cloth.position.set(0, 6.6, 0);
    cloth.rotation.y = Math.PI;
    banner.add(cloth);
    this.placeOnTrack(banner, f.finishS, 0);
    this.group.add(banner);

    // Place-name signs: leaving Hengelo at the start, entering Enschede before the finish.
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
    sign(f.startS + 30, 'Hengelo', 'Etappe 5', true);
    sign(f.finishS - 160, 'Enschede', '', false);
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
        const near = side > 0 ? 16 + t.heightAt(s) * 1.8 : -30 - t.heightAt(s) * 1.8;
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
    const zones: [number, number][] = [
      [Math.max(0, f.startS - 300), f.startS + 1100],
      [f.finishS - 1700, t.length],
    ];
    const kinds = [
      { wall: '#8c7c6c', n: 40 },
      { wall: '#b9b2a6', n: 40 },
      { wall: '#5e4a40', n: 40 },
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
