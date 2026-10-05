import type { GameAudio } from './Audio';

// Music player: title loop + race playlist, streamed from public/music/.
// Missing files are skipped silently, so the game works before the tracks exist.

export interface Track {
  file: string;
  title: string;
}

export const TITLE_TRACK: Track = { file: 'plaatsnaambord.mp3', title: 'Plaatsnaambord' };
export const RACE_TRACKS: Track[] = [
  { file: 'a35.mp3', title: 'A35' },
  { file: 'beuk-m-de-vangrail-in.mp3', title: "Beuk 'm de vangrail in" },
];

type Mode = 'off' | 'title' | 'race';

export class MusicPlayer {
  private el = new Audio();
  private filter: BiquadFilterNode | null = null;
  private gain: GainNode | null = null;
  private available = new Set<string>();
  private probed = false;
  private mode: Mode = 'off';
  private raceIndex = Math.floor(Math.random() * RACE_TRACKS.length);
  private current: Track | null = null;
  private muffled = false;
  volume = 0.7;
  /** Called when a track starts, for the "Nu speelt" toast. */
  onTrack: ((t: Track) => void) | null = null;

  constructor(private audio: GameAudio) {
    this.el.crossOrigin = 'anonymous';
    this.el.preload = 'auto';
    this.el.addEventListener('ended', () => {
      if (this.mode === 'race') this.next();
    });
    void this.probe();
  }

  private url(t: Track): string {
    return `${import.meta.env.BASE_URL}music/${t.file}`;
  }

  /** Find out which files exist (HEAD requests), once. */
  private async probe(): Promise<void> {
    const all = [TITLE_TRACK, ...RACE_TRACKS];
    await Promise.all(
      all.map(async (t) => {
        try {
          const r = await fetch(this.url(t), { method: 'HEAD' });
          const type = r.headers.get('content-type') ?? '';
          // Vite's dev server answers unknown paths with index.html, so check the type too.
          if (r.ok && !type.includes('text/html')) this.available.add(t.file);
        } catch {
          /* offline or missing: no music */
        }
      }),
    );
    this.probed = true;
    // Apply whatever mode was requested while probing.
    const m = this.mode;
    this.mode = 'off';
    if (m === 'title') this.playTitle();
    else if (m === 'race') this.playRace();
  }

  /** Re-apply the requested mode (e.g. once the AudioContext exists). */
  resume(): void {
    const m = this.mode;
    this.mode = 'off';
    this.current = null;
    if (m === 'title') this.playTitle();
    else if (m === 'race') this.playRace();
  }

  get hasMusic(): boolean {
    return this.available.size > 0;
  }

  private connect(): boolean {
    const ctx = this.audio.ctx;
    if (!ctx) return false;
    if (!this.gain) {
      const src = ctx.createMediaElementSource(this.el);
      this.filter = ctx.createBiquadFilter();
      this.filter.type = 'lowpass';
      this.filter.frequency.value = 20000;
      this.gain = ctx.createGain();
      this.gain.gain.value = this.volume;
      src.connect(this.filter).connect(this.gain).connect(this.audio.musicBus);
    }
    return true;
  }

  private play(t: Track, loop: boolean): void {
    if (!this.available.has(t.file) || !this.connect()) {
      this.current = null;
      this.el.pause();
      return;
    }
    if (this.current !== t) {
      this.el.src = this.url(t);
      this.current = t;
      this.onTrack?.(t);
    }
    this.el.loop = loop;
    void this.el.play().catch(() => {});
  }

  playTitle(): void {
    if (this.mode === 'title') return;
    this.mode = 'title';
    if (this.probed) this.play(TITLE_TRACK, true);
  }

  playRace(): void {
    if (this.mode === 'race') return;
    this.mode = 'race';
    if (!this.probed) return;
    const t = this.nextAvailableRace(0);
    if (t) this.play(t, false);
    else this.el.pause();
  }

  next(): void {
    if (this.mode !== 'race') return;
    const t = this.nextAvailableRace(1);
    if (t) {
      this.current = null; // force reload even if it's the same file
      this.play(t, false);
    }
  }

  private nextAvailableRace(step: number): Track | null {
    for (let i = 0; i < RACE_TRACKS.length; i++) {
      this.raceIndex = (this.raceIndex + (i === 0 ? step : 1)) % RACE_TRACKS.length;
      const t = RACE_TRACKS[this.raceIndex];
      if (this.available.has(t.file)) return t;
    }
    return null;
  }

  /** Muffled = heard "through a wall": pause menu and slow-motion moments. */
  setMuffled(m: boolean): void {
    if (m === this.muffled || !this.filter || !this.audio.ctx) return;
    this.muffled = m;
    const t = this.audio.ctx.currentTime;
    this.filter.frequency.setTargetAtTime(m ? 650 : 20000, t, 0.08);
    this.gain!.gain.setTargetAtTime(this.volume * (m ? 0.6 : 1), t, 0.08);
  }

  changeVolume(delta: number): number {
    this.volume = Math.min(1, Math.max(0, Math.round((this.volume + delta) * 10) / 10));
    if (this.gain && this.audio.ctx) this.gain.gain.setTargetAtTime(this.volume * (this.muffled ? 0.6 : 1), this.audio.ctx.currentTime, 0.05);
    return this.volume;
  }
}
