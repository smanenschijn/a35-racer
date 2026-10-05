import * as THREE from 'three';
import { ROAD, TRAFFIC, TRAFFIC_COLORS, TRUCK_COMPANIES, tuning, type CarSpec } from '../config';
import type { Track } from '../track/Track';
import { CarModel } from '../vehicle/CarModel';
import type { Vehicle } from '../vehicle/Vehicle';

const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));
const wrap = (a: number) => Math.atan2(Math.sin(a), Math.cos(a));
const pick = <T>(arr: T[]) => arr[Math.floor(Math.random() * arr.length)];

function randomTemplate() {
  const total = TRAFFIC.reduce((a, t) => a + t.weight, 0);
  let r = Math.random() * total;
  for (const t of TRAFFIC) {
    r -= t.weight;
    if (r <= 0) return t;
  }
  return TRAFFIC[0];
}

function randomSpec(template: CarSpec): CarSpec {
  const spec = { ...template };
  if (spec.kind === 'truck') {
    spec.color = pick([0x2255aa, 0xaa2222, 0xeeeeee, 0x226633, 0xf0b400]);
    spec.trailerText = pick(TRUCK_COMPANIES);
  } else if (spec.kind === 'van') {
    spec.color = pick([0xf2f2f2, 0xf2f2f2, 0xdddddd, 0x1f3f7a, 0x333333]);
  } else {
    spec.color = pick(TRAFFIC_COLORS);
  }
  return spec;
}

/** Plain motorway driving: keep lane, keep distance, keep right, overtake when it's free. */
class TrafficDriver {
  readonly vehicle: Vehicle;
  lane: number;
  desired: number;
  readonly rightOnly: boolean;
  private laneTimer = 2 + Math.random() * 4;
  stuck = 0;

  constructor(vehicle: Vehicle, rightOnly: boolean, desired: number, lane: number) {
    this.vehicle = vehicle;
    this.rightOnly = rightOnly;
    this.desired = desired;
    this.lane = lane;
  }

  update(dt: number, track: Track, others: Vehicle[]): void {
    const v = this.vehicle;
    const inp = v.input;
    if (v.wrecked) return;
    const speed = v.forwardSpeed;
    this.laneTimer -= dt;

    // Nearest vehicle ahead in our lane.
    let ahead: Vehicle | null = null;
    let gap = Infinity;
    // Mirror check: also look further back for anything coming up fast (racers at 200+ km/h).
    const laneFree = (lane: number, back: number, front: number) =>
      !others.some((o) => {
        if (o === v || !o.active || Math.abs(o.d - lane) > o.halfW + v.halfW + 0.4) return false;
        const ds = o.s - v.s;
        const reach = back + Math.max(0, o.forwardSpeed - speed) * 3;
        return ds > -reach && ds < front;
      });
    for (const o of others) {
      if (o === v || !o.active) continue;
      const ds = o.s - v.s;
      if (ds <= 0 || ds > 90) continue;
      if (Math.abs(o.d - this.lane) > o.halfW + v.halfW + 0.3) continue;
      const g = ds - o.halfL - v.halfL;
      if (g < gap) {
        gap = g;
        ahead = o;
      }
    }

    // Lane changes: overtake a slower vehicle, drive around obstacles, keep right afterwards.
    if (this.laneTimer <= 0) {
      const [left, right] = ROAD.laneCenters;
      const obstacle = ahead && (ahead.wrecked || ahead.speed < 3) && gap < 60;
      if (obstacle) {
        for (const lane of [left, right, ROAD.shoulder]) {
          if (Math.abs(lane - this.lane) > 1 && laneFree(lane, 15, 40)) {
            this.lane = lane;
            break;
          }
        }
        this.laneTimer = 2;
      } else if (!this.rightOnly && ahead && ahead.forwardSpeed < this.desired - 3 && gap < 50 && this.lane === right && laneFree(left, 25, 40)) {
        this.lane = left;
        this.laneTimer = 5;
      } else if (this.lane !== right && laneFree(right, 20, 45)) {
        this.lane = right;
        this.laneTimer = 4;
      } else {
        this.laneTimer = 1.5;
      }
    }

    // Steering: pure pursuit on our lane.
    const look = 10 + Math.max(0, speed) * 0.6;
    const target = track.pointAt(v.s + look, this.lane);
    const err = wrap(Math.atan2(target.x - v.x, target.z - v.z) - v.heading);
    inp.steer = clamp(-err * 2.4 + v.angVel * 0.2, -1, 1);

    // Speed: desired cruise, follow the car in front with a time gap.
    let wanted = this.desired;
    if (ahead && gap < 90) wanted = Math.min(wanted, Math.max(0, ahead.forwardSpeed + (gap - 8 - speed * 0.6) * 0.5));
    inp.throttle = speed < wanted - 0.5 ? 0.7 : 0;
    inp.brake = speed > wanted + 2 ? Math.min(1, (speed - wanted) / 8 + 0.2) : 0;
    inp.handbrake = false;
    inp.nitro = false;

    const facingBack = Math.abs(wrap(v.heading - track.frame(v.s).heading)) > 1.6;
    if ((speed < 2 && !(ahead && gap < 15)) || facingBack) this.stuck += dt;
    else this.stuck = 0;
  }
}

