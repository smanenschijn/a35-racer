import * as THREE from 'three';
import { AI_PERSONALITIES, CARS, ROAD, tuning } from '../config';
import type { GameAudio } from '../core/Audio';
import type { EventBus } from '../core/Events';
import type { Controls } from '../core/Input';
import type { Effects } from '../fx/Particles';
import { collideVehicles } from '../physics/Collisions';
import type { Track } from '../track/Track';
import type { Hud, StandingRow } from '../ui/Hud';
import { AIDriver } from '../vehicle/AIDriver';
import { CarModel } from '../vehicle/CarModel';
import { Vehicle } from '../vehicle/Vehicle';
import type { ChaseCamera } from './ChaseCamera';

export type RaceState = 'title' | 'countdown' | 'racing' | 'finished';

const HIT_WORDS = ['BEUK!', 'KNAL!', 'PATS!', 'BAM!', 'KRAK!'];

interface Deps {
  scene: THREE.Scene;
  track: Track;
  events: EventBus;
  fx: Effects;
  hud: Hud;
  audio: GameAudio;
  cam: ChaseCamera;
  rumble: (strong: number, weak: number, ms: number) => void;
}

export class Race {
  readonly vehicles: Vehicle[] = [];
  readonly player: Vehicle;
  private ais: AIDriver[] = [];
  private models = new Map<Vehicle, CarModel>();
  state: RaceState = 'title';
  paused = false;
  private countdownT = 0;
  private countdownStep = 0;
  raceTime = 0;
  private finishOrder: Vehicle[] = [];
  private resultsShown = false;
  private finishedAt = 0;
  timeScale = 1;
  private slowMoT = 0;
  private respawnT = 0;
  private resetCooldown = 0;
  private prevDs = new Map<Vehicle, number>();
  private playerScrape = 0;
  private simTime = 0;
  private d: Deps;
  /** Testing aid: let an AI drive the player's car (?autopilot in the URL). */
  autopilot = new URLSearchParams(location.search).has('autopilot');
  private autoDriver: AIDriver;

  constructor(deps: Deps) {
    this.d = deps;
    // Grid order: Sanne & Henk-Jan in front, Gerrit and the player behind.
    this.player = this.addCar('rx', true);
    for (const id of ['supremo', 'golv', 'volvi']) {
      const v = this.addCar(id, false);
      this.ais.push(new AIDriver(v, AI_PERSONALITIES[id], 0));
    }
    this.autoDriver = new AIDriver(this.player, { skill: 0.9, aggression: 0.8, taunts: [] }, ROAD.laneCenters[1]);
    this.wireEvents();
    this.reset();
  }

  private addCar(id: string, isPlayer: boolean): Vehicle {
    const v = new Vehicle(CARS[id], isPlayer);
    const model = new CarModel(CARS[id]);
    this.d.scene.add(model.root);
    this.models.set(v, model);
    v.onDamage = (amount, zone, lx, lz) => {
      model.dent(amount, lx, lz);
      const part = model.zoneDamaged(zone, v.damage[zone]);
      if (part) {
        const p = this.localToWorld(v, lx, lz, 0.6);
        this.d.fx.debris(p.x, p.y, p.z, 14, v.vx, v.vz);
      }
    };
    this.vehicles.push(v);
    return v;
  }

  reset(): void {
    const t = this.d.track;
    const start = t.features.startS;
    // [vehicle index, row, lane]
    const grid: [number, number, number][] = [
      [1, 0, 0], [2, 0, 1], [3, 1, 0], [0, 1, 1],
    ];
    for (const [vi, row, lane] of grid) {
      const v = this.vehicles[vi];
      v.place(t, start - 10 - row * 11 - lane * 3, ROAD.laneCenters[lane], 0);
      v.repair(0);
      for (const z of ['front', 'rear', 'left', 'right'] as const) v.damage[z] = 0;
      v.nitro = 0.35;
      v.frozen = true;
      v.finished = false;
      v.takedowns = 0;
      v.lastHitBy = null;
      v.lastHitTime = -99;
      v.ramCooldown = 0;
      v.input.throttle = v.input.brake = v.input.steer = 0;
      this.models.get(v)!.repair();
    }
    this.ais.forEach((ai, i) => {
      const lanes = [ROAD.laneCenters[0], ROAD.laneCenters[1], ROAD.laneCenters[0]];
      ai.setLane(lanes[i]);
    });
    this.finishOrder = [];
    this.resultsShown = false;
    this.raceTime = 0;
    this.timeScale = 1;
    this.slowMoT = 0;
    this.respawnT = 0;
    this.prevDs.clear();
    this.paused = false;
    this.d.cam.snap();
    this.d.hud.hideOverlay();
    if (this.state !== 'title') this.startCountdown();
  }

