import { CARS, RIVALS, type CarSpec } from '../config';
import type { Controls } from '../core/Input';
import { addScore, getScores, lastInitials, qualifies, rememberInitials, type Score } from '../core/Highscores';
import { clearedStages, isUnlocked, lifetime, UNLOCKS } from '../core/Progress';
import type { RaceResult } from '../game/Race';
import type { Stage } from '../track/Track';

export type MenuScreen =
  | 'title' | 'main' | 'stages' | 'cars' | 'scores' | 'stats' | 'controls' | 'pause' | 'initials' | 'results';

export interface MenuActions {
  startStage: (index: number, campaign: boolean) => void;
  nextStage: () => void;
  restartRace: () => void;
  resume: () => void;
  toMenu: () => void;
  chooseCar: (id: string) => void;
  /** Car shown in the showroom camera while browsing. */
  previewCar: (id: string) => void;
  sound: () => void;
}

export interface ResultExtras {
  campaign: boolean;
  campaignTotal: number;
  unlocked: string[];
}

const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const CAR_ORDER = ['rx', ...RIVALS];

/** Highscore table per stage (stage 5 keeps its original key). */
export const scoreKey = (stageId: number) => (stageId === 5 ? 'hengelo-enschede' : `etappe-${stageId}`);

const fmtTime = (t: number) => `${Math.floor(t / 60)}:${(t % 60).toFixed(2).padStart(5, '0')}`;

function bar(label: string, v: number): string {
  return `<div class="stat"><span>${label}</span><i><b style="width:${Math.round(Math.max(0.05, Math.min(1, v)) * 100)}%"></b></i></div>`;
}

/**
 * Arcade menus (DOM overlay). Driven by keyboard/gamepad navigation edges from Input,
 * and by taps/clicks directly on the items.
 */
export class Menu {
  readonly root = document.createElement('div');
  screen: MenuScreen | null = null;
  private index = 0;
  private items: { label: string; action: () => void; disabled?: boolean }[] = [];
  private carIndex = 0;
  private playerCar = 'rx';
  private initials = ['A', 'A', 'A'];
  private initialPos = 0;
  private pending: RaceResult | null = null;
  private extras: ResultExtras = { campaign: false, campaignTotal: 0, unlocked: [] };
  private lastRank = 0;
  private gamepad = false;
  private scoreStage = 5;
  private note = '';

  constructor(private a: MenuActions, private stages: Stage[]) {
    this.root.className = 'menu';
    document.body.appendChild(this.root);
    this.root.addEventListener('click', (e) => {
      const t = (e.target as HTMLElement).closest('[data-i],[data-act]') as HTMLElement | null;
      if (!t) {
        if (this.screen === 'title') this.open('main');
        return;
      }
      if (t.dataset.i !== undefined) {
        this.index = Number(t.dataset.i);
        const it = this.items[this.index];
        if (it && !it.disabled) it.action();
      } else this.act(t.dataset.act!);
    });
  }

  get isOpen(): boolean {
    return this.screen !== null;
  }

  setGamepad(on: boolean): void {
    if (on === this.gamepad) return;
    this.gamepad = on;
    if (this.screen === 'title') this.render();
  }

  open(screen: MenuScreen): void {
    this.screen = screen;
    this.index = 0;
    if (screen === 'cars') {
      this.carIndex = CAR_ORDER.indexOf(this.playerCar);
      this.a.previewCar(CAR_ORDER[this.carIndex]);
    } else if (screen === 'main' || screen === 'title' || screen === 'stages') {
      this.a.previewCar(this.playerCar);
    }
    this.render();
  }

  close(): void {
    this.screen = null;
    this.root.className = 'menu';
    this.root.innerHTML = '';
  }

  /** After a race: initials entry first when the time makes the highscores. */
  showResult(r: RaceResult, extras: ResultExtras): void {
    this.pending = r;
    this.extras = extras;
    this.lastRank = 0;
    const key = scoreKey(this.stages[r.stage].id);
    const finished = r.rows[r.position - 1]?.finished;
    if (!r.outOfTime && finished && r.qualified && qualifies(key, r.time)) {
      this.initials = lastInitials().padEnd(3, 'A').slice(0, 3).split('');
      this.initialPos = 0;
      this.open('initials');
    } else this.open('results');
  }

  private act(name: string): void {
    const ch = (d: number) => {
      const i = (LETTERS.indexOf(this.initials[this.initialPos]) + d + LETTERS.length) % LETTERS.length;
      this.initials[this.initialPos] = LETTERS[i];
      this.render();
    };
    switch (name) {
      case 'car-prev':
        return this.stepCar(-1);
      case 'car-next':
        return this.stepCar(1);
      case 'score-prev':
        return this.stepScores(-1);
      case 'score-next':
        return this.stepScores(1);
      case 'letter-up':
        return ch(1);
      case 'letter-down':
        return ch(-1);
      case 'letter-next':
        return this.nextLetter();
      default:
        if (name.startsWith('slot-')) {
          this.initialPos = Number(name.slice(5));
          this.render();
        }
    }
  }

