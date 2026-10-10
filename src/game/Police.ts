import * as THREE from 'three';
import { ROAD, tuning } from '../config';
import type { EventBus } from '../core/Events';
import type { Track } from '../track/Track';
import type { Vehicle } from '../vehicle/Vehicle';

const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));
const wrap = (a: number) => Math.atan2(Math.sin(a), Math.cos(a));

type UnitState = 'parked' | 'chase' | 'leave';

interface Unit {
  v: Vehicle;
  state: UnitState;
  lane: number;
  laneTimer: number;
  attackTimer: number;
}

interface Roadblock {
  s: number;
  cars: Vehicle[];
}

export interface PoliceDeps {
  scene: THREE.Scene;
  track: Track;
  events: EventBus;
  create: () => Vehicle;
  repair: (v: Vehicle) => void;
}

/**
 * Wanted level ("heat", 0..5 stars) driven by the player's chaos, pursuing units that
 * try to box the player in, roadblocks from 3 stars, and speed cameras along the road.
 */
export class PoliceManager {
  heat = 0;
  private calm = 0;
  private units: Unit[] = [];
  private blockCars: Vehicle[] = [];
  private roadblock: Roadblock | null = null;
  private roadblockCooldown = 0;
  private bustTimer = 0;
  private spawnCooldown = 0;
  /** Shared between units: they take turns at a PIT instead of piling on. */
  private pitCooldown = 0;
  readonly cameras: { s: number; flash: THREE.MeshStandardMaterial; flashT: number }[] = [];
  private prevPlayerS = 0;
  private d: PoliceDeps;
  /** Distance to the nearest chasing unit with its siren on (for audio/HUD). */
  nearestSiren = Infinity;

  constructor(deps: PoliceDeps) {
    this.d = deps;
    for (let i = 0; i < 3; i++) {
      const v = deps.create();
      v.active = false;
      this.units.push({ v, state: 'parked', lane: ROAD.laneCenters[1], laneTimer: 0, attackTimer: 2 });
    }
    for (let i = 0; i < 3; i++) {
      const v = deps.create();
      v.active = false;
      this.blockCars.push(v);
    }
    this.buildCameras();
  }

  get stars(): number {
    return Math.min(5, Math.floor(this.heat + 1e-6));
  }

  get vehicles(): Vehicle[] {
    return [...this.units.map((u) => u.v), ...this.blockCars];
  }

  addHeat(amount: number): void {
    const before = this.stars;
    this.heat = clamp(this.heat + amount, 0, 5.99);
    this.calm = 0;
    if (this.stars > before) {
      this.d.events.emit('message', {
        text: before === 0 ? 'POLITIE!' : `${'★'.repeat(this.stars)}`,
        color: '#4f8bff',
        big: before === 0,
      });
    }
  }