  startCountdown(): void {
    this.state = 'countdown';
    this.countdownT = 0;
    this.countdownStep = -1;
    this.d.hud.hideOverlay();
    this.d.hud.setHelpVisible(true);
  }

  private wireEvents(): void {
    const { events, fx, hud, audio, cam } = this.d;

    events.on('impact', (e) => {
      const n = Math.min(60, Math.floor(e.strength * 2.5));
      fx.sparkBurst(e.x, e.y, e.z, n, (e.a.vx + (e.b?.vx ?? e.a.vx)) * 0.4, (e.a.vz + (e.b?.vz ?? e.a.vz)) * 0.4);
      if (e.strength > 10) fx.debris(e.x, e.y, e.z, 8, e.a.vx, e.a.vz);
      const involvesPlayer = e.a === this.player || e.b === this.player;
      const dist = Math.hypot(e.x - this.player.x, e.z - this.player.z);
      if (dist < 120) audio.crash(e.strength * (involvesPlayer ? 1 : Math.max(0.2, 1 - dist / 120)));
      if (involvesPlayer) {
        cam.addShake(Math.min(0.9, e.strength / 20));
        this.d.rumble(e.strength / 15, e.strength / 10, 180);
        if (e.kind === 'car' && e.strength > 9) {
          hud.message(HIT_WORDS[Math.floor(Math.random() * HIT_WORDS.length)], '#ffd400', false, 0.9);
        }
      }
    });

    events.on('scrape', (e) => {
      if (Math.random() < e.intensity * 0.9) {
        const v = e.vehicle;
        fx.sparkBurst(e.x, e.y, e.z, 2, v.vx * 0.7 + e.nx * 2, v.vz * 0.7 + e.nz * 2, 5);
      }
      if (e.vehicle === this.player) this.playerScrape = Math.max(this.playerScrape, e.intensity);
    });

    events.on('wreck', ({ victim, attacker }) => {
      const p = this.localToWorld(victim, 0, 0, 0.8);
      fx.sparkBurst(p.x, p.y, p.z, 80, victim.vx * 0.5, victim.vz * 0.5, 14);
      for (let i = 0; i < 30; i++) fx.flame(p.x, p.y + Math.random(), p.z);
      fx.debris(p.x, p.y, p.z, 30, victim.vx, victim.vz);
      audio.crash(25);
      if (victim === this.player) {
        hud.message('TOTAL LOSS!', '#ff2a2a', true, 2.2);
        this.slowMo(0.3, 1.2);
        this.respawnT = 2.6;
        cam.addShake(1);
        this.d.rumble(1, 1, 600);
      } else if (attacker === this.player) {
        hud.message('TAKEDOWN!', '#ffd400', true, 2);
        hud.message(`${victim.spec.driver} ligt eruit!`, '#ffffff', false, 2);
        this.slowMo(0.35, 1.1);
        cam.addShake(0.6);
        this.d.rumble(0.8, 1, 400);
      } else {
        hud.message(`${victim.spec.driver} is total loss`, '#ff9a3c', false, 1.6);
      }
    });

    events.on('ram', ({ vehicle }) => {
      if (vehicle === this.player) audio.whoosh();
    });

    events.on('nearMiss', ({ vehicle }) => {
      if (vehicle === this.player) {
        hud.message('RAKELINGS!', '#36c6ff', false, 0.9);
        vehicle.nitro = Math.min(1, vehicle.nitro + tuning.nitroFillNearMiss);
      }
    });
  }

  private slowMo(scale: number, seconds: number): void {
    this.timeScale = scale;
    this.slowMoT = seconds;
  }

  private localToWorld(v: Vehicle, lx: number, lz: number, up: number): THREE.Vector3 {
    const fx = Math.sin(v.heading);
    const fz = Math.cos(v.heading);
    return new THREE.Vector3(v.x + fx * lz - fz * lx, v.y + up, v.z + fz * lz + fx * lx);
  }

