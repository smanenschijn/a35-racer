import * as THREE from 'three';
import type { CarSpec } from '../config';
import type { Vehicle, Zone } from './Vehicle';

// Procedural low-poly 90s car. Body panels are subdivided boxes whose vertices get pushed
// in on impact, so damage shows up as real dents.

const plateCache = new Map<string, THREE.Texture>();
function plateTexture(text: string): THREE.Texture {
  let tex = plateCache.get(text);
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
  plateCache.set(text, tex);
  return tex;
}

interface Deformable {
  mesh: THREE.Mesh;
  original: Float32Array;
}

export class CarModel {
  readonly root = new THREE.Group();
  /** Body group: leans and pitches on top of the root transform. */
  readonly body = new THREE.Group();
  private wheels: THREE.Object3D[] = [];
  private frontWheelPivots: THREE.Object3D[] = [];
  private deformables: Deformable[] = [];
  private brakeMat: THREE.MeshStandardMaterial;
  private headMat: THREE.MeshStandardMaterial;
  private paint: THREE.MeshPhysicalMaterial;
  private wheelSpin = 0;
  // Suspension springs (angle + angular velocity) for roll and pitch.
  private roll = 0;
  private rollVel = 0;
  private pitchBody = 0;
  private pitchVel = 0;
  private bounce = 0;
  private bounceVel = 0;
  private pendingDents: { lx: number; lz: number; amount: number }[] = [];
  private spec: CarSpec;
  readonly detachables: THREE.Object3D[] = [];

  constructor(spec: CarSpec) {
    this.spec = spec;
    const L = spec.length;
    const W = spec.width;
    const H = spec.bodyHeight;
    const ride = 0.3;

    this.paint = new THREE.MeshPhysicalMaterial({
      color: spec.color, metalness: 0.55, roughness: 0.32, clearcoat: 1, clearcoatRoughness: 0.12,
    });
    const glass = new THREE.MeshPhysicalMaterial({ color: 0x0d1418, metalness: 0.9, roughness: 0.08 });
    const dark = new THREE.MeshStandardMaterial({ color: 0x151515, roughness: 0.7 });
    const chrome = new THREE.MeshStandardMaterial({ color: 0xcccccc, metalness: 1, roughness: 0.25 });
    this.headMat = new THREE.MeshStandardMaterial({ color: 0xfff6dd, emissive: 0xfff2cc, emissiveIntensity: 2.2 });
    this.brakeMat = new THREE.MeshStandardMaterial({ color: 0x550000, emissive: 0xff1a1a, emissiveIntensity: 1.2 });

    // Lower body with a sloped hood and tapered tail.
    const bodyGeo = new THREE.BoxGeometry(W, H, L, 6, 3, 14);
    const pos = bodyGeo.attributes.position as THREE.BufferAttribute;
    for (let i = 0; i < pos.count; i++) {
      let y = pos.getY(i);
      const z = pos.getZ(i);
      let x = pos.getX(i);
      const zf = z / (L / 2);
      if (y > 0 && zf > 0.55) y -= (zf - 0.55) * H * 0.55; // hood slope
      if (y > 0 && zf < -0.8) y -= (-zf - 0.8) * H * 0.4;
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
        x *= 0.84;
        if (z > 0) z -= cl * 0.28; // windscreen rake
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

    // Roof panel in body colour.
    const roof = new THREE.Mesh(new THREE.BoxGeometry(W * 0.7, 0.05, cl * 0.5), this.paint);
    roof.position.set(0, ride + H + ch - 0.0, spec.cabinOffset + (spec.hatch ? -0.1 : 0));
    this.body.add(roof);
    this.detachables.push(roof);

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

    this.root.add(this.body);

    // Wheels (outside the body group so they don't lean).
    const wheelGeo = new THREE.CylinderGeometry(0.33, 0.33, 0.24, 18);
    wheelGeo.rotateZ(Math.PI / 2);
    const rimGeo = new THREE.CylinderGeometry(0.2, 0.2, 0.25, 8);
    rimGeo.rotateZ(Math.PI / 2);
    const tyre = new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.9 });
    for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
      const pivot = new THREE.Object3D();
      pivot.position.set(sx * (W / 2 - 0.12), 0.33, sz * (L / 2 - 0.75));
      const wheel = new THREE.Group();
      const t = new THREE.Mesh(wheelGeo, tyre);
      t.castShadow = true;
      wheel.add(t, new THREE.Mesh(rimGeo, chrome));
      pivot.add(wheel);
      this.root.add(pivot);
      this.wheels.push(wheel);
      if (sz > 0) this.frontWheelPivots.push(pivot);
    }
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
        const cz = dent.lz;
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
    this.paint.color.setHex(this.spec.color);
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

    this.wheelSpin += (v.forwardSpeed / 0.33) * dt;
    for (const w of this.wheels) w.rotation.x = this.wheelSpin;
    for (const p of this.frontWheelPivots) p.rotation.y = -v.input.steer * 0.45;

    this.brakeMat.emissiveIntensity = v.braking ? 5 : 1.2;
    this.headMat.emissiveIntensity = v.wrecked ? 0 : 2.2;
    if (v.wrecked) this.paint.color.lerp(new THREE.Color(0x221a16), Math.min(1, dt * 0.6));
  }
}
