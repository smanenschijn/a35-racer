import type { Input } from '../core/Input';

// v2: auto-gas became the default; the old key stored '0' for everyone who played before.
const AUTO_GAS_KEY = 'a35-autogas2';

/**
 * On-screen controls for phones and tablets: steering pads on the left, a controller-style
 * diamond of action buttons on the right (nitro, brake, ram, drift; slow-mo in the corner) and
 * pause/reset/auto-gas at the edge. Auto-gas is on by default; turned off, a GAS pedal appears
 * beside the diamond. Multi-touch via pointer events; a finger can slide from one steering pad
 * to the other, or across the diamond, without lifting.
 */
export class TouchControls {
  readonly root = document.createElement('div');
  private held = new Map<number, string>();
  /** Auto-gas: throttle stays on unless you brake (no thumb pinned to GAS the whole race). */
  private autoGas = true;
  private autoBtn: HTMLButtonElement;

  constructor(private input: Input) {
    this.root.className = 'touch';
    this.root.innerHTML = `
      <button type="button" class="t-pause" data-k="pause" aria-label="Pauze">II</button>
      <button type="button" class="t-reset" data-k="reset" aria-label="Terug op de weg">↺</button>
      <button type="button" class="t-auto" data-k="auto" aria-label="Automatisch gas" aria-pressed="false">AUTO<br>GAS</button>
      <div class="t-left">
        <button type="button" data-k="left" aria-label="Links">◀</button>
        <button type="button" data-k="right" aria-label="Rechts">▶</button>
      </div>
      <button type="button" class="t-gas" data-k="gas" aria-label="Gas">GAS</button>
      <div class="t-pad">
        <button type="button" class="t-slow" data-k="slow" aria-label="Bullet time">SLOW</button>
        <button type="button" class="t-n" data-k="drift" aria-label="Handrem">DRIFT</button>
        <button type="button" class="t-w" data-k="brake" aria-label="Rem">REM</button>
        <button type="button" class="t-e" data-k="ram" aria-label="Rammen">RAM</button>
        <button type="button" class="t-s" data-k="nitro" aria-label="Nitro">NITRO</button>
      </div>`;
    document.body.appendChild(this.root);
    this.autoBtn = this.root.querySelector('[data-k="auto"]') as HTMLButtonElement;
    try {
      this.setAutoGas(localStorage.getItem(AUTO_GAS_KEY) !== '0');
    } catch {
      // Storage blocked: auto-gas stays on.
    }

    const keyAt = (x: number, y: number): HTMLElement | null => {
      const el = document.elementFromPoint(x, y) as HTMLElement | null;
      const b = el?.closest('[data-k]') as HTMLElement | null;
      return b && this.root.contains(b) ? b : null;
    };
    const down = (e: PointerEvent) => {
      const b = (e.target as HTMLElement).closest('[data-k]') as HTMLElement | null;
      if (!b) return;
      e.preventDefault();
      this.input.usingTouch = true;
      const k = b.dataset.k!;
      this.held.set(e.pointerId, k);
      if (k === 'pause') this.input.press('pause');
      if (k === 'reset') this.input.press('reset');
      if (k === 'slow') this.input.press('bulletTime');
      if (k === 'ram') this.input.press('ramAuto');
      if (k === 'auto') this.setAutoGas(!this.autoGas);
      this.sync();
    };
    // Sliding the thumb switches between the steering pads, or between the held diamond buttons
    // (e.g. from REM onto NITRO). Taps like RAM and SLOW only fire on a fresh press.
    const SLIDE = [['left', 'right'], ['brake', 'nitro', 'drift', 'gas']];
    const move = (e: PointerEvent) => {
      const k = this.held.get(e.pointerId);
      const group = SLIDE.find((g) => g.includes(k!));
      if (!group) return;
      const nk = keyAt(e.clientX, e.clientY)?.dataset.k;
      if (nk && nk !== k && group.includes(nk)) {
        this.held.set(e.pointerId, nk);
        this.sync();
      }
    };
    const up = (e: PointerEvent) => {
      if (!this.held.has(e.pointerId)) return;
      this.held.delete(e.pointerId);
      this.sync();
    };
    this.root.addEventListener('pointerdown', down);
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', up);
    this.root.addEventListener('contextmenu', (e) => e.preventDefault());
    this.enabled = 'ontouchstart' in window || matchMedia('(pointer: coarse)').matches;
    this.setVisible(false);
  }

  /** Only on touch devices. */
  enabled = false;

  setVisible(v: boolean): void {
    this.root.hidden = !(v && this.enabled);
  }

  private setAutoGas(on: boolean): void {
    this.autoGas = on;
    this.autoBtn.classList.toggle('on', on);
    this.autoBtn.setAttribute('aria-pressed', String(on));
    this.root.classList.toggle('autogas', on);
    try {
      localStorage.setItem(AUTO_GAS_KEY, on ? '1' : '0');
    } catch {
      // Storage blocked: the setting holds for this session.
    }
    this.sync();
  }

  private sync(): void {
    const keys = new Set(this.held.values());
    for (const b of this.root.querySelectorAll<HTMLElement>('[data-k]')) {
      if (b.dataset.k !== 'auto') b.classList.toggle('on', keys.has(b.dataset.k!));
    }
    const t = this.input.touch;
    t.steer = (keys.has('right') ? 1 : 0) - (keys.has('left') ? 1 : 0);
    t.brake = keys.has('brake') ? 1 : 0;
    t.throttle = keys.has('gas') || (this.autoGas && !t.brake) ? 1 : 0;
    t.nitro = keys.has('nitro');
    t.handbrake = keys.has('drift');
  }
}