  private stepCar(d: number): void {
    this.carIndex = (this.carIndex + d + CAR_ORDER.length) % CAR_ORDER.length;
    this.note = '';
    this.a.previewCar(CAR_ORDER[this.carIndex]);
    this.render();
  }

  private stepScores(d: number): void {
    this.scoreStage = ((this.scoreStage - 1 + d + 5) % 5) + 1;
    this.render();
  }

  private nextLetter(): void {
    if (this.initialPos < 2) {
      this.initialPos++;
      this.render();
      return;
    }
    const r = this.pending!;
    const initials = this.initials.join('');
    rememberInitials(initials);
    const score: Score = { initials, time: r.time, takedowns: r.takedowns, car: r.car, date: new Date().toISOString().slice(0, 10) };
    this.lastRank = addScore(scoreKey(this.stages[r.stage].id), score);
    this.open('results');
  }

  /** Feed navigation from the polled controls. */
  handle(c: Controls): boolean {
    if (!this.screen) return false;
    const s = this.screen;
    if (s === 'title') {
      if (c.confirm || c.any) this.open('main');
      return true;
    }
    if (s === 'cars') {
      if (c.navLeft) this.stepCar(-1);
      if (c.navRight) this.stepCar(1);
    }
    if (s === 'scores') {
      if (c.navLeft) this.stepScores(-1);
      if (c.navRight) this.stepScores(1);
    }
    if (s === 'initials') {
      if (c.navUp) this.act('letter-up');
      if (c.navDown) this.act('letter-down');
      if (c.navLeft && this.initialPos > 0) {
        this.initialPos--;
        this.render();
      }
      if (c.navRight || c.confirm) this.nextLetter();
      return true;
    }
    if (this.items.length) {
      if (c.navUp) this.move(-1);
      if (c.navDown) this.move(1);
      if (c.confirm) {
        const it = this.items[this.index];
        if (it && !it.disabled) it.action();
      }
    }
    if (c.back || (c.pause && s === 'pause')) {
      if (s === 'pause') this.a.resume();
      else if (s !== 'main' && s !== 'results') this.open('main');
    }
    return true;
  }

  private move(d: number): void {
    this.index = (this.index + d + this.items.length) % this.items.length;
    this.root.querySelectorAll('[data-i]').forEach((el, i) => el.classList.toggle('sel', i === this.index));
  }

  private list(items: { label: string; action: () => void; disabled?: boolean }[]): string {
    this.items = items;
    return `<div class="menu-items">${items
      .map((it, i) => `<button type="button" data-i="${i}" class="${i === this.index ? 'sel' : ''} ${it.disabled ? 'off' : ''}">${it.label}</button>`)
      .join('')}</div>`;
  }

  private stageLabel(st: Stage): string {
    return `Etappe ${st.id} · ${st.from} → ${st.to}`;
  }

