// Local highscores per stage (browser storage). Storage can be missing or throw (private
// windows, blocked site data), so every access is guarded and the game works without it.

export interface Score {
  initials: string;
  time: number; // seconds, penalties included
  takedowns: number;
  car: string;
  date: string;
}

const KEY = 'a35racer.highscores.v1';
const MAX = 5;

function readAll(): Record<string, Score[]> {
  try {
    return JSON.parse(localStorage.getItem(KEY) ?? '{}');
  } catch {
    return {};
  }
}

export function getScores(stage: string): Score[] {
  return readAll()[stage] ?? [];
}

/** Would this time make the top list? */
export function qualifies(stage: string, time: number): boolean {
  const list = getScores(stage);
  return list.length < MAX || time < list[list.length - 1].time;
}

/** Adds a score and returns its rank (1-based), or 0 if it didn't make the list. */
export function addScore(stage: string, score: Score): number {
  const all = readAll();
  const list = [...(all[stage] ?? []), score].sort((a, b) => a.time - b.time).slice(0, MAX);
  all[stage] = list;
  try {
    localStorage.setItem(KEY, JSON.stringify(all));
  } catch {
    /* not persisted, still shown this session */
  }
  return list.indexOf(score) + 1;
}

export function lastInitials(): string {
  try {
    return localStorage.getItem(KEY + '.initials') ?? 'AAA';
  } catch {
    return 'AAA';
  }
}

export function rememberInitials(i: string): void {
  try {
    localStorage.setItem(KEY + '.initials', i);
  } catch {
    /* ignore */
  }
}
