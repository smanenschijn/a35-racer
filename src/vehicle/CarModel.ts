import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { totalLength, type CarSpec } from '../config';
import { getModel } from './models';
import type { Vehicle, Zone } from './Vehicle';

// Procedural low-poly 90s car. Body panels are subdivided boxes whose vertices get pushed
// in on impact, so damage shows up as real dents.

const plateCache = new Map<string, THREE.Texture>();
/** flipY = false for glTF meshes (their UVs use the glTF convention). */
function plateTexture(text: string, flipY = true): THREE.Texture {
  const key = `${text}|${flipY}`;
  let tex = plateCache.get(key);
  if (tex) return tex;
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 56;
  const g = c.getContext('2d')!;
  g.fillStyle = '#f4c400';
  g.fillRect(0, 0, 256, 56);
  g.fillStyle = '#1b3fa0';
  g.fillRect(0, 0, 30, 56);
  g.fillStyle = '#f4c400';
  g.font = 'bold 14px sans-serif';
  g.fillText('NL', 6, 48);
  g.fillStyle = '#111';
  g.font = 'bold 38px "Arial Narrow", Arial, sans-serif';
  g.textAlign = 'center';
  g.fillText(text, 143, 42);
  g.strokeStyle = '#111';
  g.lineWidth = 3;
  g.strokeRect(1.5, 1.5, 253, 53);
  tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  tex.flipY = flipY;
  plateCache.set(key, tex);
  return tex;
}

interface Deformable {
  mesh: THREE.Mesh;
  original: Float32Array;
  /** 1 for vertices that dent (body panels), 0 for the rest of a merged mesh. */
  mask?: Uint8Array;
}

/** A part that can break off, living as a vertex range inside the merged meshes. */
interface Loose {
  zone: string | undefined;
  centre: THREE.Vector3;
  ranges: { mesh: THREE.Mesh; start: number; count: number }[];
  gone: boolean;
}

/**
 * One material for (almost) a whole car: base colour, metalness, roughness, clearcoat and emission
 * come from vertex attributes, so a car with twenty materials draws in a handful of calls and looks
 * the same. Paint takes the per-car paint colour; head/brake lights and beacons take per-car levels.
 */