  /** Per-render-frame logic: input, state machine, real-time timers. */
  handleInput(c: Controls, realDt: number): void {
    const { hud, audio } = this.d;
    if (c.any) audio.start();

    if (this.state === 'title') {
      if (c.any) this.startCountdown();
      return;
    }
    if (c.restart) {
      this.reset();
      return;
    }
    if (c.pause && this.state !== 'finished') {
      this.paused = !this.paused;
      hud.showPause(this.paused);
    }
    if (this.paused) return;

    // Real-time slow-mo timer.
    if (this.slowMoT > 0) {
      this.slowMoT -= realDt;
      if (this.slowMoT <= 0) this.timeScale = 1;
    }

    const p = this.player;
    if (this.state === 'finished' || p.finished) {
      p.input.throttle = 0;
      p.input.brake = 0.4;
      p.input.steer = 0;
      p.input.nitro = false;
      p.input.handbrake = false;
    } else if (!this.autopilot) {
      p.input.throttle = c.throttle;
      p.input.brake = c.brake;
      p.input.steer = c.steer;
      p.input.handbrake = c.handbrake;
      p.input.nitro = c.nitro;
      if (c.ramLeft) p.input.ramLeft = true;
      if (c.ramRight) p.input.ramRight = true;
    }

    this.resetCooldown -= realDt;
    if (c.reset && this.state === 'racing' && !p.wrecked && this.resetCooldown <= 0) {
      this.respawn(p, false);
      this.resetCooldown = 2;
    }
  }

  private respawn(v: Vehicle, repair: boolean): void {
    const t = this.d.track;
    const lanes = ROAD.laneCenters;
    const lane = lanes.reduce((a, b) => (Math.abs(b - v.d) < Math.abs(a - v.d) ? b : a));
    // Find a spot not overlapping anyone.
    let s = v.s;
    for (let tries = 0; tries < 10; tries++) {
      if (!this.vehicles.some((o) => o !== v && Math.abs(o.s - s) < 7 && Math.abs(o.d - lane) < 2.5)) break;
      s += 8;
    }
    v.place(t, Math.min(s, t.length - 10), lane, repair ? 18 : 12);
    v.stun = 0;
    if (repair) {
      v.repair(20);
      this.models.get(v)!.repair();
      v.frozen = false;
    }
  }

  /** Fixed-timestep simulation. */
  step(dt: number): void {
    if (this.paused || this.state === 'title') return;
    this.simTime += dt;
    const t = this.d.track;
    const { hud, audio } = this.d;

    if (this.state === 'countdown') {
      this.countdownT += dt;
      const step = Math.floor(this.countdownT);
      if (step !== this.countdownStep) {
        this.countdownStep = step;
        if (step < 3) {
          hud.countdown(String(3 - step));
          audio.beep(false);
        } else {
          hud.countdown('GAS GEAVEN!', true);
          audio.beep(true);
          this.state = 'racing';
          for (const v of this.vehicles) v.frozen = false;
          setTimeout(() => hud.setHelpVisible(false), 8000);
        }
      }
    } else {
      this.raceTime += dt;
    }

    if (this.autopilot && !this.player.finished) {
      this.autoDriver.update(dt, t, this.vehicles, this.ais[0].vehicle);
      if (this.autoDriver.needsReset) {
        this.autoDriver.needsReset = false;
        this.respawn(this.player, false);
      }
    }
    for (const ai of this.ais) {
      ai.update(dt, t, this.vehicles, this.player);
      const v = ai.vehicle;
      if (v.finished) {
        v.input.throttle = 0;
        v.input.brake = 0.5;
      }
      if (ai.needsReset && !v.wrecked) {
        ai.needsReset = false;
        ai.resetLane();
        this.respawn(v, false);
      }
    }
    for (const v of this.vehicles) v.update(dt, this.simTime, t, this.d.events);
    for (let i = 0; i < this.vehicles.length; i++) {
      for (let j = i + 1; j < this.vehicles.length; j++) {
        collideVehicles(this.vehicles[i], this.vehicles[j], this.simTime, this.d.events);
      }
    }

    // Finish line
    const finishS = t.features.finishS;
    for (const v of this.vehicles) {
      if (!v.finished && !v.wrecked && v.s >= finishS && this.state === 'racing') {
        v.finished = true;
        v.finishTime = this.raceTime;
        this.finishOrder.push(v);
        if (v.isPlayer) {
          const pos = this.finishOrder.length;
          hud.message(pos === 1 ? 'WINNAAR!' : `${pos}e PLAATS`, pos <= 3 ? '#4dff6a' : '#ff9a3c', true, 2.5);
          this.finishedAt = this.raceTime;
          this.state = 'finished';
        }
      }
    }
    if (this.state === 'finished' && !this.resultsShown && this.raceTime - this.finishedAt > 2.5) {
      this.resultsShown = true;
      hud.showResults(this.standings(), this.finishOrder.indexOf(this.player) + 1);
    }

    // Player respawn after a total loss.
    if (this.player.wrecked && this.respawnT > 0) {
      this.respawnT -= dt / Math.max(this.timeScale, 0.01);
      if (this.respawnT <= 0) {
        this.respawn(this.player, true);
        hud.message('OPGELAPT!', '#4dff6a', false, 1.2);
      }
    }

    this.detectNearMisses();
  }

