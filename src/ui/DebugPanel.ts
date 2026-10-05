import GUI from 'lil-gui';
import { tuning } from '../config';

/** Live tuning panel (toggle with T). Values write straight into the shared tuning object. */
export class DebugPanel {
  private gui: GUI;

  constructor(onRestart: () => void) {
    this.gui = new GUI({ title: 'A35 Racer tuning (T)' });
    const t = tuning as Record<string, number | boolean>;
    const groups: [string, string[], number, number, number][] = [
      ['Handling', ['engineAccel', 'brakeDecel', 'grip', 'handbrakeGrip', 'driftGripFactor', 'steerRateLow', 'steerRateHigh', 'yawResponse', 'handbrakeYawBoost'], 0, 30, 0.05],
      ['Nitro', ['nitroAccel', 'nitroTopSpeedFactor', 'nitroDrain', 'nitroFillPerDamage', 'nitroFillTakedown', 'nitroFillNearMiss', 'nitroFillDriftPerSec'], 0, 20, 0.001],
      ['Rammen', ['ramSideSpeed', 'ramDuration', 'ramCooldown', 'ramMassFactor', 'ramDamageFactor'], 0, 20, 0.01],
      ['Schade', ['damagePerImpulse', 'railDamagePerSpeed', 'railScrapeDamage', 'takedownRailBonus', 'playerDamageFactor', 'aiDamageFactor', 'stunTime', 'carRestitution', 'railRestitution', 'railFriction'], 0, 5, 0.0001],
      ['AI', ['aiCornerLatAccel', 'aiAggression', 'rubberBandBehind', 'rubberBandAhead'], 0, 25, 0.01],
      ['Camera', ['camDistance', 'camHeight', 'camFov', 'camFovNitro'], 0, 120, 0.1],
    ];
    for (const [name, keys, min, max, step] of groups) {
      const f = this.gui.addFolder(name);
      for (const k of keys) {
        const v = t[k] as number;
        f.add(t, k, Math.min(min, v), Math.max(max, v * 3), step);
      }
      f.close();
    }
    this.gui.add({ restart: onRestart }, 'restart').name('Herstart race (R)');
    this.gui.add({ copy: () => navigator.clipboard?.writeText(JSON.stringify(tuning, null, 2)) }, 'copy').name('Kopieer waarden (JSON)');
    this.gui.hide();
  }

  toggle(): void {
    if (this.gui._hidden) this.gui.show();
    else this.gui.hide();
  }
}