function uberMaterial(paint: THREE.Color, lights: THREE.Vector4, side: THREE.Side): THREE.MeshPhysicalMaterial {
  const m = new THREE.MeshPhysicalMaterial({
    color: 0xffffff, vertexColors: true, metalness: 1, roughness: 1, clearcoat: 1, clearcoatRoughness: 0.12, side,
  });
  m.onBeforeCompile = (sh) => {
    sh.uniforms.paintColor = { value: paint };
    sh.uniforms.lightLevels = { value: lights };
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec4 pbr;\nattribute vec4 emi;\nvarying vec4 vPbr;\nvarying vec4 vEmi;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvPbr = pbr;\nvEmi = emi;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform vec3 paintColor;\nuniform vec4 lightLevels;\nvarying vec4 vPbr;\nvarying vec4 vEmi;')
      .replace('#include <color_fragment>', '#include <color_fragment>\ndiffuseColor.rgb = mix(diffuseColor.rgb, paintColor, vPbr.w);')
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\nroughnessFactor = vPbr.y;')
      .replace('#include <metalnessmap_fragment>', '#include <metalnessmap_fragment>\nmetalnessFactor = vPbr.x;')
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
float level = vEmi.w < 0.5 ? 1.0 : vEmi.w < 1.5 ? lightLevels.x : vEmi.w < 2.5 ? lightLevels.y : vEmi.w < 3.5 ? lightLevels.z : lightLevels.w;
totalEmissiveRadiance = vEmi.rgb * level;`)
      .replace('#include <lights_physical_fragment>', '#include <lights_physical_fragment>\nmaterial.clearcoat = clearcoat * vPbr.z;');
  };
  m.customProgramCacheKey = () => 'car-uber-1';
  return m;
}

const textCache = new Map<string, THREE.Texture>();
/** Lettering for liveries and trailers. */
function textTexture(text: string, bg: string, fg: string, w = 512, h = 128, font = 'bold 72px Arial, sans-serif'): THREE.Texture {
  const key = [text, bg, fg, w, h, font].join('|');
  let tex = textCache.get(key);
  if (tex) return tex;
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const g = c.getContext('2d')!;
  g.fillStyle = bg;
  g.fillRect(0, 0, w, h);
  g.fillStyle = fg;
  g.font = font;
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText(text, w / 2, h / 2 + 4);
  tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  textCache.set(key, tex);
  return tex;
}

// Shared materials / geometry (per-car paint stays unique so it can be recoloured and charred).
const glass = new THREE.MeshPhysicalMaterial({ color: 0x0d1418, metalness: 0.9, roughness: 0.08 });
const dark = new THREE.MeshStandardMaterial({ color: 0x151515, roughness: 0.7 });
const chrome = new THREE.MeshStandardMaterial({ color: 0xcccccc, metalness: 1, roughness: 0.25 });
const tyreMat = new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.9 });
const white = new THREE.MeshStandardMaterial({ color: 0xf2f2f2, roughness: 0.5 });

export class CarModel {
  readonly root = new THREE.Group();
  /** Body group: leans and pitches on top of the root transform. */
  readonly body = new THREE.Group();
  private wheels: THREE.Object3D[] = [];
  private frontWheelPivots: THREE.Object3D[] = [];
  private deformables: Deformable[] = [];
  private brakeMat: THREE.MeshStandardMaterial;
  private headMat: THREE.MeshStandardMaterial;
  private paint: THREE.MeshStandardMaterial;
  private beacons: THREE.MeshStandardMaterial[] = [];
  private wheelSpin = 0;
  private wheelR = 0.33;
  /** The car body sits this far forward of the physics centre (when towing a caravan). */
  private carOffset = 0;
  // Suspension springs (angle + angular velocity) for roll and pitch.
  private roll = 0;
  private rollVel = 0;
  private pitchBody = 0;
  private pitchVel = 0;
  private bounce = 0;
  private bounceVel = 0;
  private pendingDents: { lx: number; lz: number; amount: number }[] = [];
  private spec: CarSpec;
  private color: number;
  readonly detachables: THREE.Object3D[] = [];
  private loose: Loose[] = [];
  /** Per-car levels for the batched material: head lights, brake lights, beacon L, beacon R. */
  private lights = new THREE.Vector4(2.2, 1.2, 0, 0);
  /** Every merged body mesh with its untouched positions (dents and lost parts are undone from these). */
  private originals: { mesh: THREE.Mesh; original: Float32Array; normals?: Float32Array }[] = [];
  /** Small parts that vanish into a few pixels at a distance: wheels, calipers, plates. */
  private details: THREE.Object3D[] = [];
  private detailOn = true;

  constructor(spec: CarSpec) {
    this.spec = spec;
    this.color = spec.color;
    this.paint = new THREE.MeshPhysicalMaterial({
      color: spec.color, metalness: 0.55, roughness: 0.32, clearcoat: 1, clearcoatRoughness: 0.12,
    });
    this.headMat = new THREE.MeshStandardMaterial({ color: 0xfff6dd, emissive: 0xfff2cc, emissiveIntensity: 2.2 });
    this.brakeMat = new THREE.MeshStandardMaterial({ color: 0x550000, emissive: 0xff1a1a, emissiveIntensity: 1.2 });

    const template = spec.model ? getModel(spec.model) : undefined;
    if (template) this.buildFromModel(template);
    else if (spec.kind === 'truck') this.buildTruck();
    else this.buildCar();
    if (spec.trailerLength) this.buildCaravan();
    this.root.add(this.body);
    this.batch();
    // Only the big pieces cast shadows: the small parts are hidden under them anyway,
    // and each caster costs an extra draw call in the shadow pass.
    this.root.traverse((o) => {
      if (!(o instanceof THREE.Mesh) || !o.castShadow) return;
      if (!o.geometry.boundingSphere) o.geometry.computeBoundingSphere();
      if (o.geometry.boundingSphere!.radius < 0.75) o.castShadow = false;
    });
  }

  /** Detailed Blender model: per-instance paint and geometry, wheels on steering hubs. */
  private buildFromModel(template: THREE.Object3D): void {
    const spec = this.spec;
    const car = template.clone(true);
    const plateMat = new THREE.MeshStandardMaterial({ map: plateTexture(spec.plate, false), roughness: 0.5 });
    this.carOffset = spec.trailerLength ? totalLength(spec) / 2 - spec.length / 2 : 0;
    this.body.position.z = this.carOffset;
    car.traverse((o) => {
      if (!(o instanceof THREE.Mesh)) return;
      o.castShadow = true;
      const mat = o.material as THREE.MeshStandardMaterial;
      switch (mat.name) {
        case 'Paint':
          if (this.paint.name !== 'Paint') {
            this.paint = mat.clone();
            this.paint.color.setHex(spec.color);
          }
          o.material = this.paint;
          break;
        case 'BrakeLight':
          o.material = this.brakeMat;
          break;
        case 'HeadLight':
          o.material = this.headMat;
          break;
        case 'Plate':
          o.material = plateMat;
          break;
        case 'BeaconL':
        case 'BeaconR': {
          const b = new THREE.MeshStandardMaterial({ color: 0x0a1a66, emissive: 0x2a5cff, emissiveIntensity: 0, roughness: 0.2 });
          this.beacons.push(b);
          o.material = b;
          break;
        }
      }
      if (o.userData.deform) {
        o.geometry = o.geometry.clone();
        const pos = o.geometry.attributes.position as THREE.BufferAttribute;
        this.deformables.push({ mesh: o, original: Float32Array.from(pos.array as Float32Array) });
      }
    });
    // Hubs (steering pivots with a spinning wheel) go on the root so they don't lean with the body.
    for (const child of [...car.children]) {
      if (child.name.startsWith('hub_')) {
        this.root.add(child);
        child.position.z += this.carOffset;
        if (child.userData.steer) this.frontWheelPivots.push(child);
        const wheel = child.children.find((c) => c.userData.spin);
        if (wheel) this.wheels.push(wheel);
      } else {
        this.body.add(child);
        if (child.userData.detach) this.detachables.push(child);
      }
    }
    this.wheelR = car.userData.wheel_r ?? 0.31;
  }

  /**
   * Flatten the built car: per group (body, each wheel, each hub, things towed on the root) one mesh
   * with the batched material, plus one per glass or textured material. Loose parts become vertex
   * ranges; dents keep working through a per-vertex mask.
   */
  private batch(): void {
    this.root.updateMatrixWorld(true);
    // Blender models come with double-sided materials (some panels face inwards); keep that.
    const uber = uberMaterial(this.paint.color, this.lights, this.spec.model ? THREE.DoubleSide : THREE.FrontSide);
    const deformSet = new Set(this.deformables.map((d) => d.mesh));
    const looseOf = new Map<THREE.Object3D, Loose>();
    for (const o of this.detachables) {
      const box = new THREE.Box3().setFromObject(o);
      const centre = box.getCenter(new THREE.Vector3());
      this.body.worldToLocal(centre);
      const l: Loose = { zone: o.userData.zone, centre, ranges: [], gone: false };
      this.loose.push(l);
      o.traverse((c) => looseOf.set(c, l));
    }
    const m4 = new THREE.Matrix4();
    const lin = (c: THREE.Color) => [c.r, c.g, c.b];

    // Attributes for one source mesh under the batched material.
    const bake = (src: THREE.Material, g: THREE.BufferGeometry) => {
      const s = src as THREE.MeshPhysicalMaterial;
      const n = g.attributes.position.count;
      const paint = src === this.paint;
      const col = paint ? [1, 1, 1] : lin(s.color ?? new THREE.Color(1, 1, 1));
      const pbr = [s.metalness ?? 0, s.roughness ?? 0.6, s.clearcoat ?? 0, paint ? 1 : 0];
      let cls = 0;
      let e = s.emissive ? lin(s.emissive).map((v) => v * (s.emissiveIntensity ?? 1)) : [0, 0, 0];
      if (src === this.headMat) (cls = 1), (e = lin(s.emissive));
      else if (src === this.brakeMat) (cls = 2), (e = lin(s.emissive));
      else if (this.beacons.includes(s)) (cls = 3 + this.beacons.indexOf(s)), (e = lin(s.emissive));
      const vc = s.vertexColors ? (g.attributes.color as THREE.BufferAttribute | undefined) : undefined;
      const color = new Float32Array(n * 3);
      const pbrA = new Float32Array(n * 4);
      const emiA = new Float32Array(n * 4);
      for (let i = 0; i < n; i++) {
        const f = vc ? [vc.getX(i), vc.getY(i), vc.getZ(i)] : [1, 1, 1];
        color.set([col[0] * f[0], col[1] * f[1], col[2] * f[2]], i * 3);
        pbrA.set(pbr, i * 4);
        emiA.set([e[0], e[1], e[2], cls], i * 4);
      }
      g.setAttribute('color', new THREE.BufferAttribute(color, 3));
      g.setAttribute('pbr', new THREE.BufferAttribute(pbrA, 4));
      g.setAttribute('emi', new THREE.BufferAttribute(emiA, 4));
    };

    // Merge all meshes under `node` into meshes in the space of `space`, added to `parent`.
    const flatten = (node: THREE.Object3D, space: THREE.Object3D, parent: THREE.Object3D) => {
      interface Bucket { mat: THREE.Material; geos: THREE.BufferGeometry[]; deform: boolean[]; loose: (Loose | undefined)[] }
      const buckets = new Map<THREE.Material, Bucket>();
      const inv = new THREE.Matrix4().copy(space.matrixWorld).invert();
      node.traverse((o) => {
        if (!(o instanceof THREE.Mesh) || Array.isArray(o.material)) return;
        const src = o.material as THREE.MeshStandardMaterial;
        let g = o.geometry.clone();
        g.applyMatrix4(m4.multiplyMatrices(inv, o.matrixWorld));
        if (m4.determinant() < 0) {
          // Mirrored part: flip the winding back.
          const idx = g.index ? Array.from(g.index.array) : [...Array(g.attributes.position.count).keys()];
          for (let t = 0; t < idx.length; t += 3) [idx[t + 1], idx[t + 2]] = [idx[t + 2], idx[t + 1]];
          g.setIndex(idx);
        }
        if (!g.index) g.setIndex([...Array(g.attributes.position.count).keys()]);
        const special = src.transparent || src.name === 'Glass' || src === glass || !!src.map;
        const target = special ? src : uber;
        for (const name of Object.keys(g.attributes)) {
          const keep = name === 'position' || name === 'normal' || (name === 'uv' && special && !!src.map) || (name === 'color' && !special);
          if (!keep) g.deleteAttribute(name);
        }
        if (!special) bake(src, g);
        let b = buckets.get(target);
        if (!b) buckets.set(target, (b = { mat: target, geos: [], deform: [], loose: [] }));
        b.geos.push(g);
        let p: THREE.Object3D | null = o;
        let dm = false;
        while (p && p !== node.parent) {
          if (deformSet.has(p as THREE.Mesh) || p.userData.deform) dm = true;
          p = p.parent;
        }
        b.deform.push(dm);
        b.loose.push(looseOf.get(o));
      });
      for (const b of buckets.values()) {
        if (!b.geos.length) continue;
        const geo = b.geos.length === 1 ? b.geos[0] : mergeGeometries(b.geos, false);
        if (!geo) continue;
        geo.computeBoundingSphere();
        const mesh = new THREE.Mesh(geo, b.mat);
        mesh.castShadow = true;
        mesh.userData.batched = true;
        if ((b.mat as THREE.MeshStandardMaterial).map) this.details.push(mesh);
        parent.add(mesh);
        const mask = new Uint8Array(geo.attributes.position.count);
        let start = 0;
        let anyDeform = false;
        b.geos.forEach((g, k) => {
          const count = g.attributes.position.count;
          if (b.deform[k]) {
            mask.fill(1, start, start + count);
            anyDeform = true;
          }
          b.loose[k]?.ranges.push({ mesh, start, count });
          start += count;
        });
        const original = Float32Array.from(geo.attributes.position.array as Float32Array);
        const normals = geo.attributes.normal ? Float32Array.from(geo.attributes.normal.array as Float32Array) : undefined;
        this.originals.push({ mesh, original, normals });
        if (anyDeform) this.deformables.push({ mesh, original, mask });
      }
    };

    this.deformables = [];
    // Body (leans and pitches).
    const bodyKids = [...this.body.children];
    this.body.updateMatrixWorld(true);
    flatten(this.body, this.body, this.body);
    for (const c of bodyKids) this.body.remove(c);
    // Wheels. Two wheels on one axle spin about the same line, so they become one mesh; steered
    // front wheels of the racers keep their own pivots. Traffic doesn't show steering or calipers.
    const lite = !this.spec.model || this.spec.model.startsWith('tr_') || this.spec.model === 'police';
    const steered = (w: THREE.Object3D) => !lite && this.frontWheelPivots.includes(w.parent!);
    const pivots = new Set<THREE.Object3D>(this.wheels.map((w) => w.parent!));
    const axles = new Map<string, THREE.Object3D[]>();
    const spinning: THREE.Object3D[] = [];
    for (const w of this.wheels) {
      const pivot = w.parent!;
      if (steered(w)) {
        const holder = new THREE.Group();
        holder.position.copy(w.position);
        holder.quaternion.copy(w.quaternion);
        holder.scale.copy(w.scale);
        flatten(w, w, holder);
        pivot.remove(w);
        pivot.add(holder);
        spinning.push(holder);
        continue;
      }
      const key = `${pivot.position.y.toFixed(3)}|${pivot.position.z.toFixed(3)}`;
      if (!axles.has(key)) axles.set(key, []);
      axles.get(key)!.push(w);
    }
    for (const ws of axles.values()) {
      const p0 = ws[0].parent!;
      const axle = new THREE.Group();
      axle.position.set(0, p0.position.y, p0.position.z);
      this.root.add(axle);
      const tmp = new THREE.Group();
      this.root.add(tmp);
      this.root.updateMatrixWorld(true);
      for (const w of ws) tmp.attach(w);
      tmp.updateMatrixWorld(true);
      flatten(tmp, axle, axle);
      this.root.remove(tmp);
      spinning.push(axle);
    }
    this.wheels = spinning;
    this.details.push(...spinning);
    if (lite) this.frontWheelPivots.length = 0;
    // Brake calipers: on a steered pivot they turn with it; on the others they're fixed to the car.
    const fixed = new THREE.Group();
    this.root.add(fixed);
    for (const pivot of pivots) {
      const rest = pivot.children.filter((c) => !spinning.includes(c));
      if (!rest.length) continue;
      if (lite) {
        for (const c of rest) pivot.remove(c);
      } else if (this.frontWheelPivots.includes(pivot)) {
        const tmp = new THREE.Group();
        for (const c of rest) tmp.add(c);
        pivot.add(tmp);
        tmp.updateMatrixWorld(true);
        flatten(tmp, pivot, pivot);
        pivot.remove(tmp);
      } else {
        this.root.updateMatrixWorld(true);
        for (const c of rest) fixed.attach(c);
      }
      if (!this.frontWheelPivots.includes(pivot) && pivot.children.length === 0) pivot.removeFromParent();
    }
    if (fixed.children.length) {
      fixed.updateMatrixWorld(true);
      flatten(fixed, this.root, this.root);
    }
    fixed.removeFromParent();
    pivots.forEach((p) => {
      if (!this.frontWheelPivots.includes(p) && p.children.length === 0) p.removeFromParent();
    });
    // Anything else on the root (a towed caravan).
    for (const c of [...this.root.children]) {
      if (c === this.body || pivots.has(c) || spinning.includes(c) || c.userData.batched) continue;
      const tmp = new THREE.Group();
      this.root.add(tmp);
      tmp.add(c);
      tmp.updateMatrixWorld(true);
      flatten(tmp, this.root, this.root);
      this.root.remove(tmp);
    }
  }

  private addWheel(x: number, z: number, r: number, steer: boolean, width = 0.24): void {
    const wheelGeo = new THREE.CylinderGeometry(r, r, width, 16);
    wheelGeo.rotateZ(Math.PI / 2);
    const rimGeo = new THREE.CylinderGeometry(r * 0.6, r * 0.6, width + 0.01, 8);
    rimGeo.rotateZ(Math.PI / 2);
    const pivot = new THREE.Object3D();
    pivot.position.set(x, r, z);
    const wheel = new THREE.Group();
    const t = new THREE.Mesh(wheelGeo, tyreMat);
    t.castShadow = true;
    wheel.add(t, new THREE.Mesh(rimGeo, chrome));
    pivot.add(wheel);
    this.root.add(pivot);
    this.wheels.push(wheel);
    if (steer) this.frontWheelPivots.push(pivot);
  }

  private buildCar(): void {
    const spec = this.spec;
    const L = spec.length;
    const W = spec.width;
    const H = spec.bodyHeight;
    const ride = 0.3;
    const van = spec.kind === 'van';
    this.carOffset = spec.trailerLength ? totalLength(spec) / 2 - L / 2 : 0;
    this.body.position.z = this.carOffset;

    // Lower body with a sloped hood and tapered tail.
    const bodyGeo = new THREE.BoxGeometry(W, H, L, 6, 3, 14);
    const pos = bodyGeo.attributes.position as THREE.BufferAttribute;
    for (let i = 0; i < pos.count; i++) {
      let y = pos.getY(i);
      const z = pos.getZ(i);
      let x = pos.getX(i);
      const zf = z / (L / 2);
      if (!van && y > 0 && zf > 0.55) y -= (zf - 0.55) * H * 0.55; // hood slope
      if (van && y > 0 && zf > 0.8) y -= (zf - 0.8) * H * 0.6;
      if (!van && y > 0 && zf < -0.8) y -= (-zf - 0.8) * H * 0.4;
      if (Math.abs(zf) > 0.9) x *= 0.94;
      if (y < 0) x *= 0.97;
      pos.setXYZ(i, x, y, z);
    }
    bodyGeo.computeVertexNormals();
    const bodyMesh = new THREE.Mesh(bodyGeo, this.paint);
    bodyMesh.position.y = ride + H / 2;
    bodyMesh.castShadow = true;
    this.body.add(bodyMesh);
    this.deformables.push({ mesh: bodyMesh, original: Float32Array.from(pos.array as Float32Array) });

    // Cabin / greenhouse.
    const cl = spec.cabinLength;
    const ch = spec.cabinHeight;
    const cabGeo = new THREE.BoxGeometry(W * 0.86, ch, cl, 4, 2, 8);
    const cpos = cabGeo.attributes.position as THREE.BufferAttribute;
    for (let i = 0; i < cpos.count; i++) {
      let x = cpos.getX(i);
      const y = cpos.getY(i);
      let z = cpos.getZ(i);
      if (y > 0) {
        x *= van ? 0.95 : 0.84;
        if (z > 0) z -= cl * (van ? 0.18 : 0.28); // windscreen rake
        else if (!spec.hatch) z += cl * 0.22; // fastback
        else z += cl * 0.04;
      }
      cpos.setXYZ(i, x, y, z);
    }
    cabGeo.computeVertexNormals();
    const cabin = new THREE.Mesh(cabGeo, glass);
    cabin.position.set(0, ride + H + ch / 2 - 0.02, spec.cabinOffset);
    cabin.castShadow = true;
    this.body.add(cabin);
    this.deformables.push({ mesh: cabin, original: Float32Array.from(cpos.array as Float32Array) });

    if (van) {
      // Tall cargo box behind the cab.
      const cargoLen = L / 2 + (spec.cabinOffset - cl / 2) + 0.05;
      const cargo = new THREE.Mesh(new THREE.BoxGeometry(W * 0.98, ch, cargoLen), this.paint);
      cargo.position.set(0, ride + H + ch / 2 - 0.02, -L / 2 + cargoLen / 2);
      cargo.castShadow = true;
      this.body.add(cargo);
    }

    // Roof panel in body colour (or contrast colour).
    const roofMat = spec.roofColor !== undefined ? new THREE.MeshStandardMaterial({ color: spec.roofColor, roughness: 0.4 }) : this.paint;
    const roofLen = cl * (van ? 0.6 : 0.5);
    const roofY = ride + H + ch;
    const roof = new THREE.Mesh(new THREE.BoxGeometry(W * (van ? 0.8 : 0.7), 0.05, roofLen), roofMat);
    roof.position.set(0, roofY, spec.cabinOffset + (spec.hatch ? -0.1 : 0));
    this.body.add(roof);
    this.detachables.push(roof);

    if (spec.stripeColor !== undefined) {
      const sm = new THREE.MeshStandardMaterial({ color: spec.stripeColor, roughness: 0.35 });
      for (const x of [-0.16, 0.16]) {
        const st = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.012, roofLen + 0.02), sm);
        st.position.set(x, roofY + 0.03, roof.position.z);
        const boot = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.012, L * 0.16), sm);
        boot.position.set(x, ride + H + 0.006, -L / 2 + L * 0.13);
        const hood = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.012, L * 0.2), sm);
        hood.position.set(x, ride + H - 0.01, spec.cabinOffset + cl / 2 + L * 0.1);
        this.body.add(st, boot, hood);
      }
    }

    if (spec.livery === 'police') this.policeLivery(W, L, ride, H, roofY, roof.position.z);
    if (spec.livery === 'delivery') {
      // Thuisbesteld roof box.
      const tex = textTexture('Thuisbesteld', '#ff7a00', '#ffffff', 512, 160, 'bold 78px Arial, sans-serif');
      const boxMat = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.6 });
      const box = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.45, 0.7), [boxMat, boxMat, white, white, boxMat, boxMat]);
      box.position.set(0, roofY + 0.25, roof.position.z - 0.1);
      box.castShadow = true;
      this.body.add(box);
      this.detachables.push(box);
    }

    // Lights.
    for (const side of [-1, 1]) {
      const head = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.12, 0.05), this.headMat);
      head.position.set(side * (W / 2 - 0.3), ride + H * 0.62, L / 2 + 0.005);
      this.body.add(head);
      const tail = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.14, 0.05), this.brakeMat);
      tail.position.set(side * (W / 2 - 0.32), ride + H * 0.7, -L / 2 - 0.005);
      this.body.add(tail);
    }

    // Bumpers & plates.
    const bumperF = new THREE.Mesh(new THREE.BoxGeometry(W * 1.01, 0.18, 0.16), dark);
    bumperF.position.set(0, ride + 0.12, L / 2);
    const bumperR = bumperF.clone();
    bumperR.position.z = -L / 2;
    this.body.add(bumperF, bumperR);
    this.detachables.push(bumperF, bumperR);
    const plateMat = new THREE.MeshStandardMaterial({ map: plateTexture(spec.plate), roughness: 0.5 });
    const plateGeo = new THREE.PlaneGeometry(0.52, 0.115);
    const plateR = new THREE.Mesh(plateGeo, plateMat);
    plateR.rotation.y = Math.PI;
    plateR.position.set(0, ride + 0.32, -L / 2 - 0.09);
    const plateF = new THREE.Mesh(plateGeo, plateMat);
    plateF.position.set(0, ride + 0.14, L / 2 + 0.09);
    this.body.add(plateR, plateF);

    if (spec.spoiler) {
      const wing = new THREE.Mesh(new THREE.BoxGeometry(W * 0.9, 0.05, 0.3), this.paint);
      wing.position.set(0, ride + H + 0.28, -L / 2 + 0.25);
      const stand = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.28, 0.12), dark);
      const stand2 = stand.clone();
      stand.position.set(-W * 0.3, ride + H + 0.13, -L / 2 + 0.25);
      stand2.position.set(W * 0.3, ride + H + 0.13, -L / 2 + 0.25);
      this.body.add(wing, stand, stand2);
      this.detachables.push(wing);
    }

    // Mirrors.
    for (const side of [-1, 1]) {
      const mirror = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.1, 0.12), this.paint);
      mirror.position.set(side * (W / 2 + 0.06), ride + H + 0.08, spec.cabinOffset + cl / 2 - 0.25);
      this.body.add(mirror);
      this.detachables.push(mirror);
    }

    // Wheels (outside the body group so they don't lean).
    const r = van ? 0.36 : 0.33;
    this.wheelR = r;
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
      this.addWheel(sx * (W / 2 - 0.12), this.carOffset + sz * (L / 2 - 0.75), r, sz > 0);
    }
  }

  private policeLivery(W: number, L: number, ride: number, H: number, roofY: number, roofZ: number): void {
    // Dutch police: blue band with a thin orange-red band, "POLITIE" lettering, roof light bar.
    const blue = new THREE.MeshStandardMaterial({ color: 0x1f3d9a, roughness: 0.4 });
    const orange = new THREE.MeshStandardMaterial({ color: 0xff5a1f, roughness: 0.4 });
    const text = new THREE.MeshStandardMaterial({ map: textTexture('POLITIE', '#1f3d9a', '#ffffff', 512, 96, 'bold 70px Arial, sans-serif'), roughness: 0.4 });
    for (const side of [-1, 1]) {
      const band = new THREE.Mesh(new THREE.BoxGeometry(0.02, H * 0.32, L * 0.9), blue);
      band.position.set(side * (W / 2 + 0.005), ride + H * 0.55, 0);
      const thin = new THREE.Mesh(new THREE.BoxGeometry(0.02, H * 0.08, L * 0.9), orange);
      thin.position.set(side * (W / 2 + 0.006), ride + H * 0.3, 0);
      const label = new THREE.Mesh(new THREE.PlaneGeometry(1.5, 0.22), text);
      label.position.set(side * (W / 2 + 0.02), ride + H * 0.55, -0.2);
      label.rotation.y = (side * Math.PI) / 2; // face outwards
      this.body.add(band, thin, label);
    }
    const bar = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.1, 0.28), dark);
    bar.position.set(0, roofY + 0.08, roofZ);
    this.body.add(bar);
    for (const side of [-1, 1]) {
      const m = new THREE.MeshStandardMaterial({ color: 0x0a1a66, emissive: 0x2a5cff, emissiveIntensity: 0 });
      const lamp = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.14, 0.26), m);
      lamp.position.set(side * 0.32, roofY + 0.18, roofZ);
      this.body.add(lamp);
      this.beacons.push(m);
    }
  }

  private buildTruck(): void {
    const spec = this.spec;
    const L = totalLength(spec);
    const W = spec.width;
    const cabLen = 2.3;
    // Cab
    const cab = new THREE.Mesh(new THREE.BoxGeometry(W * 0.98, 2.6, cabLen), this.paint);
    cab.position.set(0, 0.65 + 1.3, L / 2 - cabLen / 2);
    cab.castShadow = true;
    const screen = new THREE.Mesh(new THREE.PlaneGeometry(W * 0.85, 0.9), glass);
    screen.position.set(0, 2.55, L / 2 + 0.01);
    const grille = new THREE.Mesh(new THREE.BoxGeometry(W * 0.9, 0.6, 0.06), dark);
    grille.position.set(0, 1.1, L / 2 + 0.02);
    this.body.add(cab, screen, grille);
    for (const side of [-1, 1]) {
      const head = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.18, 0.05), this.headMat);
      head.position.set(side * (W / 2 - 0.35), 0.75, L / 2 + 0.03);
      this.body.add(head);
    }
    // Trailer with company lettering.
    const tl = L - cabLen - 0.4;
    const company = spec.trailerText ?? 'Tukker Transport';
    const side = new THREE.MeshStandardMaterial({ map: textTexture(company, '#eeeeee', '#1d3f7a', 1024, 192, 'bold italic 110px Arial, sans-serif'), roughness: 0.6 });
    const plain = new THREE.MeshStandardMaterial({ color: 0xe6e6e6, roughness: 0.6 });
    const trailer = new THREE.Mesh(new THREE.BoxGeometry(W, 2.9, tl), [side, side, plain, plain, plain, plain]);
    trailer.position.set(0, 1.15 + 1.45, -L / 2 + tl / 2);
    trailer.castShadow = true;
    const chassis = new THREE.Mesh(new THREE.BoxGeometry(W * 0.7, 0.35, L - 0.4), dark);
    chassis.position.set(0, 0.9, 0);
    this.body.add(trailer, chassis);
    for (const sx of [-1, 1]) {
      const tail = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.16, 0.05), this.brakeMat);
      tail.position.set(sx * (W / 2 - 0.3), 1.0, -L / 2 - 0.02);
      this.body.add(tail);
    }
    const plateMat = new THREE.MeshStandardMaterial({ map: plateTexture(spec.plate), roughness: 0.5 });
    const plate = new THREE.Mesh(new THREE.PlaneGeometry(0.52, 0.115), plateMat);
    plate.rotation.y = Math.PI;
    plate.position.set(0, 0.8, -L / 2 - 0.03);
    this.body.add(plate);
    this.wheelR = 0.52;
    for (const sx of [-1, 1]) {
      this.addWheel(sx * (W / 2 - 0.2), L / 2 - 1.2, 0.52, false, 0.32);
      this.addWheel(sx * (W / 2 - 0.2), L / 2 - 4.2, 0.52, false, 0.32);
      for (const z of [-L / 2 + 1.2, -L / 2 + 2.5, -L / 2 + 3.8]) this.addWheel(sx * (W / 2 - 0.2), z, 0.52, false, 0.32);
    }
  }

  private buildCaravan(): void {
    const spec = this.spec;
    const T = spec.trailerLength!;
    const L = totalLength(spec);
    const g = new THREE.Group();
    const shell = new THREE.Mesh(new THREE.BoxGeometry(2.2, 2.2, T), white);
    shell.position.set(0, 0.45 + 1.1, 0);
    shell.castShadow = true;
    const stripe = new THREE.Mesh(new THREE.BoxGeometry(2.22, 0.18, T * 0.98), new THREE.MeshStandardMaterial({ color: 0x9a6a3a }));
    stripe.position.set(0, 1.1, 0);
    const win = new THREE.Mesh(new THREE.BoxGeometry(2.23, 0.5, T * 0.5), glass);
    win.position.set(0, 1.75, 0.2);
    const bar = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.1, 1.1), dark);
    bar.position.set(0, 0.45, T / 2 + 0.5);
    g.add(shell, stripe, win, bar);
    for (const sx of [-1, 1]) {
      const tail = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.12, 0.04), this.brakeMat);
      tail.position.set(sx * 0.85, 0.75, -T / 2 - 0.02);
      g.add(tail);
    }
    g.position.z = -L / 2 + T / 2;
    this.root.add(g);
    for (const sx of [-1, 1]) this.addWheel(sx * 1.0, g.position.z, 0.3, false);
  }

  /** New paint colour (recycled traffic). */
  recolor(hex: number): void {
    this.color = hex;
    this.paint.color.setHex(hex);
  }

  /** Jolt the suspension from an impact at world offset (wx, wz) from the car centre. */
  kick(wx: number, wz: number, v: Vehicle, strength: number): void {
    const fx = Math.sin(v.heading);
    const fz = Math.cos(v.heading);
    const lx = wx * -fz + wz * fx;
    const lz = wx * fx + wz * fz;
    const s = Math.min(1.2, strength * 0.06);
    this.rollVel += Math.sign(lx) * s * (Math.abs(lx) > 0.5 ? 1 : 0.3);
    this.pitchVel += Math.sign(lz) * s * 0.6;
    this.bounceVel += s * 0.8;
  }

  /** Queue a dent at a local contact point (lx right, lz forward). */
  dent(amount: number, lx: number, lz: number): void {
    this.pendingDents.push({ lx, lz, amount });
  }

  private applyDents(): void {
    if (!this.pendingDents.length) return;
    // Merge tiny scrape dents so we don't rebuild normals every frame.
    const total = this.pendingDents.reduce((a, d) => a + d.amount, 0);
    if (total < 1.2 && this.pendingDents.length < 30) return;
    for (const { mesh, mask } of this.deformables) {
      const pos = mesh.geometry.attributes.position as THREE.BufferAttribute;
      const off = mesh.position;
      for (const dent of this.pendingDents) {
        // Model space: +x is left of the car's right (we use -lx since right = -X in model space).
        const cx = -dent.lx;
        const cz = dent.lz - this.carOffset;
        const strength = Math.min(0.5, dent.amount * 0.012);
        for (let i = 0; i < pos.count; i++) {
          if (mask && !mask[i]) continue;
          const x = pos.getX(i) + off.x;
          const z = pos.getZ(i) + off.z;
          const dist = Math.hypot(x - cx, z - cz);
          if (dist > 1.1) continue;
          const f = (1 - dist / 1.1) ** 2 * strength;
          // Push towards the car's centre line, plus a little random crumple.
          const len = Math.hypot(x, z) || 1;
          pos.setX(i, pos.getX(i) - (x / len) * f * 0.8);
          pos.setZ(i, pos.getZ(i) - (z / len) * f * 0.8);
          pos.setY(i, pos.getY(i) - f * 0.25 * Math.random());
        }
      }
      pos.needsUpdate = true;
      mesh.geometry.computeVertexNormals();
    }
    this.pendingDents.length = 0;
  }

  /** Called by the game when a zone gets heavily damaged: drop loose parts. */
  zoneDamaged(zone: Zone, level: number): boolean {
    if (level < 60) return false;
    const part = this.loose.find((l) => {
      if (l.gone) return false;
      if (l.zone && l.zone !== 'top') return l.zone === zone;
      const c = l.centre;
      if (zone === 'front') return c.z > 1;
      if (zone === 'rear') return c.z < -1 || c.y > 1;
      if (zone === 'left') return c.x > 0.5;
      return c.x < -0.5;
    });
    if (!part) return false;
    part.gone = true;
    // Collapse its vertices onto one point: the part is gone, the merged mesh stays one draw call.
    for (const { mesh, start, count } of part.ranges) {
      const pos = mesh.geometry.attributes.position as THREE.BufferAttribute;
      const x = pos.getX(start);
      const y = pos.getY(start);
      const z = pos.getZ(start);
      for (let i = start; i < start + count; i++) pos.setXYZ(i, x, y, z);
      pos.needsUpdate = true;
    }
    return true;
  }

  repair(): void {
    for (const d of this.originals) {
      const pos = d.mesh.geometry.attributes.position as THREE.BufferAttribute;
      (pos.array as Float32Array).set(d.original);
      pos.needsUpdate = true;
      if (d.normals) {
        const nrm = d.mesh.geometry.attributes.normal as THREE.BufferAttribute;
        (nrm.array as Float32Array).set(d.normals);
        nrm.needsUpdate = true;
      }
    }
    for (const l of this.loose) l.gone = false;
    this.pendingDents.length = 0;
    this.paint.color.setHex(this.color);
  }

  sync(v: Vehicle, dt: number): void {
    this.applyDents();
    this.root.position.set(v.x, v.y, v.z);
    this.root.rotation.set(0, v.heading, 0);
    this.root.rotateX(v.pitch);

    // Body roll and pitch on soft, slightly underdamped springs: the car feels heavy.
    const latAcc = v.forwardSpeed * v.angVel;
    const rollTarget = Math.max(-0.11, Math.min(0.11, latAcc * 0.009));
    const pitchTarget = Math.max(-0.05, Math.min(0.06, v.accelLong * -0.0035));
    const k = 55; // stiffness
    const c = 7; // damping
    if (dt > 0) {
      this.rollVel += ((rollTarget - this.roll) * k - this.rollVel * c) * dt;
      this.roll += this.rollVel * dt;
      this.pitchVel += ((pitchTarget - this.pitchBody) * k - this.pitchVel * c) * dt;
      this.pitchBody += this.pitchVel * dt;
      this.bounceVel += (-this.bounce * 90 - this.bounceVel * 9) * dt;
      this.bounce += this.bounceVel * dt;
    }
    this.body.rotation.z = this.roll;
    this.body.rotation.x = this.pitchBody; // positive = nose down (braking)
    this.body.position.y = this.bounce;
    this.body.position.z = this.carOffset;

    this.wheelSpin += (v.forwardSpeed / this.wheelR) * dt;
    for (const w of this.wheels) w.rotation.x = this.wheelSpin;
    for (const p of this.frontWheelPivots) p.rotation.y = -v.input.steer * 0.45;

    this.brakeMat.emissiveIntensity = v.braking ? 5 : 1.2;
    this.headMat.emissiveIntensity = v.wrecked ? 0 : 2.2;
    this.lights.x = this.headMat.emissiveIntensity;
    this.lights.y = this.brakeMat.emissiveIntensity;
    if (v.wrecked) this.paint.color.lerp(new THREE.Color(0x221a16), Math.min(1, dt * 0.6));
    if (this.beacons.length) {
      // Alternating blue flashes, two quick pulses per side.
      const t = performance.now() / 1000;
      const phase = (t * 2.2) % 1;
      const pulse = (p: number) => (Math.sin(p * Math.PI * 8) > 0.2 ? 6 : 0);
      this.beacons[0].emissiveIntensity = v.sirenOn && phase < 0.5 ? pulse(phase) : 0;
      this.beacons[1].emissiveIntensity = v.sirenOn && phase >= 0.5 ? pulse(phase) : 0;
      this.lights.z = this.beacons[0].emissiveIntensity;
      this.lights.w = this.beacons[1].emissiveIntensity;
    }
  }

  /** Level of detail: far away, drop the parts nobody can see anyway. */
  setDetail(on: boolean): void {
    if (on === this.detailOn) return;
    this.detailOn = on;
    for (const o of this.details) o.visible = on;
    for (const p of this.frontWheelPivots) p.visible = on;
  }

  /** For kinematic (oncoming) traffic that isn't a physics Vehicle. */
  place(x: number, y: number, z: number, heading: number, speed: number, dt: number): void {
    this.root.position.set(x, y, z);
    this.root.rotation.set(0, heading, 0);
    this.wheelSpin += (speed / this.wheelR) * dt;
    for (const w of this.wheels) w.rotation.x = this.wheelSpin;
  }
}
