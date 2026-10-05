import { tuning, ROAD, type CarSpec } from '../config';
import type { EventBus } from '../core/Events';
import type { Projection, Track, TrackFrame } from '../track/Track';

export type Zone = 'front' | 'rear' | 'left' | 'right';

export interface VehicleInput {
  throttle: number;
  brake: number;
  steer: number; // -1 left .. +1 right
  handbrake: boolean;
  nitro: boolean;
  ramLeft: boolean; // edge-triggered, consumed by the vehicle
  ramRight: boolean;
}

export const emptyInput = (): VehicleInput => ({
  throttle: 0, brake: 0, steer: 0, handbrake: false, nitro: false, ramLeft: false, ramRight: false,
});

const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));

/**
 * Semi-arcade 2D rigid body on the XZ plane (NFS2SE feel): engine force along the heading,
 * yaw rate steered towards a target, and lateral velocity bled off by "grip".
 * Height and pitch come from the track.
 */
export class Vehicle {
  readonly spec: CarSpec;
  readonly isPlayer: boolean;
  readonly halfL: number;
  readonly halfW: number;
  readonly mass: number;
  readonly inertia: number;

  x = 0;
  y = 0;
  z = 0;
  heading = 0;
  vx = 0;
  vz = 0;
  angVel = 0;
  pitch = 0;

  input: VehicleInput = emptyInput();
  damage: Record<Zone, number> = { front: 0, rear: 0, left: 0, right: 0 };
  nitro = 0.35;
  nitroActive = false;
  ramTimer = 0;
  /** Short window after a ram lands during which we still count as the rammer. */
  ramHitTimer = 0;
  ramCooldown = 0;
  ramDir = 0;
  /** Car we're shoving into (null = short dodge without target). */
  ramTarget: Vehicle | null = null;
  private wasRamming = false;
  /** Longitudinal acceleration of the last step, used for visual body pitch. */
  accelLong = 0;
  stun = 0;
  wrecked = false;
  wreckTime = 0;
  frozen = true;
  drifting = false;
  scraping = 0;
  braking = false;
  lastHitBy: Vehicle | null = null;
  lastHitTime = -99;
  lastContactTime = -99;
  powerFactor = 1;
  finished = false;
  finishTime = 0;
  takedowns = 0;

  readonly proj: Projection = { idx: -1, s: 0, d: 0 };
  /** Called whenever damage is dealt: (amount, zone, point in local space x/z). */
  onDamage: ((amount: number, zone: Zone, lx: number, lz: number) => void) | null = null;

  private fr = {} as TrackFrame;

  constructor(spec: CarSpec, isPlayer: boolean) {
    this.spec = spec;
    this.isPlayer = isPlayer;
    this.halfL = spec.length / 2;
    this.halfW = spec.width / 2;
    this.mass = spec.mass;
    this.inertia = (this.mass * (spec.length ** 2 + spec.width ** 2)) / 12;
  }

  get s(): number {
    return this.proj.s;
  }
  get d(): number {
    return this.proj.d;
  }
  get speed(): number {
    return Math.hypot(this.vx, this.vz);
  }
  get forwardSpeed(): number {
    return this.vx * Math.sin(this.heading) + this.vz * Math.cos(this.heading);
  }
  get totalDamage(): number {
    const d = this.damage;
    return (d.front + d.rear + d.left + d.right) / 4;
  }

  /** 0..100: how close the car is to total loss (worst zone or overall wear). */
  get wreckLevel(): number {
    const d = this.damage;
    return Math.min(100, Math.max(d.front, d.rear, d.left, d.right, (this.totalDamage / tuning.wreckTotal) * 100));
  }

  place(track: Track, s: number, d: number, speed = 0): void {
    const fr = track.frame(s, this.fr);
    this.x = fr.x + fr.rx * d;
    this.z = fr.z + fr.rz * d;
    this.y = fr.y;
    this.heading = fr.heading;
    this.vx = fr.fx * speed;
    this.vz = fr.fz * speed;
    this.angVel = 0;
    this.proj.idx = -1;
    track.project(this.x, this.z, -1, this.proj);
  }

  repair(level: number): void {
    for (const z of Object.keys(this.damage) as Zone[]) this.damage[z] = Math.min(this.damage[z], level);
    this.wrecked = false;
    this.stun = 0;
  }