  private detectNearMisses(): void {
    const p = this.player;
    if (p.wrecked || this.state !== 'racing') return;
    for (const o of this.vehicles) {
      if (o === p) continue;
      const ds = o.s - p.s;
      const prev = this.prevDs.get(o);
      this.prevDs.set(o, ds);
      if (prev === undefined || o.wrecked) continue;
      if (Math.sign(prev) !== Math.sign(ds)) {
        const gap = Math.abs(o.d - p.d) - p.halfW - o.halfW;
        const rel = Math.abs(p.forwardSpeed - o.forwardSpeed);
        const recentContact = this.simTime - p.lastContactTime < 1 && p.lastHitBy === o;
        if (gap < 1.0 && gap > 0 && rel > 6 && !recentContact) this.d.events.emit('nearMiss', { vehicle: p, other: o });
      }
    }
  }

  ranking(): Vehicle[] {
    const finished = this.finishOrder;
    const running = this.vehicles.filter((v) => !v.finished && !v.wrecked).sort((a, b) => b.s - a.s);
    const out = this.vehicles.filter((v) => !v.finished && v.wrecked);
    return [...finished, ...running, ...out];
  }

  standings(): StandingRow[] {
    return this.ranking().map((v) => ({
      name: v.spec.driver,
      car: v.spec.name,
      isPlayer: v.isPlayer,
      wrecked: v.wrecked && !v.finished,
      finished: v.finished,
      time: v.finished ? v.finishTime : undefined,
      takedowns: v.takedowns,
    }));
  }

  /** Per-render-frame visuals: models, particles, audio, HUD. */
  render(dt: number, time: number): void {
    const { fx, hud, audio, cam, track } = this.d;
    const simDt = this.paused ? 0 : dt * this.timeScale;
    for (const v of this.vehicles) {
      const model = this.models.get(v)!;
      model.sync(v, simDt);
      if (simDt <= 0) continue;
      const dmg = Math.max(v.damage.front, v.totalDamage);
      // Engine smoke grows with front damage; wrecks burn.
      if (v.wrecked) {
        const p = this.localToWorld(v, 0, v.halfL * 0.6, 1);
        if (Math.random() < 0.7) fx.flame(p.x, p.y, p.z);
        if (Math.random() < 0.5) fx.smokePuff(p.x, p.y + 0.6, p.z, 1);
      } else if (dmg > 35 && Math.random() < (dmg - 35) / 60) {
        const p = this.localToWorld(v, 0, v.halfL * 0.65, 0.9);
        fx.smokePuff(p.x, p.y, p.z, Math.min(1, (dmg - 35) / 50), v.vx, v.vz);
      }
      if (v.nitroActive) {
        for (const side of [-0.35, 0.35]) {
          const p = this.localToWorld(v, side, -v.halfL - 0.15, 0.4);
          fx.nitroFlame(p.x, p.y, p.z, v.vx, v.vz);
        }
      }
      if (v.drifting || (v.braking && v.speed > 25 && Math.random() < 0.3)) {
        for (const side of [-0.75, 0.75]) {
          const p = this.localToWorld(v, side, -v.halfL + 0.7, 0.2);
          fx.tyreSmoke(p.x, p.y, p.z);
        }
      }
    }
    fx.update(simDt);
    cam.update(this.player, Math.max(simDt, 0.0001), time);

    const p = this.player;
    audio.engine(p.speed, p.input.throttle, p.nitroActive, !p.wrecked && this.state !== 'title');
    audio.scrape(this.paused ? 0 : this.playerScrape);
    this.playerScrape = 0;

    const ranking = this.ranking();
    hud.update(p, ranking.indexOf(p) + 1, this.vehicles.length, this.standings(), track.features.finishS - p.s, this.raceTime);
  }
}
