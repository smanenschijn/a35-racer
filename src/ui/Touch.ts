import type { Input } from '../core/Input';

/**
 * On-screen controls for phones and tablets: steering pads on the left, pedals on the right,
 * nitro/handbrake/ram buttons in between and a pause button. Multi-touch via pointer events.
 */
export class TouchControls {
  readonly root = document.createElement('div');
  private held = new Map<number, string>();

  constructor(private input: Input) {
    this.root.className = 'touch';
    this.root.innerHTML = `
      <button type="button" class="t-pause" data-k="pause" aria-label="Pauze">II</button>
      <div class="t-left">
        <button type="button" data-k="left" aria-label="Links">◀</button>
        <button type="button" data-k="right" aria-label="Rechts">▶</button>
      </div>
      <div class="t-mid">
        <button type="button" data-k="ramL" aria-label="Ram links">RAM◀</button>
        <button type="button" data-k="ramR" aria-label="Ram rechts">▶RAM</button>
        <button type="button" data-k="drift" aria-label="Handrem">DRIFT</button>
        <button type="button" data-k="nitro" aria-label="Nitro">NITRO</button>
      </div>
      <div class="t-right">
        <button type="button" data-k="brake" aria-label="Rem">REM</button>
        <button type="button" data-k="gas" aria-label="Gas">GAS</button>
      </div>`;
    document.body.appendChild(this.root);
    const down = (e: PointerEvent) => {
      const b = (e.target as HTMLElement).closest('[data-k]') as HTMLElement | null;
      if (!b) return;
      e.preventDefault();
      this.input.usingTouch = true;
      const k = b.dataset.k!;
      this.held.set(e.pointerId, k);
      b.classList.add('on');
      if (k === 'pause') this.input.press('pause');
      if (k === 'ramL') this.input.press('ramLeft');
      if (k === 'ramR') this.input.press('ramRight');
      this.sync();
    };
    const up = (e: PointerEvent) => {
      const k = this.held.get(e.pointerId);
      if (!k) return;
      this.held.delete(e.pointerId);
      this.root.querySelector(`[data-k="${k}"]`)?.classList.remove('on');
      this.sync();
    };
    this.root.addEventListener('pointerdown', down);
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

  private sync(): void {
    const keys = new Set(this.held.values());
    const t = this.input.touch;
    t.steer = (keys.has('right') ? 1 : 0) - (keys.has('left') ? 1 : 0);
    t.throttle = keys.has('gas') ? 1 : 0;
    t.brake = keys.has('brake') ? 1 : 0;
    t.nitro = keys.has('nitro');
    t.handbrake = keys.has('drift');
  }
}
