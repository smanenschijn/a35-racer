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
  private seenHitTime = -99;
  private recoverTimer = 0;
  /** Set when the AI wants to be reset onto the road. */
  needsReset = false;

  constructor(vehicle: Vehicle, personality: AIPersonality, startD: number) {
    this.vehicle = vehicle;
    this.personality = personality;
    this.targetD = startD;
  }

  private brakeTapTimer = 3 + Math.random() * 5;
  private brakeTap = 0;

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

    // --- Look around: who's ahead in our lane, who's beside us ---
    // How far ahead to react depends on closing speed: awareness is in metres at 20 m/s closing.
    const lookTime = p.awareness / 20;
    const scan = 25 + speed * (1 + lookTime);
    let ahead: Vehicle | null = null;
    let aheadDs = Infinity;
    let victim: Vehicle | null = null;
    for (const o of others) {
      if (o === v || !o.active) continue;
      const ds = o.s - v.s;
      const dd = o.d - v.d;
      // Check both our target lane and the lane we're physically in.
      const inLane =
        Math.abs(o.d - this.targetD) < o.halfW + v.halfW + 0.4 || Math.abs(o.d - v.d) < o.halfW + v.halfW + 0.2;
      if (ds > 0 && ds < scan && inLane && ds - o.halfL - v.halfL < aheadDs) {
        ahead = o;
        aheadDs = ds - o.halfL - v.halfL;
      }
      if (o.isRacer && !o.wrecked && Math.abs(ds) < 4.5 && Math.abs(dd) < 3.8 && Math.abs(dd) > 1.2) {
        if (!victim || o === player) victim = o;
      }
    }
    const aheadSlower = ahead !== null && (ahead.forwardSpeed < speed - 1 || ahead.wrecked);
    // Bennie: a rival in front gets shunted, not overtaken.
    const shunting = p.shunter && ahead !== null && ahead.isRacer && !ahead.wrecked && aheadDs < 30;
    const closing = ahead ? Math.max(0, speed - ahead.forwardSpeed) : 0;
    const blocked = aheadSlower && aheadDs < 12 + closing * (0.8 + lookTime) && !shunting;

    let laneChanged = false;
    if (blocked && this.laneTimer <= 0) {
      const lanes = [...ROAD.laneCenters, ROAD.shoulder];
      // Only to an adjacent lane: jumping two lanes cuts straight through the traffic in between.
      const options = lanes.filter((l) => Math.abs(l - this.targetD) > 1.5 && Math.abs(l - v.d) < 4.2);
      // A lane is free if nobody is beside us there and nothing slow is coming up in it.
      const free = options.filter(
        (l) =>
          !others.some((o) => {
            if (o === v || !o.active || Math.abs(o.d - l) > o.halfW + v.halfW + 0.3) return false;
            const ds = o.s - v.s;
            if (ds > -8 - o.halfL && ds < 8 + o.halfL) return true;
            const close = Math.max(0, speed - o.forwardSpeed);
            return ds > 0 && ds < 15 + close * (1 + lookTime);
          }),
      );
      if (free.length) {
        // Prefer the nearest free lane.
        free.sort((a, b) => Math.abs(a - v.d) - Math.abs(b - v.d));
        this.targetD = free[0];
        this.laneTimer = p.laneChangeDelay;
        laneChanged = true;
      }
    }

    // --- Focus on the player (Henk-Jan): go hunt them down ---
    if (p.playerFocus > 0.8 && Math.abs(gap) < 60 && !player.wrecked && this.laneTimer <= 0 && !blocked) {
      this.targetD = clamp(player.d, -ROAD.halfWidth + 1.3, ROAD.halfWidth - 1.3);
      this.laneTimer = 0.8;
    }

    // Aggressive drivers steer into the rival beside them and use the ram.
    let lineD = this.targetD;
    const aggro = p.aggression * tuning.aiAggression;
    // Just got shoved: no counter-attack until we've regained control.
    if (v.lastHitTime !== this.seenHitTime) {
      this.seenHitTime = v.lastHitTime;
      this.recoverTimer = 1.2;
    }
    this.recoverTimer -= dt;
    const recovering = v.stun > 0 || this.recoverTimer > 0;
    if (victim && aggro > 0 && !recovering) {
      const dir = Math.sign(victim.d - v.d);
      // Rivals mostly gang up on the player; AI-vs-AI fights depend on the character.
      const weight = victim === player ? 1 : 0.15 + (1 - p.playerFocus) * 0.5;
      if (this.attackTimer <= 0 && v.ramCooldown <= 0) {
        // One roll per opportunity, not per physics step.
        if (Math.random() < aggro * weight) {
          if (dir > 0) inp.ramRight = true;
          else inp.ramLeft = true;
          this.attackTimer = 2.5 + Math.random() * 3 * (1 - aggro);
        } else {
          this.attackTimer = 1.2;
        }
      }
      lineD = lineD + (victim.d - lineD) * 0.5 * aggro * weight;
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

    // --- Speed: corners, traffic ahead we can't pass, brake taps ---
    let maxK = 0;
    for (let a = 0; a < 140; a += 10) maxK = Math.max(maxK, Math.abs(track.curvatureAt(v.s + a)));
    const lat = tuning.aiCornerLatAccel * (0.75 + 0.25 * p.skill);
    const cornerSpeed = maxK > 1e-5 ? Math.sqrt(lat / maxK) : Infinity;
    let wanted = Math.min(v.spec.topSpeed * (0.9 + 0.1 * p.skill), cornerSpeed);
    if (blocked && !laneChanged && ahead && Math.abs(this.targetD - v.d) < 1.5) {
      // Stuck behind someone: follow at a distance (reckless drivers leave less room).
      const room = 4 + p.awareness * 0.25;
      // Brake early enough: v² = v_ahead² + 2·a·gap with a comfortable 9 m/s².
      const safe = Math.sqrt(Math.max(0, ahead.forwardSpeed ** 2 + 2 * 9 * Math.max(0, aheadDs - room)));
      wanted = Math.min(wanted, safe);
    }
    if (p.erratic > 0) {
      this.brakeTapTimer -= dt;
      if (this.brakeTapTimer <= 0) {
        this.brakeTap = 0.5 + Math.random() * 0.6;
        this.brakeTapTimer = 4 + Math.random() * 6 / p.erratic;
      }
    }
    this.brakeTap = Math.max(0, this.brakeTap - dt);

    inp.throttle = speed < wanted ? 1 : speed < wanted + 2 ? 0.3 : 0;
    inp.brake = speed > wanted + 3 ? Math.min(1, (speed - wanted) / 10 + 0.3) : 0;
    if (this.brakeTap > 0) {
      inp.throttle = 0;
      inp.brake = 0.7;
    }
    inp.handbrake = false;
    inp.nitro = v.nitro > 0.6 && Math.abs(inp.steer) < 0.3 && speed > 25 && !blocked && Math.random() < 0.02 * (1 + p.skill) ? true : inp.nitro && v.nitro > 0.1 && !blocked;

    // --- Stuck recovery ---
    const facingBack = Math.abs(wrap(v.heading - track.frame(v.s).heading)) > 1.8;
    const waitingInTraffic = blocked && ahead !== null && ahead.speed < 3;
    if ((Math.abs(speed) < 3 && !waitingInTraffic) || facingBack) this.stuckTime += dt;
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
