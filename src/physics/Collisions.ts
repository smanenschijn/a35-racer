import { tuning } from '../config';
import type { EventBus } from '../core/Events';
import type { Vehicle } from '../vehicle/Vehicle';

// 2D oriented-box collisions between vehicles (XZ plane), resolved with an impulse
// that includes rotation, so side hits spin cars and nose-to-tail hits push them.

interface Box {
  cx: number;
  cz: number;
  ax: [number, number][]; // forward, right unit axes
  ext: [number, number]; // half length, half width
  corners: [number, number][];
}

function boxOf(v: Vehicle): Box {
  const fx = Math.sin(v.heading);
  const fz = Math.cos(v.heading);
  const rx = -fz;
  const rz = fx;
  const corners: [number, number][] = [];
  for (const a of [1, -1]) {
    for (const b of [1, -1]) {
      corners.push([v.x + fx * v.halfL * a + rx * v.halfW * b, v.z + fz * v.halfL * a + rz * v.halfW * b]);
    }
  }
  return { cx: v.x, cz: v.z, ax: [[fx, fz], [rx, rz]], ext: [v.halfL, v.halfW], corners };
}

function project(box: Box, nx: number, nz: number): [number, number] {
  let min = Infinity;
  let max = -Infinity;
  for (const [x, z] of box.corners) {
    const p = x * nx + z * nz;
    if (p < min) min = p;
    if (p > max) max = p;
  }
  return [min, max];
}

function inside(box: Box, x: number, z: number, margin = 0.02): boolean {
  const dx = x - box.cx;
  const dz = z - box.cz;
  for (let i = 0; i < 2; i++) {
    const p = dx * box.ax[i][0] + dz * box.ax[i][1];
    if (Math.abs(p) > box.ext[i] + margin) return false;
  }
  return true;
}

export function collideVehicles(a: Vehicle, b: Vehicle, time: number, events: EventBus): boolean {
  // Cheap reject
  const dx = b.x - a.x;
  const dz = b.z - a.z;
  const reach = a.halfL + b.halfL;
  if (dx * dx + dz * dz > reach * reach) return false;
  if (Math.abs(a.y - b.y) > 2) return false;

  const A = boxOf(a);
  const B = boxOf(b);
  let depth = Infinity;
  let nx = 0;
  let nz = 0;
  for (const [ax, az] of [...A.ax, ...B.ax]) {
    const [amin, amax] = project(A, ax, az);
    const [bmin, bmax] = project(B, ax, az);
    const overlap = Math.min(amax, bmax) - Math.max(amin, bmin);
    if (overlap <= 0) return false;
    if (overlap < depth) {
      depth = overlap;
      nx = ax;
      nz = az;
    }
  }
  // Normal from A to B.
  if (nx * dx + nz * dz < 0) {
    nx = -nx;
    nz = -nz;
  }

  // Contact point: a corner of one box that lies inside the other.
  let px = 0;
  let pz = 0;
  let found = 0;
  for (const [x, z] of B.corners) if (inside(A, x, z)) { px += x; pz += z; found++; }
  for (const [x, z] of A.corners) if (inside(B, x, z)) { px += x; pz += z; found++; }
  if (found) {
    px /= found;
    pz /= found;
  } else {
    px = (a.x + b.x) / 2;
    pz = (a.z + b.z) / 2;
  }

  // Effective masses (a ramming car hits like a heavier car).
  const ma = a.mass * (a.ramming ? tuning.ramMassFactor : 1);
  const mb = b.mass * (b.ramming ? tuning.ramMassFactor : 1);
  // A rammer is also much harder to spin, so the shove doesn't throw you off yourself.
  const ia = a.inertia * (a.ramming ? tuning.ramMassFactor * 3 : 1);
  const ib = b.inertia * (b.ramming ? tuning.ramMassFactor * 3 : 1);

  // Positional correction split by mass.
  const total = ma + mb;
  a.x -= nx * depth * (mb / total);
  a.z -= nz * depth * (mb / total);
  b.x += nx * depth * (ma / total);
  b.z += nz * depth * (ma / total);

  const rax = px - a.x;
  const raz = pz - a.z;
  const rbx = px - b.x;
  const rbz = pz - b.z;
  // Velocity of the contact point: v + ω × r, with ω × r = (ω r.z, -ω r.x) in our convention.
  const vax = a.vx + a.angVel * raz;
  const vaz = a.vz - a.angVel * rax;
  const vbx = b.vx + b.angVel * rbz;
  const vbz = b.vz - b.angVel * rbx;
  const rvx = vbx - vax;
  const rvz = vbz - vaz;
  const vn = rvx * nx + rvz * nz;
  if (vn >= 0) return true; // already separating

  const cra = raz * nx - rax * nz;
  const crb = rbz * nx - rbx * nz;
  const denom = 1 / ma + 1 / mb + (cra * cra) / ia + (crb * crb) / ib;
  const j = (-(1 + tuning.carRestitution) * vn) / denom;

  // Friction along the tangent.
  let tx = rvx - vn * nx;
  let tz = rvz - vn * nz;
  const tl = Math.hypot(tx, tz);
  let jt = 0;
  if (tl > 1e-4) {
    tx /= tl;
    tz /= tl;
    const crat = raz * tx - rax * tz;
    const crbt = rbz * tx - rbx * tz;
    const denomT = 1 / ma + 1 / mb + (crat * crat) / ia + (crbt * crbt) / ib;
    jt = Math.min(tl / denomT, tuning.carFriction * j);
  }

  const jx = j * nx + jt * tx;
  const jz = j * nz + jt * tz;
  a.vx -= jx / ma;
  a.vz -= jz / ma;
  a.angVel -= (raz * jx - rax * jz) / ia;
  b.vx += jx / mb;
  b.vz += jz / mb;
  b.angVel += (rbz * jx - rbx * jz) / ib;

  if (a.ramming) a.ramLanded();
  if (b.ramming) b.ramLanded();

  // Damage, scaled by who was ramming whom.
  const base = j * tuning.damagePerImpulse;
  const toA = base * (b.ramming ? tuning.ramDamageFactor : 1) * (a.ramming ? 0.5 : 1);
  const toB = base * (a.ramming ? tuning.ramDamageFactor : 1) * (b.ramming ? 0.5 : 1);
  const local = (v: Vehicle, wx: number, wz: number): [number, number] => {
    const fx = Math.sin(v.heading);
    const fz = Math.cos(v.heading);
    return [wx * -fz + wz * fx, wx * fx + wz * fz];
  };
  const [alx, alz] = local(a, rax, raz);
  const [blx, blz] = local(b, rbx, rbz);

  // Blame: a rammer is never the victim of its own shove.
  if (!a.ramming || b.ramming) {
    a.lastHitBy = b;
    a.lastHitTime = time;
  }
  if (!b.ramming || a.ramming) {
    b.lastHitBy = a;
    b.lastHitTime = time;
  }
  a.lastContactTime = b.lastContactTime = time;
  a.addDamage(a.zoneAt(alx, alz), toA, alx, alz, b, time, events);
  b.addDamage(b.zoneAt(blx, blz), toB, blx, blz, a, time, events);

  const strength = -vn;
  if (strength > 6) {
    if (!a.ramming) a.stun = Math.max(a.stun, tuning.stunTime * Math.min(1, toA / 12));
    if (!b.ramming) b.stun = Math.max(b.stun, tuning.stunTime * Math.min(1, toB / 12));
  }
  if (strength > 1.5) {
    events.emit('impact', { x: px, y: (a.y + b.y) / 2 + 0.6, z: pz, strength, kind: 'car', a, b });
  }
  return true;
}
