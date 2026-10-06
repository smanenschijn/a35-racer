// Keyboard + Gamepad input, merged into one control state for the player.

export interface Controls {
  throttle: number;
  brake: number;
  steer: number;
  handbrake: boolean;
  nitro: boolean;
  ramLeft: boolean;
  ramRight: boolean;
  reset: boolean;
  restart: boolean;
  pause: boolean;
  mute: boolean;
  debug: boolean;
  nextTrack: boolean;
  volumeUp: boolean;
  volumeDown: boolean;
  confirm: boolean;
  // Menu navigation (edges)
  navUp: boolean;
  navDown: boolean;
  navLeft: boolean;
  navRight: boolean;
  back: boolean;
  any: boolean;
}

/** Held controls fed by the on-screen touch buttons. */
export interface TouchState {
  steer: number;
  throttle: number;
  brake: number;
  nitro: boolean;
  handbrake: boolean;
}

const NAV_KEYS: Record<string, keyof Controls> = {
  ArrowUp: 'navUp',
  KeyW: 'navUp',
  ArrowDown: 'navDown',
  KeyS: 'navDown',
  ArrowLeft: 'navLeft',
  KeyA: 'navLeft',
  ArrowRight: 'navRight',
  KeyD: 'navRight',
  Escape: 'back',
  Backspace: 'back',
};

const EDGE_KEYS: Record<string, keyof Controls> = {
  KeyQ: 'ramLeft',
  KeyE: 'ramRight',
  Backspace: 'reset',
  KeyF: 'reset',
  KeyR: 'restart',
  Escape: 'pause',
  KeyP: 'pause',
  KeyM: 'mute',
  KeyT: 'debug',
  KeyN: 'nextTrack',
  Equal: 'volumeUp',
  NumpadAdd: 'volumeUp',
  Minus: 'volumeDown',
  NumpadSubtract: 'volumeDown',
  Enter: 'confirm',
  Space: 'confirm',
};

// Standard gamepad mapping button indices.
const PAD = { a: 0, b: 1, x: 2, y: 3, l1: 4, r1: 5, l2: 6, r2: 7, select: 8, start: 9 };

export class Input {
  private keys = new Set<string>();
  private edges = new Set<keyof Controls>();
  private padPrev: boolean[] = [];
  private kbSteer = 0;
  private lastPad: Gamepad | null = null;
  usingGamepad = false;
  usingTouch = false;
  readonly touch: TouchState = { steer: 0, throttle: 0, brake: 0, nitro: false, handbrake: false };
  private stickPrev = { x: 0, y: 0 };

  /** For on-screen buttons and menus: fire a one-shot control. */
  press(edge: keyof Controls): void {
    this.edges.add(edge);
    this.edges.add('any');
  }

