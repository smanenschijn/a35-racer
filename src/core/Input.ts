// Keyboard + Gamepad input, merged into one control state for the player.

export interface Controls {
  throttle: number;
  brake: number;
  steer: number;
  handbrake: boolean;
  nitro: boolean;
  ramLeft: boolean;
  ramRight: boolean;
  /** Ram towards whichever side has a target (touch's single RAM button). */
  ramAuto: boolean;
  /** Held: camera looks behind the car. */
  lookBack: boolean;
  reset: boolean;
  bulletTime: boolean;
  /** Fires once the restart key has been held long enough. */
  restart: boolean;
  /** 0..1 while the restart key is held. */
  restartHold: number;
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

/** Driving actions the player can rebind to other keys. */
export type BindAction =
  | 'throttle' | 'brake' | 'left' | 'right' | 'handbrake' | 'nitro' | 'bulletTime' | 'ramLeft' | 'ramRight' | 'reset' | 'lookBack';

export const BIND_LABELS: Record<BindAction, string> = {
  throttle: 'Gas',
  brake: 'Rem / achteruit',
  left: 'Links sturen',
  right: 'Rechts sturen',
  handbrake: 'Handrem (drift)',
  nitro: 'Nitro',
  bulletTime: 'Bullet time',
  ramLeft: 'Ram links',
  ramRight: 'Ram rechts',
  reset: 'Terug op de weg',
  lookBack: 'Achterom kijken',
};

const DEFAULT_BINDINGS: Record<BindAction, string[]> = {
  throttle: ['ArrowUp', 'KeyW'],
  brake: ['ArrowDown', 'KeyS'],
  left: ['ArrowLeft', 'KeyA'],
  right: ['ArrowRight', 'KeyD'],
  handbrake: ['Space'],
  nitro: ['ShiftLeft', 'ShiftRight'],
  bulletTime: ['KeyC'],
  ramLeft: ['KeyQ'],
  ramRight: ['KeyE'],
  reset: ['KeyF'],
  lookBack: ['KeyV'],
};

/** Keys with a fixed job (menus, pause, music, restart): not available for rebinding. */
export const RESERVED_KEYS = new Set([
  'Escape', 'KeyP', 'KeyM', 'KeyN', 'KeyT', 'KeyR', 'Enter', 'NumpadEnter', 'Equal', 'Minus', 'NumpadAdd', 'NumpadSubtract',
  'Backspace', 'Tab',
]);

const BINDINGS_KEY = 'a35-bindings';

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

/** Fixed one-shot keys (the rebindable ones are looked up in the bindings). */
const EDGE_KEYS: Record<string, keyof Controls> = {
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
  NumpadEnter: 'confirm',
  Space: 'confirm',
};

/** Rebindable actions that fire once per press. */
const EDGE_ACTIONS: Partial<Record<BindAction, keyof Controls>> = {
  ramLeft: 'ramLeft',
  ramRight: 'ramRight',
  reset: 'reset',
  bulletTime: 'bulletTime',
};

// Standard gamepad mapping button indices.
const PAD = { a: 0, b: 1, x: 2, y: 3, l1: 4, r1: 5, l2: 6, r2: 7, select: 8, start: 9, l3: 10, r3: 11 };

/** Seconds the restart key must be held (a stray tap shouldn't throw away a race). */
const RESTART_HOLD = 0.8;

/** Readable name for a key code. */
export function keyName(code: string): string {
  const names: Record<string, string> = {
    ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→', Space: 'SPATIE', ShiftLeft: 'SHIFT', ShiftRight: 'SHIFT',
    ControlLeft: 'CTRL', ControlRight: 'R-CTRL', AltLeft: 'ALT', AltRight: 'ALT GR', Enter: 'ENTER', Comma: ',', Period: '.',
    Slash: '/', Semicolon: ';', Quote: "'", BracketLeft: '[', BracketRight: ']', Backslash: '\\', Backquote: '`', CapsLock: 'CAPS',
  };
  if (names[code]) return names[code];
  if (code.startsWith('Key')) return code.slice(3);
  if (code.startsWith('Digit')) return code.slice(5);
  if (code.startsWith('Numpad')) return `NUM ${code.slice(6)}`;
  return code.toUpperCase();
}

export class Input {
  private keys = new Set<string>();
  private edges = new Set<keyof Controls>();
  private padPrev: boolean[] = [];
  private steerState = 0;
  private lastPad: Gamepad | null = null;
  private restartT = 0;
  private restartFired = false;
  usingGamepad = false;
  usingTouch = false;
  /** Player's speed (m/s), set by the game each frame: digital steering eases off at speed. */
  vehicleSpeed = 0;
  readonly touch: TouchState = { steer: 0, throttle: 0, brake: 0, nitro: false, handbrake: false };
  private stickPrev = { x: 0, y: 0 };
  bindings: Record<BindAction, string[]> = Input.loadBindings();
  /** Rebinding: the next key press goes here instead of the game. */
  private capture: ((code: string | null) => void) | null = null;