  addDamage(zone: Zone, amount: number, lx: number, lz: number, attacker: Vehicle | null, time: number, events: EventBus): void {
    if (this.wrecked || amount <= 0) return;
    const factor = this.isPlayer ? tuning.playerDamageFactor : tuning.aiDamageFactor;
    const dmg = amount * factor;
    this.damage[zone] = Math.min(100, this.damage[zone] + dmg);
    this.onDamage?.(dmg, zone, lx, lz);

    // Whoever recently hit us gets the credit (and nitro) for this damage.
    const credit = attacker ?? (time - this.lastHitTime < tuning.takedownWindow ? this.lastHitBy : null);
    if (credit && credit !== this) credit.nitro = Math.min(1, credit.nitro + dmg * tuning.nitroFillPerDamage);

    if (this.wreckLevel >= 100) {
      this.wrecked = true;
      this.wreckTime = time;
      this.nitroActive = false;
      this.angVel += (Math.random() - 0.5) * 4;
      if (credit && credit !== this) {
        credit.takedowns++;
        credit.nitro = Math.min(1, credit.nitro + tuning.nitroFillTakedown);
      }
      events.emit('wreck', { victim: this, attacker: credit && credit !== this ? credit : null });
    }
  }

  /** Map a local contact point (lx right, lz forward) to a damage zone. */
  zoneAt(lx: number, lz: number): Zone {
    if (Math.abs(lz) / this.halfL > Math.abs(lx) / this.halfW) return lz > 0 ? 'front' : 'rear';
    return lx > 0 ? 'right' : 'left';
  }

