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

// Last contact time per pair, so a long grinding contact doesn't count as many separate crashes.
const lastPairContact = new WeakMap<Vehicle, Map<Vehicle, number>>();

function pairSince(a: Vehicle, b: Vehicle, time: number): number {
  let m = lastPairContact.get(a);
  if (!m) lastPairContact.set(a, (m = new Map()));
  let m2 = lastPairContact.get(b);
  if (!m2) lastPairContact.set(b, (m2 = new Map()));
  const prev = Math.max(m.get(b) ?? -99, m2.get(a) ?? -99);
  m.set(b, time);
  m2.set(a, time);
  return time - prev;
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

  // Both ramming each other at once: a clash. Both bounce off, little damage.
  if (a.ramTimer > 0 && b.ramTimer > 0 && a.ramTarget === b && b.ramTarget === a) {
    a.x -= (nx * depth) / 2;
    a.z -= (nz * depth) / 2;
    b.x += (nx * depth) / 2;
    b.z += (nz * depth) / 2;
    for (const [v, sgn] of [[a, -1], [b, 1]] as const) {
      const along = v.vx * nx + v.vz * nz;
      v.vx += nx * (sgn * 4 - along);
      v.vz += nz * (sgn * 4 - along);
      v.ramLanded();
      v.lastContactTime = time;
    }
    pairSince(a, b, time);
    a.addDamage(a.zoneAt(...toLocal(a, px, pz)), 4, ...toLocal(a, px, pz), b, time, events);
    b.addDamage(b.zoneAt(...toLocal(b, px, pz)), 4, ...toLocal(b, px, pz), a, time, events);
    events.emit('impact', { x: px, y: (a.y + b.y) / 2 + 0.6, z: pz, strength: 12, kind: 'car', a, b });
    return true;
  }

  // A targeted ram that lands is a scripted arcade shove, not a physics bounce.
  const landA = a.ramTimer > 0 && a.ramTarget === b && !(b.ramTimer > 0 && b.ramTarget === a);
  const landB = b.ramTimer > 0 && b.ramTarget === a && !(a.ramTimer > 0 && a.ramTarget === b);
  if (landA || landB) {
    const [r, v] = landA ? [a, b] : [b, a];
    const sign = landA ? 1 : -1; // n points from a to b
    v.x += nx * depth * sign;
    v.z += nz * depth * sign;
    landRam(r, v, px, pz, time, events);
    return true;
  }

  // Who is the aggressor? Compare how fast each car moves into the other, measured
  // relative to the slower car's pace along the road (so a rear-end shunt blames the
  // faster car and a side swipe blames the one that steered in).
  const wa = aggressorShare(a, b, nx, nz, time);
  const wb = 1 - wa;

  // Positional correction: mostly the victim gets pushed out.
  const pa = 1 - wa;
  const pb = 1 - wb;
  const pt = pa + pb || 1;
  a.x -= nx * depth * (pa / pt);
  a.z -= nz * depth * (pa / pt);
  b.x += nx * depth * (pb / pt);
  b.z += nz * depth * (pb / pt);

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
  // Arcade: the aggressor feels only part of the recoil (and a rammer none of the spin),
  // so shoving someone doesn't throw you into the opposite rail.
  const recoilA = a.ramming ? 0.15 : 1 - tuning.aggressorRecoil * wa;
  const recoilB = b.ramming ? 0.15 : 1 - tuning.aggressorRecoil * wb;
  // Rammed cars slide sideways rather than spinning back into the rammer.
  const spinA = a.ramming ? 0 : b.ramming ? 0.5 : recoilA;
  const spinB = b.ramming ? 0 : a.ramming ? 0.5 : recoilB;
  a.vx -= (jx / ma) * recoilA;
  a.vz -= (jz / ma) * recoilA;
  a.angVel -= ((raz * jx - rax * jz) / ia) * spinA;
  b.vx += (jx / mb) * recoilB;
  b.vz += (jz / mb) * recoilB;
  b.angVel += ((rbz * jx - rbx * jz) / ib) * spinB;

  if (a.ramming) a.ramLanded();
  if (b.ramming) b.ramLanded();

  // Damage: the aggressor takes a fraction, the victim takes more. Rams hit extra hard.
  // Contacts within a fraction of a second of the previous one are part of the same crash.
  const repeat = pairSince(a, b, time) < 0.25 ? 0.25 : 1;
  const base = j * tuning.damagePerImpulse * repeat;
  const toA = base * (1.25 - 0.9 * wa) * (b.ramming ? tuning.ramDamageFactor : 1) * (a.ramming ? 0.6 : 1);
  const toB = base * (1.25 - 0.9 * wb) * (a.ramming ? tuning.ramDamageFactor : 1) * (b.ramming ? 0.6 : 1);
  const local = (v: Vehicle, wx: number, wz: number): [number, number] => {
    const fx = Math.sin(v.heading);
    const fz = Math.cos(v.heading);
    return [wx * -fz + wz * fx, wx * fx + wz * fz];
  };
  const [alx, alz] = local(a, rax, raz);
  const [blx, blz] = local(b, rbx, rbz);

  // Blame: the aggressor is never the victim of its own shove.
  if (wa < 0.7) {
    a.lastHitBy = b;
    a.lastHitTime = time;
  }
  if (wb < 0.7) {
    b.lastHitBy = a;
    b.lastHitTime = time;
  }
  a.lastContactTime = b.lastContactTime = time;
  a.addDamage(a.zoneAt(alx, alz), toA, alx, alz, b, time, events);
  b.addDamage(b.zoneAt(blx, blz), toB, blx, blz, a, time, events);

  const strength = -vn;
  if (strength > 6) {
    if (wa < 0.7) a.stun = Math.max(a.stun, tuning.stunTime * Math.min(1, toA / 12));
    if (wb < 0.7) b.stun = Math.max(b.stun, tuning.stunTime * Math.min(1, toB / 12));
  }
  if (strength > 1.5) {
    events.emit('impact', { x: px, y: (a.y + b.y) / 2 + 0.6, z: pz, strength, kind: 'car', a, b });
  }
  return true;
}