interface Oncoming {
  model: CarModel;
  s: number;
  lane: number;
  speed: number;
}

export interface TrafficDeps {
  scene: THREE.Scene;
  track: Track;
  create: (spec: CarSpec) => Vehicle;
  recolor: (v: Vehicle, hex: number) => void;
  repair: (v: Vehicle) => void;
}

/**
 * Same-direction traffic is fully simulated (you can shove it, wreck it, use it as a
 * weapon). Oncoming traffic on the other carriageway is decoration on rails.
 */
export class TrafficManager {
  readonly vehicles: Vehicle[] = [];
  private drivers: TrafficDriver[] = [];
  private oncoming: Oncoming[] = [];
  private d: TrafficDeps;

  constructor(deps: TrafficDeps) {
    this.d = deps;
    for (let i = 0; i < tuning.trafficCount; i++) {
      const tpl = randomTemplate();
      const v = deps.create(randomSpec(tpl.spec));
      this.vehicles.push(v);
      const lane = tpl.lane === 'right' ? ROAD.laneCenters[1] : pick(ROAD.laneCenters);
      this.drivers.push(new TrafficDriver(v, tpl.lane === 'right', 0, lane));
    }
    for (let i = 0; i < tuning.oncomingCount; i++) {
      const tpl = randomTemplate();
      const model = new CarModel(randomSpec(tpl.spec));
      deps.scene.add(model.root);
      this.oncoming.push({ model, s: 0, lane: pick(ROAD.oncomingLanes), speed: tpl.speed[0] });
    }
  }

  private speedFor(v: Vehicle): number {
    const tpl = TRAFFIC.find((t) => t.spec.id === v.spec.id) ?? TRAFFIC[0];
    return tpl.speed[0] + Math.random() * (tpl.speed[1] - tpl.speed[0]);
  }

  private spawn(i: number, s: number): boolean {
    const v = this.vehicles[i];
    const drv = this.drivers[i];
    const lane = drv.rightOnly || Math.random() < 0.6 ? ROAD.laneCenters[1] : ROAD.laneCenters[0];
    // Keep a safe distance from anyone already there.
    const clear = (ss: number) =>
      !this.vehicles.some((o, j) => j !== i && o.active && Math.abs(o.s - ss) < o.halfL + v.halfL + 18 && Math.abs(o.d - lane) < 2.5);
    let tries = 0;
    while (!clear(s) && tries < 8) {
      s += 30;
      tries++;
    }
    if (s > this.d.track.length - 80 || !clear(s)) return false;
    drv.desired = this.speedFor(v);
    drv.lane = lane;
    drv.stuck = 0;
    this.d.repair(v);
    if (v.spec.kind !== 'truck') this.d.recolor(v, v.spec.kind === 'van' ? pick([0xf2f2f2, 0xdddddd, 0x1f3f7a]) : pick(TRAFFIC_COLORS));
    v.place(this.d.track, s, lane, drv.desired);
    v.active = true;
    v.frozen = false;
    return true;
  }

  /** Spread traffic over the stretch, keeping the start area clear. */
  reset(startS: number): void {
    const t = this.d.track;
    const from = startS + 260;
    const span = t.length - 120 - from;
    this.vehicles.forEach((v, i) => {
      v.active = false;
      if (!this.spawn(i, from + (span * (i + Math.random() * 0.8)) / this.vehicles.length)) v.active = false;
    });
    for (const o of this.oncoming) {
      o.s = startS - 200 + Math.random() * 1400;
      o.speed = 25 + Math.random() * 9;
      o.lane = pick(ROAD.oncomingLanes);
    }
  }

  update(dt: number, all: Vehicle[], racers: Vehicle[], player: Vehicle): void {
    const t = this.d.track;
    const live = racers.filter((r) => !r.wrecked);
    const minS = Math.min(...live.map((r) => r.s), player.s);
    const maxS = Math.max(...live.map((r) => r.s), player.s);
    this.vehicles.forEach((v, i) => {
      if (!v.active) {
        // Re-enter ahead of the leading racer, out of sight.
        if (Math.random() < 0.02) this.spawn(i, maxS + 500 + Math.random() * 400);
        return;
      }
      const drv = this.drivers[i];
      drv.update(dt, t, all);
      const behindAll = v.s < minS - 150;
      const atEnd = v.s > t.length - 50;
      if (behindAll || atEnd || drv.stuck > 4) {
        v.active = false;
      }
    });
  }

  /** Oncoming carriageway: kinematic, recycled around the player. */
  renderOncoming(dt: number, playerS: number): void {
    const t = this.d.track;
    for (const o of this.oncoming) {
      o.s -= o.speed * dt;
      if (o.s < playerS - 180 || o.s < 5) {
        o.s = Math.min(t.length - 5, playerS + 700 + Math.random() * 700);
        o.speed = 25 + Math.random() * 9;
        o.lane = pick(ROAD.oncomingLanes);
      }
      const fr = t.frame(o.s);
      o.model.place(fr.x + fr.rx * o.lane, fr.y, fr.z + fr.rz * o.lane, fr.heading + Math.PI, o.speed, dt);
    }
  }
}
