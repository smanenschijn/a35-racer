import { tuning, ROAD, type AIPersonality } from '../config';
import type { Track } from '../track/Track';
import type { Vehicle } from './Vehicle';

const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));
const wrap = (a: number) => Math.atan2(Math.sin(a), Math.cos(a));

/**
 * Racing AI: pure-pursuit steering towards a lane target, corner speed from upcoming
 * curvature, lane changes to overtake, and opportunistic shoves into rivals.
 */
export class AIDriver {
  readonly vehicle: Vehicle;
  readonly personality: AIPersonality;
  private targetD: number;
  private laneTimer = 0;
  private stuckTime = 0;
  private attackTimer = 6 + Math.random() * 4; // no shoving right off the grid
  /** Set when the AI wants to be reset onto the road. */
  needsReset = false;

  constructor(vehicle: Vehicle, personality: AIPersonality, startD: number) {
    this.vehicle = vehicle;
    this.personality = personality;
    this.targetD = startD;
  }

  update(dt: number, track: Track, others: Vehicle[], player: Vehicle): void {
    const v = this.vehicle;
    const inp = v.input;
    if (v.wrecked || v.frozen) return;
    const p = this.personality;
    const speed = v.forwardSpeed;
    this.laneTimer -= dt;
    this.attackTimer -= dt;

    // --- Rubber banding (light) ---
    const gap = player.s - v.s;
    if (gap > 90) v.powerFactor = tuning.rubberBandBehind;
    else if (gap < -150) v.powerFactor = tuning.rubberBandAhead;
    else v.powerFactor = 1;

    // --- Traffic awareness: overtake slower cars ahead, attack neighbours ---
    let blocked = false;
    let victim: Vehicle | null = null;
    for (const o of others) {
      if (o === v) continue;
      const ds = o.s - v.s;
      const dd = o.d - v.d;
      if (ds > 0 && ds < 30 && Math.abs(o.d - this.targetD) < 2.2 && (o.forwardSpeed < speed - 1 || o.wrecked)) blocked = true;
      if (!o.wrecked && Math.abs(ds) < 4.5 && Math.abs(dd) < 3.8 && Math.abs(dd) > 1.2) {
        // Prefer hitting the player, then anyone.
        if (!victim || o === player) victim = o;
      }
    }
    if (blocked && this.laneTimer <= 0) {
      const lanes = [...ROAD.laneCenters, 4.0];
      const options = lanes.filter((l) => Math.abs(l - this.targetD) > 1.5);
      const free = options.filter((l) => !others.some((o) => o !== v && o.s > v.s - 6 && o.s - v.s < 30 && Math.abs(o.d - l) < 2));
      const pick = (free.length ? free : options)[Math.floor(Math.random() * (free.length || options.length))];
      this.targetD = pick;
      this.laneTimer = 1.5;
    }

    // Aggressive drivers steer into the player when alongside, and use the ram.
    let lineD = this.targetD;
    const aggro = p.aggression * tuning.aiAggression;
    if (victim && aggro > 0) {
      const dir = Math.sign(victim.d - v.d);
      // Rivals mostly gang up on the player; AI-vs-AI fights are rarer.
      const vsPlayer = victim === player ? 1 : 0.3;
      if (this.attackTimer <= 0 && v.ramCooldown <= 0) {
        // One roll per opportunity, not per physics step.
        if (Math.random() < aggro * vsPlayer) {
          if (dir > 0) inp.ramRight = true;
          else inp.ramLeft = true;
          this.attackTimer = 2.5 + Math.random() * 3 * (1 - aggro);
        } else {
          this.attackTimer = 1.2;
        }
      }
      lineD = lineD + (victim.d - lineD) * 0.5 * aggro * vsPlayer;
    } else if (aggro > 0.5 && gap < 0 && gap > -25 && Math.abs(player.d - v.d) < 4) {
      // Block the player behind us by drifting into their lane.
      lineD += (player.d - lineD) * 0.35 * aggro;
    }
    lineD = clamp(lineD, -ROAD.halfWidth + 1.3, ROAD.halfWidth - 1.3);

    // --- Steering: pure pursuit towards a point ahead on the chosen line ---
    const look = 9 + Math.max(0, speed) * 0.45;
    const target = track.pointAt(v.s + look, lineD);
    const desired = Math.atan2(target.x - v.x, target.z - v.z);
    const err = wrap(desired - v.heading);
    inp.steer = clamp(-err * 3.2 + v.angVel * 0.15, -1, 1);

    // --- Speed: slow down for upcoming curvature ---
    let maxK = 0;
    for (let ahead = 0; ahead < 140; ahead += 10) maxK = Math.max(maxK, Math.abs(track.curvatureAt(v.s + ahead)));
    const lat = tuning.aiCornerLatAccel * (0.75 + 0.25 * p.skill);
    const cornerSpeed = maxK > 1e-5 ? Math.sqrt(lat / maxK) : Infinity;
    const wanted = Math.min(v.spec.topSpeed * (0.9 + 0.1 * p.skill), cornerSpeed);
    inp.throttle = speed < wanted ? 1 : speed < wanted + 2 ? 0.3 : 0;
    inp.brake = speed > wanted + 4 ? 0.6 : 0;
    inp.handbrake = false;
    inp.nitro = v.nitro > 0.6 && Math.abs(inp.steer) < 0.3 && speed > 25 && Math.random() < 0.02 * (1 + p.skill) ? true : inp.nitro && v.nitro > 0.1;

    // --- Stuck recovery ---
    const facingBack = Math.abs(wrap(v.heading - track.frame(v.s).heading)) > 1.8;
    if (Math.abs(speed) < 3 || facingBack) this.stuckTime += dt;
    else this.stuckTime = 0;
    if (this.stuckTime > 2.5) {
      this.needsReset = true;
      this.stuckTime = 0;
    }
  }

  setLane(d: number): void {
    this.targetD = d;
  }

  resetLane(): void {
    this.targetD = ROAD.laneCenters[Math.floor(Math.random() * ROAD.laneCenters.length)];
  }

  get laneTarget(): number {
    return this.targetD;
  }
}