  update(dt: number, time: number, track: Track, events: EventBus, others: Vehicle[] = []): void {
    const inp = this.input;
    const active = !this.wrecked && !this.frozen;
    const dmg = this.damage;
    const front = dmg.front / 100;
    const rear = dmg.rear / 100;

    let fx = Math.sin(this.heading);
    let fz = Math.cos(this.heading);
    let vF = this.vx * fx + this.vz * fz;
    let vL = this.vx * -fz + this.vz * fx;
    const speed = Math.hypot(vF, vL);

    this.stun = Math.max(0, this.stun - dt);
    this.ramCooldown = Math.max(0, this.ramCooldown - dt);
    this.ramTimer = Math.max(0, this.ramTimer - dt);
    this.ramHitTimer = Math.max(0, this.ramHitTimer - dt);

    // --- Nitro ---
    this.nitroActive = active && inp.nitro && this.nitro > 0.01 && vF > 3;
    if (this.nitroActive) this.nitro = Math.max(0, this.nitro - tuning.nitroDrain * dt);

    // --- Longitudinal ---
    const top = this.spec.topSpeed * (1 - 0.3 * front) * (this.nitroActive ? tuning.nitroTopSpeedFactor : 1) * this.powerFactor;
    const accel = tuning.engineAccel * this.spec.accelFactor * (1 - 0.35 * front) * this.powerFactor;
    let aF = 0;
    this.braking = false;
    if (active) {
      if (inp.throttle > 0 && vF < top) aF += accel * inp.throttle * Math.max(0.08, 1 - (vF / top) ** 2);
      if (inp.brake > 0) {
        if (vF > 1) {
          aF -= tuning.brakeDecel * inp.brake;
          this.braking = true;
        } else if (vF > -14) aF -= accel * 0.5 * inp.brake; // reverse
      }
      if (this.nitroActive) aF += tuning.nitroAccel * Math.max(0, 1 - vF / top);
      if (inp.handbrake) aF -= 3 * Math.sign(vF);
    } else if (this.wrecked) {
      aF -= 7 * Math.sign(vF);
    } else if (this.frozen) {
      aF -= tuning.brakeDecel * Math.sign(vF);
    }
    aF -= tuning.rollingDecel * Math.sign(vF) + tuning.dragCoef * vF * Math.abs(vF);
    this.accelLong = aF;
    const newVF = vF + aF * dt;
    vF = Math.sign(newVF) !== Math.sign(vF) && Math.abs(vF) < 1 && !(active && (inp.throttle > 0 || inp.brake > 0)) ? 0 : newVF;

    // --- Steering / yaw ---
    const sideDmg = Math.max(dmg.left, dmg.right) / 100;
    const speedT = clamp(speed / 70, 0, 1);
    let maxYaw = (tuning.steerRateLow + (tuning.steerRateHigh - tuning.steerRateLow) * speedT) * (1 - 0.25 * sideDmg);
    maxYaw *= clamp(speed / 7, 0, 1); // no turning on the spot
    let steer = active ? inp.steer : 0;
    if (active) steer = clamp(steer + ((dmg.right - dmg.left) / 100) * 0.2, -1, 1);
    if (active && inp.handbrake) maxYaw *= tuning.handbrakeYawBoost;
    const targetYaw = -steer * maxYaw * (vF >= 0 ? 1 : -1);
    let response = tuning.yawResponse;
    if (this.stun > 0) response = 1.2;
    if (this.wrecked) response = 0.6;
    this.angVel += (targetYaw - this.angVel) * Math.min(1, response * dt);
    this.heading += this.angVel * dt;

    // Re-express velocity in the rotated frame, then bleed lateral velocity (grip).
    const wx = fx * vF - fz * vL;
    const wz = fz * vF + fx * vL;
    fx = Math.sin(this.heading);
    fz = Math.cos(this.heading);
    vF = wx * fx + wz * fz;
    vL = wx * -fz + wz * fx;

    let grip = tuning.grip * this.spec.gripFactor * (1 - 0.45 * rear);
    if (active && inp.handbrake) grip = tuning.handbrakeGrip;
    else if (Math.abs(vL) > 3.5) grip *= tuning.driftGripFactor;
    if (this.stun > 0) grip *= 0.35;
    if (this.wrecked) grip = 1.5;
    const vLBefore = vL;
    vL *= Math.exp(-grip * dt);
    // Arcade: part of the lost slide becomes forward speed so drifts don't kill momentum.
    if (active && vF > 5) vF += Math.abs(vLBefore - vL) * 0.25;

    // --- Ram attack: a sideways shove that locks on to a car beside you ---
    if (active && this.ramCooldown <= 0 && (inp.ramLeft || inp.ramRight)) {
      this.ramDir = inp.ramRight ? 1 : -1;
      this.ramTarget = this.findRamTarget(others);
      if (this.ramTarget) {
        this.ramTimer = tuning.ramDuration;
        this.ramCooldown = tuning.ramCooldown;
      } else {
        // Nobody there: just a small feint, so you don't throw yourself into the rail.
        this.ramTimer = 0.14;
        this.ramCooldown = 0.6;
      }
      events.emit('ram', { vehicle: this, dir: this.ramDir });
    }
    inp.ramLeft = inp.ramRight = false;
    // Never shove ourselves into the rail.
    if (this.ramTimer > 0 && this.ramDir * this.proj.d > ROAD.halfWidth - this.halfW - 0.5) this.ramTimer = 0;
    if (this.ramTimer > 0) {
      const target = this.ramTarget;
      const sideSpeed = target ? tuning.ramSideSpeed : 4;
      vL += (this.ramDir * sideSpeed - vL) * Math.min(1, 45 * dt);
      if (target) {
        // Match the target's position along the road so the hit lands door-to-door.
        const ds = target.proj.s - this.proj.s;
        vF += clamp(target.forwardSpeed + ds * 2 - vF, -8, 8) * Math.min(1, 5 * dt);
      }
      this.angVel *= Math.exp(-12 * dt); // stay straight while shoving
      this.wasRamming = true;
    } else if (this.wasRamming) {
      // Snap back after the shove so the rammer doesn't follow the victim into the rail.
      this.wasRamming = false;
      this.ramTarget = null;
      vL *= 0.2;
      this.angVel *= 0.3;
    }

    this.drifting = active && speed > 15 && Math.abs(vL) > 4;
    if (this.drifting) this.nitro = Math.min(1, this.nitro + tuning.nitroFillDriftPerSec * dt);

    this.vx = fx * vF - fz * vL;
    this.vz = fz * vF + fx * vL;
    this.x += this.vx * dt;
    this.z += this.vz * dt;

    // --- Track ---
    track.project(this.x, this.z, this.proj.idx, this.proj);
    this.collideRails(track, dt, time, events);
    const fr = track.frame(this.proj.s, this.fr);
    this.y = fr.y;
    const along = Math.cos(this.heading - fr.heading);
    this.pitch = -Math.atan(fr.slope * along);
  }

  get ramming(): boolean {
    return this.ramTimer > 0 || this.ramHitTimer > 0;
  }

  private findRamTarget(others: Vehicle[]): Vehicle | null {
    let best: Vehicle | null = null;
    let bestScore = Infinity;
    for (const o of others) {
      if (o === this || o.wrecked) continue;
      const ds = o.proj.s - this.proj.s;
      const side = (o.proj.d - this.proj.d) * this.ramDir;
      if (Math.abs(ds) > 6 || side < 0.8 || side > 6) continue;
      const score = Math.abs(ds) + side;
      if (score < bestScore) {
        bestScore = score;
        best = o;
      }
    }
    return best;
  }

  /** The shove landed: end it a moment later so the impact transfers but we don't keep pushing. */
  ramLanded(): void {
    if (this.ramTimer > 0) this.ramHitTimer = 0.15;
    this.ramTimer = 0; // stop pushing immediately, the impact already transferred
  }