  private buildCameras(): void {
    const t = this.d.track;
    const pole = new THREE.MeshStandardMaterial({ color: 0x8a8f96, metalness: 0.6, roughness: 0.4 });
    const housing = new THREE.MeshStandardMaterial({ color: 0x3a3f46, metalness: 0.4, roughness: 0.5 });
    for (let s = 480; s < t.length - 200; s += 760) {
      const flash = new THREE.MeshStandardMaterial({ color: 0x222222, emissive: 0xffffff, emissiveIntensity: 0 });
      const g = new THREE.Group();
      const p = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.14, 3.2, 8), pole);
      p.position.y = 1.6;
      const box = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.7, 0.6), housing);
      box.position.set(0, 3.3, 0);
      const lens = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.2, 0.05), flash);
      lens.position.set(0, 3.3, -0.32);
      g.add(p, box, lens);
      const fr = t.frame(s);
      g.position.set(fr.x + fr.rx * 7.4, fr.y, fr.z + fr.rz * 7.4);
      g.rotation.y = fr.heading;
      this.d.scene.add(g);
      this.cameras.push({ s, flash, flashT: 0 });
    }
  }

  reset(): void {
    this.heat = 0;
    this.calm = 0;
    this.bustTimer = 0;
    this.spawnCooldown = 0;
    this.pitCooldown = 0;
    this.roadblockCooldown = 10;
    for (const u of this.units) {
      u.state = 'parked';
      u.v.active = false;
      u.v.sirenOn = false;
    }
    this.clearRoadblock();
    this.prevPlayerS = 0;
  }

  private clearRoadblock(): void {
    for (const v of this.blockCars) {
      v.active = false;
      v.sirenOn = false;
    }
    this.roadblock = null;
  }

  private desiredUnits(): number {
    return [0, 1, 1, 2, 2, 3][this.stars];
  }

  /** The police wrecked the player: fewer stars, the chase is called off and no PITs for a while. */
  backOff(): void {
    this.heat = Math.max(0, this.heat - tuning.policeWreckHeatDrop);
    this.calm = 0;
    this.bustTimer = 0;
    this.pitCooldown = tuning.policeWreckGrace;
    this.spawnCooldown = Math.max(this.spawnCooldown, tuning.policeWreckGrace * 0.5);
    for (const u of this.units) if (u.state === 'chase') this.release(u);
  }

  update(dt: number, player: Vehicle, all: Vehicle[], racing: boolean, time: number): void {
    const t = this.d.track;
    this.pitCooldown -= dt;

    // --- Speed cameras ---
    const kmh = player.speed * 3.6;
    for (const cam of this.cameras) {
      cam.flashT = Math.max(0, cam.flashT - dt);
      cam.flash.emissiveIntensity = cam.flashT > 0 ? 12 * cam.flashT : 0;
      if (racing && this.prevPlayerS < cam.s && player.s >= cam.s && kmh > tuning.speedCameraKmh) {
        cam.flashT = 0.35;
        this.d.events.emit('flash', { kmh });
        this.addHeat(0.7);
      }
    }
    this.prevPlayerS = player.s;

    // --- Heat decay ---
    this.calm += dt;
    const chasersClose = this.units.some((u) => u.state === 'chase' && Math.abs(u.v.s - player.s) < 150);
    if (this.calm > tuning.heatDecayDelay) this.heat = Math.max(0, this.heat - tuning.heatDecay * (chasersClose ? 0.35 : 1) * dt);

    // --- Spawning pursuit units ---
    this.spawnCooldown -= dt;
    const chasing = this.units.filter((u) => u.state === 'chase').length;
    if (racing && chasing < this.desiredUnits() && this.spawnCooldown <= 0) {
      const u = this.units.find((x) => x.state === 'parked');
      if (u) this.spawnUnit(u, player, all);
      this.spawnCooldown = 4;
    }
    if (this.stars === 0) for (const u of this.units) if (u.state === 'chase') this.release(u);

    // --- Drive units ---
    this.nearestSiren = Infinity;
    for (const u of this.units) {
      const v = u.v;
      if (!v.active) continue;
      if (u.state === 'chase') this.chase(u, player, all, dt);
      else if (u.state === 'leave') this.cruise(u, dt);
      if (v.wrecked && Math.abs(v.s - player.s) > 120) this.park(u);
      if (u.state === 'leave' && Math.abs(v.s - player.s) > 300) this.park(u);
      if (v.sirenOn && !v.wrecked) this.nearestSiren = Math.min(this.nearestSiren, Math.hypot(v.x - player.x, v.z - player.z));
    }

    // --- Roadblocks ---
    this.roadblockCooldown -= dt;
    if (this.roadblock && player.s > this.roadblock.s + 150) this.clearRoadblock();
    if (racing && !this.roadblock && this.stars >= 3 && this.roadblockCooldown <= 0) {
      const s = player.s + 650;
      if (s < t.features.finishS - 80) this.placeRoadblock(s, all);
      this.roadblockCooldown = 25;
    }
    if (this.roadblock) {
      for (const v of this.roadblock.cars) if (v.active && !v.wrecked) this.nearestSiren = Math.min(this.nearestSiren, Math.hypot(v.x - player.x, v.z - player.z));
    }

    // --- Busted: pinned down by the police ---
    const pinned =
      racing && this.stars > 0 && player.speed < 5 && !player.wrecked &&
      this.vehicles.some((p) => p.active && !p.wrecked && Math.hypot(p.x - player.x, p.z - player.z) < 7.5);
    this.bustTimer = pinned ? this.bustTimer + dt : Math.max(0, this.bustTimer - dt * 2);
    if (this.bustTimer > tuning.bustSeconds) {
      const fine = this.stars * tuning.bustPenalty;
      player.penalty += fine;
      this.d.events.emit('busted', { penalty: fine });
      this.heat = Math.max(0, this.heat - 2.5);
      this.bustTimer = 0;
      for (const u of this.units) if (u.state === 'chase') this.release(u);
    }
    void time;
  }

  get bustProgress(): number {
    return Math.min(1, this.bustTimer / tuning.bustSeconds);
  }

  private spawnUnit(u: Unit, player: Vehicle, all: Vehicle[]): void {
    const t = this.d.track;
    // Come from behind, out of view; near the start, wait on the shoulder ahead instead.
    const behind = player.s > 260;
    let s = behind ? player.s - 220 : player.s + 400;
    const lane = behind ? ROAD.laneCenters[Math.floor(Math.random() * 2)] : ROAD.shoulder;
    const free = (ss: number) => !all.some((o) => o !== u.v && o.active && Math.abs(o.s - ss) < 12 && Math.abs(o.d - lane) < 2.5);
    for (let i = 0; i < 6 && !free(s); i++) s += behind ? -15 : 15;
    if (s < 10 || s > t.length - 50) return;
    this.d.repair(u.v);
    u.v.place(t, s, lane, behind ? Math.min(player.speed + 8, 70) : 0);
    u.v.active = true;
    u.v.frozen = false;
    u.v.sirenOn = true;
    u.state = 'chase';
    u.lane = lane;
    u.attackTimer = 2;
  }

  private release(u: Unit): void {
    u.state = 'leave';
    u.v.sirenOn = false;
  }

  private park(u: Unit): void {
    u.state = 'parked';
    u.v.active = false;
    u.v.sirenOn = false;
  }

  private steerTo(v: Vehicle, lane: number): void {
    const t = this.d.track;
    const speed = v.forwardSpeed;
    const target = t.pointAt(v.s + 9 + Math.max(0, speed) * 0.45, lane);
    const err = wrap(Math.atan2(target.x - v.x, target.z - v.z) - v.heading);
    v.input.steer = clamp(-err * 3.2 + v.angVel * 0.15, -1, 1);
  }

  private chase(u: Unit, player: Vehicle, all: Vehicle[], dt: number): void {
    const v = u.v;
    const inp = v.input;
    if (v.wrecked) return;
    u.laneTimer -= dt;
    u.attackTimer -= dt;
    const ds = player.s - v.s; // > 0: player ahead of us
    const speed = v.forwardSpeed;

    // Obstacles ahead in our lane.
    let gap = Infinity;
    let ahead: Vehicle | null = null;
    for (const o of all) {
      if (o === v || o === player || !o.active) continue;
      const g = o.s - v.s - o.halfL - v.halfL;
      if (g > 0 && g < 45 && Math.abs(o.d - u.lane) < o.halfW + v.halfW + 0.3 && g < gap) {
        gap = g;
        ahead = o;
      }
    }

    // Lane choice: pull up next to the player, or get in front to block (3+ stars).
    if (u.laneTimer <= 0) {
      const lanes = [...ROAD.laneCenters, ROAD.shoulder];
      const freeLane = (l: number) =>
        !all.some((o) => o !== v && o !== player && o.active && o.s - v.s > -6 && o.s - v.s < 35 && Math.abs(o.d - l) < o.halfW + v.halfW + 0.3);
      let wantLane: number;
      if (ds > 8 || this.stars >= 3) wantLane = lanes.reduce((a, b) => (Math.abs(b - player.d) < Math.abs(a - player.d) ? b : a));
      else wantLane = lanes.filter((l) => Math.abs(l - player.d) > 2).sort((a, b) => Math.abs(a - player.d) - Math.abs(b - player.d))[0];
      if (ahead && gap < 30) {
        const alt = lanes.filter((l) => Math.abs(l - u.lane) > 1.5 && freeLane(l));
        if (alt.length) wantLane = alt.sort((a, b) => Math.abs(a - player.d) - Math.abs(b - player.d))[0];
      }
      if (wantLane !== u.lane && (freeLane(wantLane) || Math.abs(ds) < 15)) u.lane = wantLane;
      u.laneTimer = 0.8;
    }
    let line = u.lane;
    if (Math.abs(ds) < 6) line = u.lane + (player.d - u.lane) * 0.3; // lean on the player
    this.steerTo(v, clamp(line, -ROAD.halfWidth + 1.2, ROAD.halfWidth - 1.2));

    // Speed: catch up hard, then match (or brake-check from the front at 3+ stars).
    let wanted: number;
    if (ds > 10) wanted = v.spec.topSpeed * (1 + 0.04 * this.stars);
    else if (ds > -6) wanted = player.forwardSpeed + ds * 0.6;
    else wanted = this.stars >= 3 ? Math.max(0, player.forwardSpeed - 6) : player.forwardSpeed - 10;
    if (ahead && gap < 25 && Math.abs(ahead.d - u.lane) < 2) wanted = Math.min(wanted, ahead.alongSpeed + (gap - 6) * 0.6);
    v.powerFactor = ds > 40 ? 1.15 : 1;
    inp.throttle = speed < wanted ? 1 : 0;
    inp.brake = speed > wanted + 3 ? Math.min(1, (speed - wanted) / 10 + 0.3) : 0;
    inp.nitro = false;
    inp.handbrake = false;

    // PIT: shove the player when alongside.
    const lateral = player.d - v.d;
    if (Math.abs(ds) < 4 && Math.abs(lateral) > 1.2 && Math.abs(lateral) < 4 && u.attackTimer <= 0 && this.pitCooldown <= 0 && v.ramCooldown <= 0 && !player.wrecked) {
      if (lateral > 0) inp.ramRight = true;
      else inp.ramLeft = true;
      u.attackTimer = 3.4 - this.stars * 0.2;
      this.pitCooldown = tuning.policePitInterval;
    }
  }

  private cruise(u: Unit, dt: number): void {
    const v = u.v;
    if (v.wrecked) return;
    this.steerTo(v, ROAD.laneCenters[1]);
    v.input.throttle = v.forwardSpeed < 24 ? 0.5 : 0;
    v.input.brake = v.forwardSpeed > 28 ? 0.4 : 0;
    void dt;
  }

  private placeRoadblock(s: number, all: Vehicle[]): void {
    const t = this.d.track;
    const slots = [ROAD.laneCenters[0], ROAD.laneCenters[1], ROAD.shoulder];
    const gapIndex = Math.floor(Math.random() * slots.length);
    const used = slots.filter((_, i) => i !== gapIndex);
    const cars: Vehicle[] = [];
    used.forEach((d, i) => {
      const v = this.blockCars[i];
      this.d.repair(v);
      v.place(t, s + (i % 2) * 3, d, 0);
      v.heading += (i % 2 ? 1 : -1) * 0.9; // parked diagonally across the lane
      v.active = true;
      v.frozen = true;
      v.sirenOn = true;
      cars.push(v);
    });
    // Traffic already standing in the block would be crushed: nudge it out of the way.
    for (const o of all) if (o.role === 'traffic' && o.active && Math.abs(o.s - s) < 12) o.active = false;
    this.roadblock = { s, cars };
    this.d.events.emit('message', { text: 'WEGBLOKKADE VERDEROP!', color: '#4f8bff' });
  }
}
