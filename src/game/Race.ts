import * as THREE from 'three';
import { AI_PERSONALITIES, CARS, POLICE_CAR, RIVALS, ROAD, tuning, type CarSpec } from '../config';
import type { GameAudio } from '../core/Audio';
import type { EventBus } from '../core/Events';
import type { Controls } from '../core/Input';
import type { Announcer } from '../core/Announcer';
import type { MusicPlayer } from '../core/Music';
import type { Effects } from '../fx/Particles';
import { collideVehicles } from '../physics/Collisions';
import type { Track } from '../track/Track';
import type { Hud, StandingRow } from '../ui/Hud';
import { AIDriver } from '../vehicle/AIDriver';
import { CarModel } from '../vehicle/CarModel';
import { Vehicle, type VehicleRole } from '../vehicle/Vehicle';
import type { ChaseCamera } from './ChaseCamera';
import { PoliceManager } from './Police';
import { TrafficManager } from './Traffic';

export type RaceState = 'menu' | 'countdown' | 'racing' | 'finished';

export interface RaceResult {
  rows: StandingRow[];
  position: number;
  time: number;
  takedowns: number;
  outOfTime: boolean;
  /** Top 3 and within time: the stage is cleared. */
  qualified: boolean;
  car: string;
}

const HIT_WORDS = ['BEUK!', 'KNAL!', 'PATS!', 'BAM!', 'KRAK!'];

interface Deps {
  scene: THREE.Scene;
  track: Track;
  events: EventBus;
  fx: Effects;
  hud: Hud;
  audio: GameAudio;
  music: MusicPlayer;
  announcer: Announcer;
  cam: ChaseCamera;
  rumble: (strong: number, weak: number, ms: number) => void;
}

export class Race {
  /** Every physics vehicle: racers, traffic and police. */
  readonly vehicles: Vehicle[] = [];
  /** The eight competitors (player first). */
  readonly racers: Vehicle[] = [];
  player: Vehicle;
  private ais: AIDriver[] = [];
  private models = new Map<Vehicle, CarModel>();
  readonly traffic: TrafficManager;
  readonly police: PoliceManager;
  state: RaceState = 'menu';
  /** Checkpoint clock (seconds left). */
  timeLeft = 0;
  private nextCheckpoint = 0;
  private checkpointBonus: number[] = [];
  private outOfTime = false;
  private warned = false;
  /** In the menu only this racer is shown (showroom). */
  showroom: Vehicle | null = null;
  /** Called once the result is known (after the finish or when time runs out). */
  onFinished: ((r: RaceResult) => void) | null = null;
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
  private lastTaunt = -99;
  private active: Vehicle[] = [];
  private d: Deps;
  /** Testing aid: let an AI drive the player's car (?autopilot in the URL). */
  autopilot = new URLSearchParams(location.search).has('autopilot');
  private autoDriver: AIDriver;

  constructor(deps: Deps) {
    this.d = deps;
    this.player = this.addVehicle(CARS.rx, 'racer', true);
    this.racers.push(this.player);
    for (const id of RIVALS) {
      const v = this.addVehicle(CARS[id], 'racer');
      this.racers.push(v);
      this.ais.push(new AIDriver(v, AI_PERSONALITIES[id], 0));
    }
    this.autoDriver = new AIDriver(this.player, { ...AI_PERSONALITIES.golv, playerFocus: 0 }, ROAD.laneCenters[1]);

    this.traffic = new TrafficManager({
      scene: deps.scene,
      track: deps.track,
      create: (spec) => this.addVehicle(spec, 'traffic'),
      recolor: (v, hex) => this.models.get(v)!.recolor(hex),
      repair: (v) => this.fullRepair(v),
    });
    this.police = new PoliceManager({
      scene: deps.scene,
      track: deps.track,
      events: deps.events,
      create: () => this.addVehicle(POLICE_CAR, 'police'),
      repair: (v) => this.fullRepair(v),
    });

    this.wireEvents();
    this.reset();
  }

