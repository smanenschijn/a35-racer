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
        if (child.userData.steer) this.frontWheelPivots.push(child);
        const wheel = child.children.find((c) => c.userData.spin);
        if (wheel) this.wheels.push(wheel);
      } else {
        this.body.add(child);
        if (child.userData.detach) this.detachables.push(child);
      }
    }
    this.wheelR = car.userData.wheel_r ?? 0.31;
    this.mergeStatic();
  }

  /**
   * Merge every body part that can't break off into one mesh per material. A detailed car
   * has ~100 parts; this brings it down to a dozen draw calls. Dents keep working because
   * the merged meshes become the deformables.
   */
  private mergeStatic(): void {
    const groups = new Map<THREE.Material, THREE.BufferGeometry[]>();
    const deformMats = new Set<THREE.Material>();
    const merged: THREE.Object3D[] = [];
    this.body.updateMatrixWorld(true);
    const toBody = new THREE.Matrix4().copy(this.body.matrixWorld).invert();
    const m = new THREE.Matrix4();
    for (const child of this.body.children) {
      if (this.detachables.includes(child)) continue;
      child.traverse((o) => {
        if (!(o instanceof THREE.Mesh)) return;
        const g = o.geometry.clone();
        g.applyMatrix4(m.multiplyMatrices(toBody, o.matrixWorld));
        for (const name of Object.keys(g.attributes)) if (name !== 'position' && name !== 'normal') g.deleteAttribute(name);
        const mat = o.material as THREE.Material;
        if (!groups.has(mat)) groups.set(mat, []);
        groups.get(mat)!.push(g.index ? g : g.setIndex([...Array(g.attributes.position.count).keys()]));
        if (o.userData.deform) deformMats.add(mat);
      });
      merged.push(child);
    }
    for (const c of merged) this.body.remove(c);
    this.deformables = [];
    for (const [mat, geos] of groups) {
      const geo = mergeGeometries(geos, false);
      if (!geo) continue;
      const mesh = new THREE.Mesh(geo, mat);
      mesh.castShadow = true;
      this.body.add(mesh);
      if (deformMats.has(mat)) {
        const pos = geo.attributes.position as THREE.BufferAttribute;
        this.deformables.push({ mesh, original: Float32Array.from(pos.array as Float32Array) });
      }
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
    for (const { mesh } of this.deformables) {
      const pos = mesh.geometry.attributes.position as THREE.BufferAttribute;
      const off = mesh.position;
      for (const dent of this.pendingDents) {
        // Model space: +x is left of the car's right (we use -lx since right = -X in model space).
        const cx = -dent.lx;
        const cz = dent.lz - this.carOffset;
        const strength = Math.min(0.5, dent.amount * 0.012);
        for (let i = 0; i < pos.count; i++) {
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
  zoneDamaged(zone: Zone, level: number): THREE.Object3D | null {
    if (level < 60) return null;
    const candidates = this.detachables.filter((o) => o.parent === this.body && o.visible).filter((o) => {
      if (o.userData.zone) return o.userData.zone === zone;
      if (zone === 'front') return o.position.z > 1;
      if (zone === 'rear') return o.position.z < -1 || o.position.y > 1;
      if (zone === 'left') return o.position.x > 0.5;
      return o.position.x < -0.5;
    });
    const part = candidates[0];
    if (!part) return null;
    part.visible = false;
    return part;
  }

  repair(): void {
    for (const d of this.deformables) {
      const pos = d.mesh.geometry.attributes.position as THREE.BufferAttribute;
      (pos.array as Float32Array).set(d.original);
      pos.needsUpdate = true;
      d.mesh.geometry.computeVertexNormals();
    }
    for (const o of this.detachables) o.visible = true;
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
    if (v.wrecked) this.paint.color.lerp(new THREE.Color(0x221a16), Math.min(1, dt * 0.6));
    if (this.beacons.length) {
      // Alternating blue flashes, two quick pulses per side.
      const t = performance.now() / 1000;
      const phase = (t * 2.2) % 1;
      const pulse = (p: number) => (Math.sin(p * Math.PI * 8) > 0.2 ? 6 : 0);
      this.beacons[0].emissiveIntensity = v.sirenOn && phase < 0.5 ? pulse(phase) : 0;
      this.beacons[1].emissiveIntensity = v.sirenOn && phase >= 0.5 ? pulse(phase) : 0;
    }
  }

  /** For kinematic (oncoming) traffic that isn't a physics Vehicle. */
  place(x: number, y: number, z: number, heading: number, speed: number, dt: number): void {
    this.root.position.set(x, y, z);
    this.root.rotation.set(0, heading, 0);
    this.wheelSpin += (speed / this.wheelR) * dt;
    for (const w of this.wheels) w.rotation.x = this.wheelSpin;
  }
}