  private collideRails(track: Track, dt: number, time: number, events: EventBus): void {
    const fr = track.frame(this.proj.s, this.fr);
    const fx = Math.sin(this.heading);
    const fz = Math.cos(this.heading);
    const rx = -fz;
    const rz = fx;
    const limit = ROAD.halfWidth;
    let scrape = 0;

    for (const side of [1, -1]) {
      // Find the corner deepest past this side's rail.
      let best = -Infinity;
      let cx = 0;
      let cz = 0;
      for (const a of [1, -1]) {
        for (const b of [1, -1]) {
          const ox = fx * this.halfL * a + rx * this.halfW * b;
          const oz = fz * this.halfL * a + rz * this.halfW * b;
          const cd = this.proj.d + ox * fr.rx + oz * fr.rz;
          const depth = side * cd - limit;
          if (depth > best) {
            best = depth;
            cx = ox;
            cz = oz;
          }
        }
      }
      if (best <= 0) continue;

      // Normal points from the rail back into the road.
      const nx = -side * fr.rx;
      const nz = -side * fr.rz;
      this.x += nx * best;
      this.z += nz * best;
      this.proj.d -= side * best;

      const vcx = this.vx + this.angVel * cz;
      const vcz = this.vz - this.angVel * cx;
      const vn = vcx * nx + vcz * nz;
      const tx = fr.fx;
      const tz = fr.fz;
      const vt = this.vx * tx + this.vz * tz;
      const speed = Math.abs(vt);
      const lx = cx * rx + cz * rz;
      const lz = cx * fx + cz * fz;
      const zone = this.zoneAt(lx, lz);
      const recentlyHit = time - this.lastHitTime < tuning.takedownWindow && this.lastHitBy !== null;

      if (vn < 0) {
        const crn = cz * nx - cx * nz;
        const j = (-(1 + tuning.railRestitution) * vn) / (1 / this.mass + (crn * crn) / this.inertia);
        this.vx += (j * nx) / this.mass;
        this.vz += (j * nz) / this.mass;
        this.angVel += (cz * j * nx - cx * j * nz) / this.inertia;
        // Lose some speed along the rail.
        const loss = Math.min(speed, tuning.railFriction * -vn * 1.2) * Math.sign(vt);
        this.vx -= tx * loss;
        this.vz -= tz * loss;

        const impact = -vn;
        const threshold = this.isPlayer ? 3.5 : 2;
        if (impact > threshold) {
          const bonus = recentlyHit ? tuning.takedownRailBonus : 1;
          this.addDamage(zone, (impact - threshold) * tuning.railDamagePerSpeed * bonus, lx, lz, null, time, events);
          if (impact > 5) this.stun = Math.max(this.stun, tuning.stunTime * 0.6);
          events.emit('impact', {
            x: this.x + cx, y: this.y + 0.5, z: this.z + cz, strength: impact, kind: 'rail', a: this,
          });
        }
      }
      // Glide: turn the nose parallel to the rail instead of bouncing back into it.
      if (!this.wrecked) {
        let err = this.heading - fr.heading;
        err = Math.atan2(Math.sin(err), Math.cos(err));
        if (-side * err > 0 && Math.abs(err) < 1.2 && vt > 5) {
          this.heading -= err * Math.min(1, tuning.railGlide * dt);
          this.angVel *= Math.exp(-8 * dt);
        }
      }
      // Continuous scraping: damage, speed loss and sparks.
      if (speed > 4) {
        const bonus = recentlyHit ? tuning.takedownRailBonus : 1;
        this.addDamage(zone, speed * tuning.railScrapeDamage * dt * bonus, lx, lz, null, time, events);
        const drag = Math.min(speed, 3.5 * dt) * Math.sign(vt);
        this.vx -= tx * drag;
        this.vz -= tz * drag;
        scrape = Math.max(scrape, Math.min(1, speed / 40));
        events.emit('scrape', {
          x: this.x + cx, y: this.y + 0.45, z: this.z + cz, intensity: scrape, vehicle: this, nx, nz,
        });
      }
      this.lastContactTime = time;
    }
    this.scraping = scrape;

    // End walls at the start and finish of the stretch.
    if (this.proj.s <= 0.5 || this.proj.s >= track.length - 0.5) {
      const dir = this.proj.s <= 0.5 ? 1 : -1;
      const vt = this.vx * fr.fx + this.vz * fr.fz;
      if (vt * dir < 0) {
        this.vx -= fr.fx * vt * 1.3;
        this.vz -= fr.fz * vt * 1.3;
      }
    }
  }
}