  private addVehicle(spec: CarSpec, role: VehicleRole, isPlayer = false): Vehicle {
    const v = new Vehicle(spec, isPlayer, role);
    const model = new CarModel(spec);
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

  private fullRepair(v: Vehicle): void {
    v.repair(0);
    for (const z of ['front', 'rear', 'left', 'right'] as const) v.damage[z] = 0;
    v.lastHitBy = null;
    v.lastHitTime = -99;
    v.ramCooldown = 0;
    v.nitroActive = false;
    this.models.get(v)!.repair();
  }

  reset(): void {
    const t = this.d.track;
    const start = t.features.startS;
    // Grid: two per row, rivals in RIVALS order, the player starts last.
    const order = [...this.racers.slice(1), this.player];
    order.forEach((v, i) => {
      const row = Math.floor(i / 2);
      const lane = i % 2;
      v.place(t, start - 10 - row * 10 - lane * 3, ROAD.laneCenters[lane], 0);
      this.fullRepair(v);
      v.nitro = 0.35;
      v.frozen = true;
      v.finished = false;
      v.takedowns = 0;
      v.penalty = 0;
      v.input.throttle = v.input.brake = v.input.steer = 0;
    });
    this.ais.forEach((ai) => ai.setLane(ai.vehicle.d));
    this.traffic.reset(start);
    this.police.reset();
    this.finishOrder = [];
    this.resultsShown = false;
    this.raceTime = 0;
    this.timeScale = 1;
    this.slowMoT = 0;
    this.respawnT = 0;
    this.prevDs.clear();
    this.paused = false;
    this.setupClock();
    this.d.cam.snap();
    this.d.hud.hideOverlay();
    if (this.state !== 'menu') this.startCountdown();
  }

  /** Arcade time limit: enough to reach the first checkpoint; each gate buys the next leg. */
  private setupClock(): void {
    const f = this.d.track.features;
    const pace = 40; // m/s (~144 km/h) you need to average, crashes included
    const gates = [...f.checkpoints, f.finishS];
    this.timeLeft = (gates[0] - f.startS) / pace + 10;
    this.checkpointBonus = gates.slice(1).map((g, i) => (g - gates[i]) / pace + 2);
    this.nextCheckpoint = 0;
    this.outOfTime = false;
    this.warned = false;
  }

  /** Swap cars with the rival who drives `id` (they take over your old car). */
  setPlayerCar(id: string): void {
    const target = this.racers.find((v) => v.spec.id === id);
    if (!target || target === this.player) return;
    const old = this.player;
    const ai = this.ais.find((a) => a.vehicle === target)!;
    const rivalName = target.driverName;
    target.isPlayer = true;
    target.driverName = 'Jij';
    old.isPlayer = false;
    old.driverName = rivalName;
    ai.vehicle = old;
    this.autoDriver.vehicle = target;
    this.player = target;
    this.racers.splice(this.racers.indexOf(target), 1);
    this.racers.unshift(target);
    this.reset();
  }

  /** Menu → race. */
  start(): void {
    this.state = 'countdown';
    this.reset();
  }

  /** Race → menu (grid reset, cars frozen). */
  toMenu(): void {
    this.state = 'menu';
    this.reset();
  }

  startCountdown(): void {
    this.state = 'countdown';
    this.countdownT = 0;
    this.countdownStep = -1;
    this.d.hud.hideOverlay();
    this.d.hud.setHelpVisible(true);
  }

  private wireEvents(): void {
    const { events, fx, hud, audio, cam, announcer } = this.d;

    events.on('impact', (e) => {
      const n = Math.min(60, Math.floor(e.strength * 2.5));
      fx.sparkBurst(e.x, e.y, e.z, n, (e.a.vx + (e.b?.vx ?? e.a.vx)) * 0.4, (e.a.vz + (e.b?.vz ?? e.a.vz)) * 0.4);
      if (e.strength > 10) fx.debris(e.x, e.y, e.z, 8, e.a.vx, e.a.vz);
      this.models.get(e.a)?.kick(e.x - e.a.x, e.z - e.a.z, e.a, e.strength);
      if (e.b) this.models.get(e.b)?.kick(e.x - e.b.x, e.z - e.b.z, e.b, e.strength);
      const involvesPlayer = e.a === this.player || e.b === this.player;
      const dist = Math.hypot(e.x - this.player.x, e.z - this.player.z);
      if (dist < 120) audio.crash(e.strength * (involvesPlayer ? 1 : Math.max(0.2, 1 - dist / 120)));
      if (involvesPlayer) {
        cam.addShake(Math.min(0.9, e.strength / 20));
        this.d.rumble(e.strength / 15, e.strength / 10, 180);
        if (e.kind === 'car' && e.strength > 9) {
          hud.message(HIT_WORDS[Math.floor(Math.random() * HIT_WORDS.length)], '#ffd400', false, 0.9);
        }
        // Chaos draws the police: hitting traffic or the police themselves.
        const other = e.a === this.player ? e.b : e.a;
        if (other && this.state === 'racing') {
          if (other.role === 'traffic' && e.strength > 5) this.police.addHeat(Math.min(0.35, e.strength * 0.018));
          if (other.role === 'police' && e.strength > 3) this.police.addHeat(0.4);
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
      const dist = Math.hypot(victim.x - this.player.x, victim.z - this.player.z);
      if (dist < 200) audio.crash(25 * Math.max(0.3, 1 - dist / 200));
      if (victim === this.player) {
        hud.message('TOTAL LOSS!', '#ff2a2a', true, 2.2);
        announcer.say('Total loss!', { priority: true });
        this.slowMo(0.3, 1.2);
        this.respawnT = 2.6;
        cam.addShake(1);
        this.d.rumble(1, 1, 600);
        return;
      }
      const byPlayer = attacker === this.player;
      if (victim.isRacer) {
        if (byPlayer) {
          hud.message('TAKEDOWN!', '#ffd400', true, 2);
          announcer.say(`Takedown! ${victim.driverName} ligt eruit!`, { priority: true });
          hud.message(`${victim.driverName} ligt eruit!`, '#ffffff', false, 2);
          this.slowMo(0.35, 1.1);
          cam.addShake(0.6);
          this.d.rumble(0.8, 1, 400);
          this.police.addHeat(0.6);
        } else {
          hud.message(`${victim.driverName} is total loss`, '#ff9a3c', false, 1.6);
        }
      } else if (byPlayer && victim.role === 'police') {
        hud.message('AGENT UITGESCHAKELD!', '#4f8bff', true, 2);
        announcer.say('Agent uitgeschakeld!');
        this.slowMo(0.4, 0.9);
        this.police.addHeat(1.2);
      } else if (byPlayer) {
        hud.message('BOEM!', '#ff9a3c', false, 1);
        this.police.addHeat(0.8);
      }
    });

    events.on('ram', ({ vehicle }) => {
      if (vehicle === this.player) {
        audio.whoosh();
        if (vehicle.ramTarget && this.state === 'racing') this.police.addHeat(0.15);
      } else if (vehicle.isRacer && vehicle.ramTarget === this.player && this.simTime - this.lastTaunt > 6 && Math.random() < 0.5) {
        // Rivals talk trash when they go for you.
        const ai = this.ais.find((a) => a.vehicle === vehicle);
        const taunts = ai?.personality.taunts ?? [];
        if (taunts.length) {
          hud.taunt(vehicle.driverName, taunts[Math.floor(Math.random() * taunts.length)]);
          this.lastTaunt = this.simTime;
        }
      }
    });

    events.on('nearMiss', ({ vehicle, other }) => {
      if (vehicle === this.player) {
        if (other.role === 'traffic' && Math.random() < 0.6) audio.horn(other.spec.kind === 'truck', 0.8);
        hud.message('RAKELINGS!', '#36c6ff', false, 0.9);
        vehicle.nitro = Math.min(1, vehicle.nitro + tuning.nitroFillNearMiss);
      }
    });

    events.on('message', (m) => {
      hud.message(m.text, m.color, m.big, m.big ? 2 : 1.4);
      if (m.text === 'POLITIE!') announcer.say('Politie!');
      if (m.text.startsWith('WEGBLOKKADE')) announcer.say('Wegblokkade verderop!');
    });

    events.on('flash', ({ kmh }) => {
      hud.flash();
      audio.flash();
      hud.message(`GEFLITST! ${Math.round(kmh)} km/u`, '#ffffff', false, 1.6);
      announcer.say('Geflitst!');
    });

    events.on('busted', ({ penalty }) => {
      hud.message('BEKEURING!', '#ff2a2a', true, 2);
      announcer.say(`Bekeuring! ${penalty} seconden erbij.`, { priority: true });
      hud.message(`+${penalty} seconden`, '#ffffff', false, 2);
      audio.crash(6);
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
    const { hud, audio, music } = this.d;
    if (c.any) audio.start();
    if (c.nextTrack) music.next();
    if (c.volumeUp || c.volumeDown) {
      const vol = music.changeVolume(c.volumeUp ? 0.1 : -0.1);
      hud.message(`MUZIEK ${Math.round(vol * 100)}%`, '#ffffff', false, 0.8);
    }

    if (this.state === 'menu') return;
    if (c.restart) {
      this.reset();
      return;
    }
    music.setMuffled(this.paused || this.timeScale < 1);
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
    for (let tries = 0; tries < 12; tries++) {
      if (!this.vehicles.some((o) => o !== v && o.active && Math.abs(o.s - s) < o.halfL + v.halfL + 4 && Math.abs(o.d - lane) < 2.6)) break;
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
    if (this.paused || this.state === 'menu') return;
    this.simTime += dt;
    const t = this.d.track;
    const { hud, audio, music, announcer } = this.d;

    if (this.state === 'countdown') {
      this.countdownT += dt;
      const step = Math.floor(this.countdownT);
      if (step !== this.countdownStep) {
        this.countdownStep = step;
        if (step < 3) {
          hud.countdown(String(3 - step));
          audio.beep(false);
          announcer.say(['Drie', 'Twee', 'Eén'][step], { priority: true, rate: 1.3 });
        } else {
          hud.countdown('GAS GEAVEN!', true);
          audio.beep(true);
          announcer.say('Gas geaven!', { priority: true, rate: 1.2, pitch: 1.1 });
          this.state = 'racing';
          for (const v of this.racers) v.frozen = false;
          music.playRace();
          setTimeout(() => hud.setHelpVisible(false), 8000);
        }
      }
    } else {
      this.raceTime += dt;
    }
    if (this.state === 'racing') this.tickClock(dt);

    this.active = this.vehicles.filter((v) => v.active);
    const all = this.active;

    if (this.autopilot && !this.player.finished) {
      this.autoDriver.update(dt, t, all, this.ais[0].vehicle);
      if (this.autoDriver.needsReset) {
        this.autoDriver.needsReset = false;
        this.respawn(this.player, false);
      }
    }
    for (const ai of this.ais) {
      ai.update(dt, t, all, this.player);
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
    this.traffic.update(dt, all, this.racers, this.player);
    this.police.update(dt, this.player, all, this.state === 'racing', this.simTime);

    for (const v of all) v.update(dt, this.simTime, t, this.d.events, all);
    for (let i = 0; i < all.length; i++) {
      for (let j = i + 1; j < all.length; j++) {
        collideVehicles(all[i], all[j], this.simTime, this.d.events);
      }
    }

    // Finish line
    const finishS = t.features.finishS;
    for (const v of this.racers) {
      const open = this.state === 'racing' || (this.state === 'finished' && !v.isPlayer);
      if (!v.finished && !v.wrecked && v.s >= finishS && open && !(v.isPlayer && this.outOfTime)) {
        v.finished = true;
        v.finishTime = this.raceTime + v.penalty;
        this.finishOrder.push(v);
        if (v.isPlayer) {
          const pos = this.finishOrder.filter((o) => o.finishTime <= v.finishTime).length;
          hud.message(pos === 1 ? 'WINNAAR!' : `${pos}e PLAATS`, pos <= 3 ? '#4dff6a' : '#ff9a3c', true, 2.5);
          announcer.say(pos === 1 ? 'Winnaar! Gas geaven!' : pos <= 3 ? `Finish! Plaats ${pos}` : `Finish. Plaats ${pos}. Dat mot beter.`,
            { priority: true });
          if (v.penalty > 0) hud.message(`incl. ${v.penalty} s boete`, '#ff9a3c', false, 2.5);
          this.finishedAt = this.raceTime;
          this.state = 'finished';
        }
      }
    }
    // Wait out the player's penalty so rivals crossing in that window rank fairly.
    if (this.state === 'finished' && !this.resultsShown && this.raceTime - this.finishedAt > Math.max(2.5, this.player.penalty)) {
      this.resultsShown = true;
      const ranking = this.ranking();
      const position = ranking.indexOf(this.player) + 1;
      const result: RaceResult = {
        rows: this.standings(),
        position,
        time: this.player.finished ? this.player.finishTime : this.raceTime,
        takedowns: this.player.takedowns,
        outOfTime: this.outOfTime,
        qualified: !this.outOfTime && position <= 3,
        car: this.player.spec.name,
      };
      if (this.onFinished) this.onFinished(result);
      else hud.showResults(result.rows, position);
      music.playTitle();
    }

    // Player respawn after a total loss.
    if (this.player.wrecked && this.respawnT > 0) {
      this.respawnT -= dt / Math.max(this.timeScale, 0.01);
      if (this.respawnT <= 0) {
        this.respawn(this.player, true);
        hud.message('OPGELAPT!', '#4dff6a', false, 1.2);
        this.d.announcer.say('Kump wal goed!');
      }
    }

    this.detectNearMisses();
  }

  private tickClock(dt: number): void {
    const { hud, announcer, audio } = this.d;
    const f = this.d.track.features;
    const p = this.player;
    if (this.nextCheckpoint < f.checkpoints.length && p.s >= f.checkpoints[this.nextCheckpoint]) {
      const bonus = this.checkpointBonus[this.nextCheckpoint];
      this.timeLeft += bonus;
      this.nextCheckpoint++;
      this.warned = false;
      hud.message('CHECKPOINT!', '#4dff6a', true, 1.8);
      hud.message(`+${Math.round(bonus)} seconden`, '#ffffff', false, 1.8);
      audio.chime();
      announcer.say('Checkpoint! Extra tijd!');
    }
    this.timeLeft = Math.max(0, this.timeLeft - dt);
    if (!this.warned && this.timeLeft < 10) {
      this.warned = true;
      announcer.say('Tien seconden!', { priority: true });
    }
    if (this.timeLeft <= 0 && !p.finished) {
      this.outOfTime = true;
      this.state = 'finished';
      this.finishedAt = this.raceTime;
      p.input.throttle = 0;
      hud.message('TIJD OP!', '#ff2a2a', true, 2.5);
      announcer.say('Tijd op!', { priority: true });
    }
  }

  private detectNearMisses(): void {
    const p = this.player;
    if (p.wrecked || this.state !== 'racing') return;
    for (const o of this.active) {
      if (o === p) continue;
      const ds = o.s - p.s;
      const prev = this.prevDs.get(o);
      this.prevDs.set(o, ds);
      if (prev === undefined || o.wrecked || Math.abs(ds) > 20) continue;
      if (Math.sign(prev) !== Math.sign(ds)) {
        const gap = Math.abs(o.d - p.d) - p.halfW - o.halfW;
        const rel = Math.abs(p.forwardSpeed - o.forwardSpeed);
        const recentContact = this.simTime - p.lastContactTime < 1 && p.lastHitBy === o;
        if (gap < 1.0 && gap > 0 && rel > 6 && !recentContact) this.d.events.emit('nearMiss', { vehicle: p, other: o });
      }
    }
  }

  ranking(): Vehicle[] {
    const finished = [...this.finishOrder].sort((a, b) => a.finishTime - b.finishTime);
    const running = this.racers.filter((v) => !v.finished && !v.wrecked).sort((a, b) => b.s - a.s);
    const out = this.racers.filter((v) => !v.finished && v.wrecked);
    return [...finished, ...running, ...out];
  }

  standings(): StandingRow[] {
    return this.ranking().map((v) => ({
      name: v.driverName,
      car: v.spec.name,
      isPlayer: v.isPlayer,
      wrecked: v.wrecked && !v.finished,
      finished: v.finished,
      time: v.finished ? v.finishTime : undefined,
      takedowns: v.takedowns,
      penalty: v.penalty,
    }));
  }

  /** Per-render-frame visuals: models, particles, audio, HUD. */
  render(dt: number, time: number): void {
    const { fx, hud, audio, cam, track } = this.d;
    const simDt = this.paused ? 0 : dt * this.timeScale;
    const p = this.player;
    for (const v of this.vehicles) {
      const model = this.models.get(v)!;
      model.root.visible = v.active && !(this.state === 'menu' && this.showroom && v.isRacer && v !== this.showroom);
      if (!v.active) continue;
      model.sync(v, simDt);
      if (simDt <= 0) continue;
      // Effects only near the player (traffic far away doesn't need smoke).
      if (Math.abs(v.s - p.s) > 400) continue;
      const dmg = Math.max(v.damage.front, v.totalDamage);
      // Engine smoke grows with front damage; wrecks burn.
      if (v.wrecked) {
        const w = this.localToWorld(v, 0, v.halfL * 0.6, 1);
        if (Math.random() < 0.7) fx.flame(w.x, w.y, w.z);
        if (Math.random() < 0.5) fx.smokePuff(w.x, w.y + 0.6, w.z, 1);
      } else if (dmg > 35 && Math.random() < (dmg - 35) / 60) {
        const w = this.localToWorld(v, 0, v.halfL * 0.65, 0.9);
        fx.smokePuff(w.x, w.y, w.z, Math.min(1, (dmg - 35) / 50), v.vx, v.vz);
      }
      if (v.nitroActive) {
        for (const side of [-0.35, 0.35]) {
          const w = this.localToWorld(v, side, -v.halfL - 0.15, 0.4);
          fx.nitroFlame(w.x, w.y, w.z, v.vx, v.vz);
        }
      }
      if (v.drifting || (v.braking && v.speed > 25 && Math.random() < 0.3)) {
        for (const side of [-0.75, 0.75]) {
          const w = this.localToWorld(v, side, -v.halfL + 0.7, 0.2);
          fx.tyreSmoke(w.x, w.y, w.z);
        }
      }
    }
    this.traffic.renderOncoming(simDt, p.s);
    fx.update(simDt);
    if (this.state !== 'menu') cam.update(p, Math.max(simDt, 0.0001), time);

    audio.engine(p.speed, p.input.throttle, p.nitroActive, !p.wrecked && this.state !== 'menu');
    audio.scrape(this.paused ? 0 : this.playerScrape);
    const squeal = p.drifting ? 1 : p.braking && p.speed > 22 ? 0.5 : 0;
    audio.squeal(this.paused || p.wrecked ? 0 : squeal);
    audio.siren(this.paused ? 0 : Math.max(0, 1 - this.police.nearestSiren / 220));
    this.playerScrape = 0;

    const ranking = this.ranking();
    hud.update({
      player: p,
      position: ranking.indexOf(p) + 1,
      total: this.racers.length,
      rows: this.standings(),
      distanceLeft: track.features.finishS - p.s,
      raceTime: this.raceTime + p.penalty,
      stars: this.police.stars,
      heat: this.police.heat,
      sirenNear: this.police.nearestSiren < 120,
      bust: this.police.bustProgress,
      timeLeft: this.state === 'menu' ? -1 : this.timeLeft,
    });
  }
}
