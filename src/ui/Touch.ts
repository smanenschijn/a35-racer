import type { Input } from '../core/Input';

const AUTO_GAS_KEY = 'a35-autogas';

/**
 * On-screen controls for phones and tablets: steering pads on the left, pedals on the right,
 * nitro/handbrake/ram buttons in between and a pause button. Multi-touch via pointer events;
 * a finger can slide from one steering pad to the other without lifting.
 */
export class TouchControls {
  readonly root = document.createElement('div');
  private held = new Map<number, string>();
  /** Auto-gas: throttle stays on unless you brake (no thumb pinned to GAS the whole race). */
  private autoGas = false;
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
      <div class="t-mid">
        <button type="button" data-k="ram" aria-label="Rammen">RAM</button>
        <button type="button" data-k="drift" aria-label="Handrem">DRIFT</button>
        <button type="button" data-k="nitro" aria-label="Nitro">NITRO</button>
        <button type="button" data-k="slow" aria-label="Bullet time">SLOW</button>
      </div>
      <div class="t-right">
        <button type="button" data-k="brake" aria-label="Rem">REM</button>
        <button type="button" data-k="gas" aria-label="Gas">GAS</button>
      </div>`;
    document.body.appendChild(this.root);
    this.autoBtn = this.root.querySelector('[data-k="auto"]') as HTMLButtonElement;
    try {
      this.setAutoGas(localStorage.getItem(AUTO_GAS_KEY) === '1');
    } catch {
      // Storage blocked: auto-gas starts off.
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
    // Steering: sliding the thumb across to the other pad switches direction.
    const move = (e: PointerEvent) => {
      const k = this.held.get(e.pointerId);
      if (k !== 'left' && k !== 'right') return;
      const b = keyAt(e.clientX, e.clientY);
      const nk = b?.dataset.k;
      if ((nk === 'left' || nk === 'right') && nk !== k) {
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