  constructor() {
    window.addEventListener('keydown', (e) => {
      if (e.repeat) return;
      this.keys.add(e.code);
      const edge = EDGE_KEYS[e.code];
      if (edge) this.edges.add(edge);
      const nav = NAV_KEYS[e.code];
      if (nav) this.edges.add(nav);
      this.edges.add('any');
      this.usingGamepad = false;
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space', 'Backspace'].includes(e.code)) e.preventDefault();
    });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => this.keys.clear());
  }

  private key(...codes: string[]): boolean {
    return codes.some((c) => this.keys.has(c));
  }

  poll(dt: number): Controls {
    const c: Controls = {
      throttle: 0, brake: 0, steer: 0, handbrake: false, nitro: false, ramLeft: false, ramRight: false,
      reset: false, restart: false, pause: false, mute: false, debug: false,
      nextTrack: false, volumeUp: false, volumeDown: false, confirm: false,
      navUp: false, navDown: false, navLeft: false, navRight: false, back: false, any: false,
    };

    // Keyboard: smoothed steering so taps make small corrections.
    const left = this.key('ArrowLeft', 'KeyA');
    const right = this.key('ArrowRight', 'KeyD');
    const target = (right ? 1 : 0) - (left ? 1 : 0);
    const rate = target === 0 || Math.sign(target) !== Math.sign(this.kbSteer) ? 5 : 2.4;
    this.kbSteer += Math.max(-rate * dt, Math.min(rate * dt, target - this.kbSteer));
    c.steer = this.kbSteer;
    c.throttle = this.key('ArrowUp', 'KeyW') ? 1 : 0;
    c.brake = this.key('ArrowDown', 'KeyS') ? 1 : 0;
    c.handbrake = this.key('Space');
    c.nitro = this.key('ShiftLeft', 'ShiftRight');
    for (const e of this.edges) (c as unknown as Record<string, boolean>)[e] = true;
    this.edges.clear();

    // Touch buttons
    const t = this.touch;
    if (t.steer !== 0) c.steer = t.steer;
    c.throttle = Math.max(c.throttle, t.throttle);
    c.brake = Math.max(c.brake, t.brake);
    c.nitro ||= t.nitro;
    c.handbrake ||= t.handbrake;

    // Gamepad
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const pad = Array.from(pads).find((p): p is Gamepad => !!p && p.connected) ?? null;
    this.lastPad = pad;
    if (pad) {
      const btn = (i: number) => pad.buttons[i]?.pressed ?? false;
      const val = (i: number) => pad.buttons[i]?.value ?? 0;
      const pressed = (i: number) => btn(i) && !this.padPrev[i];
      let ax = pad.axes[0] ?? 0;
      const dead = 0.12;
      ax = Math.abs(ax) < dead ? 0 : (ax - Math.sign(ax) * dead) / (1 - dead);
      const padActive = Math.abs(ax) > 0 || val(PAD.r2) > 0.05 || val(PAD.l2) > 0.05 || pad.buttons.some((b) => b.pressed);
      if (padActive) this.usingGamepad = true;
      if (Math.abs(ax) > Math.abs(c.steer)) c.steer = Math.sign(ax) * ax * ax; // squared for precision
      c.throttle = Math.max(c.throttle, val(PAD.r2));
      c.brake = Math.max(c.brake, val(PAD.l2));
      c.handbrake ||= btn(PAD.a);
      c.nitro ||= btn(PAD.b);
      c.ramLeft ||= pressed(PAD.l1);
      c.ramRight ||= pressed(PAD.r1);
      c.reset ||= pressed(PAD.y);
      c.restart ||= pressed(PAD.select);
      c.pause ||= pressed(PAD.start);
      c.confirm ||= pressed(PAD.a) || pressed(PAD.start);
      c.nextTrack ||= pressed(PAD.x);
      c.back ||= pressed(PAD.b);
      c.navUp ||= pressed(12);
      c.navDown ||= pressed(13);
      c.navLeft ||= pressed(14);
      c.navRight ||= pressed(15);
      // The stick also navigates menus (edge when it crosses the threshold).
      const sx = pad.axes[0] ?? 0;
      const sy = pad.axes[1] ?? 0;
      if (sx < -0.6 && this.stickPrev.x >= -0.6) c.navLeft = true;
      if (sx > 0.6 && this.stickPrev.x <= 0.6) c.navRight = true;
      if (sy < -0.6 && this.stickPrev.y >= -0.6) c.navUp = true;
      if (sy > 0.6 && this.stickPrev.y <= 0.6) c.navDown = true;
      this.stickPrev = { x: sx, y: sy };
      c.any ||= pad.buttons.some((_, i) => pressed(i));
      this.padPrev = pad.buttons.map((b) => b.pressed);
    }
    return c;
  }

  rumble(strong: number, weak: number, ms: number): void {
    const act = (this.lastPad as (Gamepad & { vibrationActuator?: { playEffect: (t: string, p: object) => Promise<unknown> } }) | null)
      ?.vibrationActuator;
    act?.playEffect('dual-rumble', { duration: ms, strongMagnitude: Math.min(1, strong), weakMagnitude: Math.min(1, weak) }).catch(() => {});
  }
}
