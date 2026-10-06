// Campaign progress, car unlocks and lifetime statistics (browser storage, guarded).
import type { RaceStats } from '../game/Race';

const KEY = 'a35racer.progress.v1';

export interface Lifetime {
  races: number;
  wins: number;
  stagesCleared: number;
  takedowns: number;
  nearMisses: number;
  topSpeed: number;
  biggestHit: number;
  busted: number;
  wrecks: number;
  km: number;
}

interface Saved {
  cleared: number[]; // stage ids (1..5) finished in the top 3
  stats: Lifetime;
}

const empty = (): Saved => ({
  cleared: [],
  stats: { races: 0, wins: 0, stagesCleared: 0, takedowns: 0, nearMisses: 0, topSpeed: 0, biggestHit: 0, busted: 0, wrecks: 0, km: 0 },
});

function read(): Saved {
  try {
    const s = JSON.parse(localStorage.getItem(KEY) ?? 'null');
    return s ? { ...empty(), ...s, stats: { ...empty().stats, ...s.stats } } : empty();
  } catch {
    return empty();
  }
}

function write(s: Saved): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(s));
  } catch {
    /* not persisted */
  }
}

/** Cars you start with; the others unlock by clearing a stage. */
export const UNLOCKS: Record<string, number> = {
  rx: 0, golv: 0, corso: 0, civik: 1, volvi: 2, spacewagen: 3, calibro: 4, supremo: 5,
};

export function isUnlocked(carId: string): boolean {
  const need = UNLOCKS[carId] ?? 0;
  return need === 0 || read().cleared.includes(need);
}

export function clearedStages(): number[] {
  return read().cleared;
}

export function lifetime(): Lifetime {
  return read().stats;
}

/** Record a race; returns the car ids that just got unlocked. */
export function recordRace(stageId: number, position: number, qualified: boolean, takedowns: number, r: RaceStats): string[] {
  const s = read();
  const before = Object.keys(UNLOCKS).filter((c) => UNLOCKS[c] === 0 || s.cleared.includes(UNLOCKS[c]));
  const st = s.stats;
  st.races++;
  if (position === 1 && qualified) st.wins++;
  if (qualified && !s.cleared.includes(stageId)) {
    s.cleared.push(stageId);
    st.stagesCleared = s.cleared.length;
  }
  st.takedowns += takedowns;
  st.nearMisses += r.nearMisses;
  st.topSpeed = Math.max(st.topSpeed, r.topSpeed);
  st.biggestHit = Math.max(st.biggestHit, r.biggestHit);
  st.busted += r.busted;
  st.wrecks += r.wrecks;
  st.km += r.distance / 1000;
  write(s);
  const after = Object.keys(UNLOCKS).filter((c) => UNLOCKS[c] === 0 || s.cleared.includes(UNLOCKS[c]));
  return after.filter((c) => !before.includes(c));
}