/** Share (0..1) of the closing speed that car a is responsible for. */
function aggressorShare(a: Vehicle, b: Vehicle, nx: number, nz: number, time: number): number {
  if (a.ramming && !b.ramming) return 1;
  if (b.ramming && !a.ramming) return 0;
  // Follow-up contacts after a shove (the victim bouncing back off the rail) stay in the
  // shover's favour, so you don't get punished for your own successful hit.
  const aHitB = b.lastHitBy === a && time - b.lastHitTime < 1.5;
  const bHitA = a.lastHitBy === b && time - a.lastHitTime < 1.5;
  if (aHitB && !bHitA) return 0.9;
  if (bHitA && !aHitB) return 0.1;
  // Running into someone else's wreck hurts you too.
  if (a.wrecked !== b.wrecked) return 0.5;
  // Road direction ≈ average heading of both cars.
  let tx = Math.sin(a.heading) + Math.sin(b.heading);
  let tz = Math.cos(a.heading) + Math.cos(b.heading);
  const tl = Math.hypot(tx, tz) || 1;
  tx /= tl;
  tz /= tl;
  const pace = Math.min(a.vx * tx + a.vz * tz, b.vx * tx + b.vz * tz);
  const refx = tx * pace;
  const refz = tz * pace;
  const intoB = Math.max(0, (a.vx - refx) * nx + (a.vz - refz) * nz);
  const intoA = Math.max(0, -((b.vx - refx) * nx + (b.vz - refz) * nz));
  const total = intoA + intoB;
  return total < 0.5 ? 0.5 : intoB / total;
}

function landRam(r: Vehicle, v: Vehicle, px: number, pz: number, time: number, events: EventBus): void {
  // Shove direction: sideways from the rammer's point of view.
  const fx = Math.sin(r.heading);
  const fz = Math.cos(r.heading);
  const sx = -fz * r.ramDir;
  const sz = fx * r.ramDir;

  // Victim: launched sideways and briefly loses grip.
  const vAlong = v.vx * sx + v.vz * sz;
  v.vx += sx * (tuning.ramShoveSpeed - vAlong);
  v.vz += sz * (tuning.ramShoveSpeed - vAlong);
  v.angVel += (Math.random() - 0.5) * 1.2;
  v.stun = Math.max(v.stun, tuning.stunTime);
  v.lastHitBy = r;
  v.lastHitTime = time;

  // Rammer: stops its sideways lunge at the contact point and keeps its line.
  const rAlong = r.vx * sx + r.vz * sz;
  r.vx -= sx * rAlong * 0.85;
  r.vz -= sz * rAlong * 0.85;
  r.angVel *= 0.3;
  r.ramLanded();
  r.lastContactTime = v.lastContactTime = time;
  pairSince(r, v, time);

  const [vlx, vlz] = toLocal(v, px, pz);
  const [rlx, rlz] = toLocal(r, px, pz);
  v.addDamage(v.zoneAt(vlx, vlz), tuning.ramDamage, vlx, vlz, r, time, events);
  r.addDamage(r.zoneAt(rlx, rlz), 1.5, rlx, rlz, null, time, events);
  events.emit('impact', { x: px, y: (r.y + v.y) / 2 + 0.6, z: pz, strength: 14, kind: 'car', a: r, b: v });
}

/** World point → car-local (right, forward) offset. */
function toLocal(c: Vehicle, px: number, pz: number): [number, number] {
  const cx = Math.sin(c.heading);
  const cz = Math.cos(c.heading);
  const wx = px - c.x;
  const wz = pz - c.z;
  return [wx * -cz + wz * cx, wx * cx + wz * cz];
}