  /** For on-screen buttons and menus: fire a one-shot control. */
  press(edge: keyof Controls): void {
    this.edges.add(edge);
    this.edges.add('any');
  }

  constructor() {
    window.addEventListener('keydown', (e) => {
      if (this.capture) {
        e.preventDefault();
        if (e.repeat) return;
        const cb = this.capture;
        this.capture = null;
        cb(e.code === 'Escape' ? null : e.code);
        return;
      }
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space', 'Backspace', 'Tab'].includes(e.code) || this.isBound(e.code)) {
        e.preventDefault();
      }
      if (e.repeat) return;
      this.keys.add(e.code);
      const edge = EDGE_KEYS[e.code];
      if (edge) this.edges.add(edge);
      for (const [action, ctl] of Object.entries(EDGE_ACTIONS) as [BindAction, keyof Controls][]) {
        if (this.bindings[action].includes(e.code)) this.edges.add(ctl);
      }
      const nav = NAV_KEYS[e.code];
      if (nav) this.edges.add(nav);
      this.edges.add('any');
      this.usingGamepad = false;
    });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => this.keys.clear());
  }

  private static loadBindings(): Record<BindAction, string[]> {
    const out = structuredClone(DEFAULT_BINDINGS);
    try {
      const saved = JSON.parse(localStorage.getItem(BINDINGS_KEY) ?? '{}') as Partial<Record<BindAction, string[]>>;
      for (const k of Object.keys(out) as BindAction[]) {
        const v = saved[k];
        if (Array.isArray(v) && v.every((c) => typeof c === 'string')) out[k] = v.filter((c) => !RESERVED_KEYS.has(c));
      }
    } catch {
      // Corrupt or blocked storage: defaults.
    }
    return out;
  }

  private saveBindings(): void {
    try {
      localStorage.setItem(BINDINGS_KEY, JSON.stringify(this.bindings));
    } catch {
      // Storage blocked: the binding still holds for this session.
    }
  }

  private isBound(code: string): boolean {
    return Object.values(this.bindings).some((codes) => codes.includes(code));
  }

  /** Wait for the next key press and bind it to `action` (Escape cancels). */
  rebind(action: BindAction, done: (ok: boolean) => void): void {
    this.capture = (code) => {
      if (!code || RESERVED_KEYS.has(code)) {
        done(false);
        return;
      }
      // A key does one thing: take it away from whatever had it.
      for (const k of Object.keys(this.bindings) as BindAction[]) this.bindings[k] = this.bindings[k].filter((c) => c !== code);
      this.bindings[action] = [code];
      this.keys.clear();
      this.saveBindings();
      done(true);
    };
  }

  cancelRebind(): void {
    this.capture = null;
  }

  resetBindings(): void {
    this.bindings = structuredClone(DEFAULT_BINDINGS);
    this.saveBindings();
  }

  /** Short label of the control for an action on the device in use (for hints). */
  label(action: BindAction): string {
    if (this.usingTouch) {
      const t: Partial<Record<BindAction, string>> = { nitro: 'NITRO', handbrake: 'DRIFT', ramLeft: 'RAM', ramRight: 'RAM', bulletTime: 'SLOW', reset: '↺' };
      return t[action] ?? '';
    }
    if (this.usingGamepad) {
      const p: Record<BindAction, string> = {
        throttle: 'R2', brake: 'L2', left: 'stick', right: 'stick', handbrake: '✕/A', nitro: '○/B', bulletTime: 'L3/R3',
        ramLeft: 'L1', ramRight: 'R1', reset: '△/Y', lookBack: 'rechterstick ↓',
      };
      return p[action];
    }
    return [...new Set(this.bindings[action].map(keyName))].join('/') || '—';
  }

  private bound(action: BindAction): boolean {
    return this.bindings[action].some((c) => this.keys.has(c));
  }

  poll(dt: number): Controls {
    const c: Controls = {
      throttle: 0, brake: 0, steer: 0, handbrake: false, nitro: false, ramLeft: false, ramRight: false, ramAuto: false,
      lookBack: false, reset: false, bulletTime: false, restart: false, restartHold: 0, pause: false,
      mute: false, debug: false, nextTrack: false, volumeUp: false, volumeDown: false, confirm: false,
      navUp: false, navDown: false, navLeft: false, navRight: false, back: false, any: false,
    };

    // Digital steering (keyboard and touch buttons): eased in, and gentler at speed, so taps make
    // small corrections in town and the car doesn't dart around at 250 km/u.
    const left = this.bound('left') || this.touch.steer < 0;
    const right = this.bound('right') || this.touch.steer > 0;
    const speedT = Math.min(1, this.vehicleSpeed / 65);
    const target = ((right ? 1 : 0) - (left ? 1 : 0)) * (1 - 0.18 * speedT);
    const centering = target === 0 || Math.sign(target) !== Math.sign(this.steerState);
    const rate = centering ? 6.5 - 2 * speedT : 5 - 3 * speedT;
    this.steerState += Math.max(-rate * dt, Math.min(rate * dt, target - this.steerState));
    c.steer = this.steerState;
    c.throttle = this.bound('throttle') ? 1 : 0;
    c.brake = this.bound('brake') ? 1 : 0;
    c.handbrake = this.bound('handbrake');
    c.nitro = this.bound('nitro');
    c.lookBack = this.bound('lookBack');
    for (const e of this.edges) (c as unknown as Record<string, boolean>)[e] = true;
    this.edges.clear();

    // Touch buttons
    const t = this.touch;
    c.throttle = Math.max(c.throttle, t.throttle);
    c.brake = Math.max(c.brake, t.brake);
    c.nitro ||= t.nitro;
    c.handbrake ||= t.handbrake;

    // Gamepad
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const pad = Array.from(pads).find((p): p is Gamepad => !!p && p.connected) ?? null;
    this.lastPad = pad;
    let restartHeld = this.keys.has('KeyR');
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
      // Either stick click: L3 is awkward while you're steering with that same stick.
      c.bulletTime ||= pressed(PAD.l3) || pressed(PAD.r3);
      c.lookBack ||= (pad.axes[3] ?? 0) > 0.6;
      if (btn(PAD.select)) restartHeld = true;
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

    // Restart only after holding R / Select for a moment.
    if (restartHeld) {
      this.restartT += dt;
      if (this.restartT >= RESTART_HOLD && !this.restartFired) {
        this.restartFired = true;
        c.restart = true;
      }
    } else {
      this.restartT = 0;
      this.restartFired = false;
    }
    c.restartHold = this.restartFired ? 0 : Math.min(1, this.restartT / RESTART_HOLD);
    return c;
  }

  rumble(strong: number, weak: number, ms: number): void {
    const act = (this.lastPad as (Gamepad & { vibrationActuator?: { playEffect: (t: string, p: object) => Promise<unknown> } }) | null)
      ?.vibrationActuator;
    act?.playEffect('dual-rumble', { duration: ms, strongMagnitude: Math.min(1, strong), weakMagnitude: Math.min(1, weak) }).catch(() => {});
  }
}