  private render(): void {
    const s = this.screen;
    this.items = [];
    this.root.className = `menu show ${s}`;
    const logo = `<div class="logo"><span class="a35">A35</span><span class="racer">RACER</span></div>`;
    switch (s) {
      case 'title':
        this.root.innerHTML = `${logo}
          <div class="sub">Van Salland naar Twente · Raalte → Enschede</div>
          <div class="press">${this.gamepad ? 'Druk op ✕ / A' : matchMedia('(pointer: coarse)').matches ? 'Tik om te starten' : 'Druk op ENTER'}</div>`;
        break;
      case 'main': {
        const car = CARS[this.playerCar];
        this.root.innerHTML = `${logo}
          <div class="sub">Je rijdt de <b>${car.name}</b></div>
          ${this.list([
            { label: 'Racen', action: () => this.open('stages') },
            { label: 'Auto kiezen', action: () => this.open('cars') },
            { label: 'Highscores', action: () => this.open('scores') },
            { label: 'Statistieken', action: () => this.open('stats') },
            { label: 'Besturing', action: () => this.open('controls') },
            { label: 'Geluid aan/uit', action: () => this.a.sound() },
          ])}`;
        break;
      }
      case 'stages': {
        const cleared = clearedStages();
        this.root.innerHTML = `<div class="menu-title">Waar rijden we?</div>
          ${this.list([
            { label: 'Hele race · Raalte → Enschede', action: () => this.a.startStage(0, true) },
            ...this.stages.map((st, i) => ({
              label: `${this.stageLabel(st)}${cleared.includes(st.id) ? ' <em>✓</em>' : ''}`,
              action: () => this.a.startStage(i, false),
            })),
            { label: 'Terug', action: () => this.open('main') },
          ])}
          <div class="hint">Eindig bij de eerste drie om een etappe te halen. Elke gehaalde etappe speelt een nieuwe auto vrij.</div>`;
        break;
      }
      case 'cars': {
        const id = CAR_ORDER[this.carIndex];
        const c: CarSpec = CARS[id];
        const open = isUnlocked(id);
        const owner = id === this.playerCar ? 'Jouw auto' : `Normaal van ${c.driver}`;
        const lock = open ? '' : `<div class="lock">🔒 Haal etappe ${UNLOCKS[id]} om deze auto vrij te spelen</div>`;
        this.root.innerHTML = `
          <div class="menu-title">Kies je auto</div>
          <div class="car-pick">
            <button type="button" class="arrow" data-act="car-prev" aria-label="Vorige auto">‹</button>
            <div class="car-card ${open ? '' : 'locked'}">
              <div class="car-name">${c.name}</div>
              <div class="car-owner">${owner} · ${this.carIndex + 1}/${CAR_ORDER.length}</div>
              ${bar('Topsnelheid', (c.topSpeed - 60) / 12)}
              ${bar('Acceleratie', (c.accelFactor - 0.85) / 0.25)}
              ${bar('Gewicht', (c.mass - 1000) / 700)}
              ${bar('Grip', (c.gripFactor - 0.9) / 0.17)}
              ${lock}
            </div>
            <button type="button" class="arrow" data-act="car-next" aria-label="Volgende auto">›</button>
          </div>
          ${this.list([
            {
              label: open ? 'Deze nemen' : 'Nog op slot',
              disabled: !open,
              action: () => {
                this.playerCar = id;
                this.a.chooseCar(id);
                this.open('main');
              },
            },
            { label: 'Terug', action: () => this.open('main') },
          ])}
          <div class="hint">← → wisselen · je ruilt van auto met de coureur die hem normaal rijdt</div>`;
        break;
      }
      case 'scores': {
        const st = this.stages[this.scoreStage - 1];
        const rows = getScores(scoreKey(st.id));
        this.root.innerHTML = `
          <div class="menu-title">Highscores</div>
          <div class="car-pick"><button type="button" class="arrow" data-act="score-prev" aria-label="Vorige etappe">‹</button>
            <div class="sub">${this.stageLabel(st)}</div>
            <button type="button" class="arrow" data-act="score-next" aria-label="Volgende etappe">›</button></div>
          ${rows.length ? `<table><tr><th>#</th><th>Naam</th><th>Tijd</th><th>Takedowns</th><th>Auto</th></tr>
            ${rows.map((r, i) => `<tr class="${i + 1 === this.lastRank ? 'me' : ''}"><td>${i + 1}</td><td>${r.initials}</td><td>${fmtTime(r.time)}</td><td>${r.takedowns}</td><td>${r.car}</td></tr>`).join('')}
          </table>` : '<div class="sub">Nog geen tijden. Rij de eerste!</div>'}
          ${this.list([{ label: 'Terug', action: () => this.open('main') }])}`;
        break;
      }
      case 'stats': {
        const l = lifetime();
        const row = (k: string, v: string) => `<tr><td>${k}</td><td>${v}</td></tr>`;
        this.root.innerHTML = `
          <div class="menu-title">Statistieken</div>
          <table>
            ${row('Races gereden', String(l.races))}
            ${row('Gewonnen', String(l.wins))}
            ${row('Etappes gehaald', `${l.stagesCleared} van 5`)}
            ${row('Tegenstanders in de vangrail', String(l.takedowns))}
            ${row('Rakelings gepasseerd', String(l.nearMisses))}
            ${row('Topsnelheid', `${Math.round(l.topSpeed)} km/u`)}
            ${row('Hardste klap', `${Math.round(l.biggestHit * 3.6)} km/u`)}
            ${row('Bekeuringen', String(l.busted))}
            ${row('Total loss', String(l.wrecks))}
            ${row('Kilometers', l.km.toFixed(1))}
          </table>
          ${this.list([{ label: 'Terug', action: () => this.open('main') }])}`;
        break;
      }
      case 'controls':
        this.root.innerHTML = `
          <div class="menu-title">Besturing</div>
          <div class="controls">
            <div><b>↑ ↓ / W S</b> gas & rem</div><div><b>← → / A D</b> sturen</div>
            <div><b>SPATIE</b> handrem (drift)</div><div><b>SHIFT</b> nitro</div>
            <div><b>Q / E</b> ram links / rechts</div><div><b>⌫</b> terug op de weg</div>
            <div><b>ESC / P</b> pauze</div><div><b>R</b> opnieuw</div>
            <div><b>N</b> volgend nummer</div><div><b>− / +</b> muziekvolume</div>
          </div>
          <div class="tip">Gamepad: R2/L2 gas en rem, ✕ handrem, ○ nitro, L1/R1 rammen. Telefoon: knoppen op het scherm, liefst liggend.</div>
          <div class="tip">Op de N35 rijdt het tegenverkeer naast je: inhalen kan, maar kijk uit. Haal de checkpoints op tijd en eindig bij de eerste drie.</div>
          ${this.list([{ label: 'Terug', action: () => this.open('main') }])}`;
        break;
      case 'pause':
        this.root.innerHTML = `<div class="big-title">PAUZE</div>
          ${this.list([
            { label: 'Verder', action: () => this.a.resume() },
            { label: 'Opnieuw', action: () => this.a.restartRace() },
            { label: 'Naar menu', action: () => this.a.toMenu() },
          ])}`;
        break;
      case 'initials':
        this.root.innerHTML = `
          <div class="big-title">NIEUWE HIGHSCORE</div>
          <div class="sub">${fmtTime(this.pending!.time)} · zet je naam erbij</div>
          <div class="initials">${this.initials
            .map((l, i) => `<div class="slot ${i === this.initialPos ? 'sel' : ''}">
              ${i === this.initialPos ? '<button type="button" data-act="letter-up" aria-label="Letter omhoog">▲</button>' : ''}
              <span data-act="slot-${i}">${l}</span>
              ${i === this.initialPos ? '<button type="button" data-act="letter-down" aria-label="Letter omlaag">▼</button>' : ''}
            </div>`)
            .join('')}</div>
          <button type="button" class="ok" data-act="letter-next">${this.initialPos < 2 ? 'Volgende letter' : 'Opslaan'}</button>
          <div class="hint">↑ ↓ letter kiezen · → of ENTER verder</div>`;
        break;
      case 'results': {
        const r = this.pending!;
        const x = this.extras;
        const st = this.stages[r.stage];
        const last = r.stage >= this.stages.length - 1;
        const champion = x.campaign && last && r.qualified;
        const title = r.outOfTime ? 'TIJD OP!' : champion ? 'KAMPIOEN!' : r.position === 1 ? 'WINNAAR!' : 'FINISH';
        const verdict = r.outOfTime
          ? 'Je haalde het checkpoint niet op tijd. Gas geven!'
          : champion
            ? `Van Raalte tot Enschede in ${fmtTime(x.campaignTotal)}. Kump wal goed!`
            : r.qualified
              ? `${this.stageLabel(st)} gehaald: ${r.position}e plaats!`
              : `${r.position}e... Je moet bij de eerste drie eindigen, noaber!`;
        const unlocked = x.unlocked.length
          ? `<div class="unlock">Nieuwe auto vrijgespeeld: ${x.unlocked.map((c) => CARS[c].name).join(', ')}!</div>`
          : '';
        const items: { label: string; action: () => void }[] = [];
        if (r.qualified && !last) items.push({ label: `Volgende etappe: ${this.stages[r.stage + 1].from} → ${this.stages[r.stage + 1].to}`, action: () => this.a.nextStage() });
        items.push({ label: 'Opnieuw', action: () => this.a.restartRace() });
        items.push({ label: 'Naar menu', action: () => this.a.toMenu() });
        this.root.innerHTML = `
          <div class="big-title">${title}</div>
          <div class="sub">${verdict}${this.lastRank ? ` · ${this.lastRank}e in de highscores` : ''}${x.campaign && !champion ? (r.qualified ? ` · hele race tot nu toe ${fmtTime(x.campaignTotal)}` : ' · de hele race is voorbij') : ''}</div>
          ${unlocked}
          <table>
            <tr><th>#</th><th>Coureur</th><th>Auto</th><th>Tijd</th><th>Takedowns</th></tr>
            ${r.rows.map((row, i) => `<tr class="${row.isPlayer ? 'me' : ''}"><td>${i + 1}</td><td>${row.name}</td><td>${row.car}</td><td>${
              row.wrecked ? 'WRAK' : row.finished && row.time !== undefined ? fmtTime(row.time) + (row.penalty ? ` <em>(+${row.penalty}s)</em>` : '') : '—'
            }</td><td>${row.takedowns}</td></tr>`).join('')}
          </table>
          ${this.list(items)}`;
        break;
      }
    }
    if (this.note) this.root.insertAdjacentHTML('beforeend', `<div class="hint">${this.note}</div>`);
  }
}
