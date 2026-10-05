import type { Vehicle, Zone } from '../vehicle/Vehicle';

export interface StandingRow {
  name: string;
  car: string;
  isPlayer: boolean;
  wrecked: boolean;
  finished: boolean;
  time?: number;
  takedowns: number;
  penalty: number;
}

export interface HudState {
  player: Vehicle;
  position: number;
  total: number;
  rows: StandingRow[];
  distanceLeft: number;
  raceTime: number;
  stars: number;
  heat: number;
  sirenNear: boolean;
  bust: number;
}

const el = <K extends keyof HTMLElementTagNameMap>(tag: K, cls = '', html = ''): HTMLElementTagNameMap[K] => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html) e.innerHTML = html;
  return e;
};

const fmtTime = (t: number) => {
  const m = Math.floor(t / 60);
  const s = (t % 60).toFixed(2).padStart(5, '0');
  return `${m}:${s}`;
};

const zoneColor = (d: number) => {
  // green → yellow → red
  const h = Math.max(0, 120 - d * 1.2);
  return `hsl(${h}, 90%, ${d >= 100 ? 25 : 50}%)`;
};

export class Hud {
  readonly root = el('div', 'hud');
  private pos = el('div', 'hud-pos');
  private standings = el('div', 'hud-standings');
  private stage = el('div', 'hud-stage');
  private speed = el('div', 'hud-speed');
  private gaugeArc: SVGPathElement;
  private boostFill = el('div', 'boost-fill');
  private ramL = el('div', 'ram-ind', 'Q');
  private ramR = el('div', 'ram-ind', 'E');
  private zones: Record<Zone, SVGElement>;
  private dmgPct = el('div', 'dmg-pct');
  private messages = el('div', 'hud-messages');
  private overlay = el('div', 'overlay');
  private help = el('div', 'hud-help');
  private wanted = el('div', 'hud-wanted');
  private bustBar = el('div', 'bust', '<span>KLEMGEZET</span><div class="bust-fill"></div>');
  private policeGlow = el('div', 'police-glow');
  private flashEl = el('div', 'cam-flash');
  private nowPlaying = el('div', 'now-playing');
  private lastPos = 0;
  private lastStars = -1;

  constructor(parent: HTMLElement) {
    parent.appendChild(this.root);

    const tl = el('div', 'hud-tl');
    tl.append(this.pos, this.standings);

    const tr = el('div', 'hud-tr');
    tr.append(this.stage);

    // Speedometer
    const br = el('div', 'hud-br');
    br.innerHTML = `
      <svg class="gauge" viewBox="0 0 200 120">
        <path d="M20 110 A 80 80 0 0 1 180 110" class="gauge-bg"/>
        <path d="M20 110 A 80 80 0 0 1 180 110" class="gauge-fg"/>
      </svg>`;
    this.gaugeArc = br.querySelector('.gauge-fg') as SVGPathElement;
    const unit = el('div', 'hud-unit', 'KM/U');
    br.append(this.speed, unit);

    // Damage + boost
    const bl = el('div', 'hud-bl');
    bl.innerHTML = `
      <svg class="dmg" viewBox="0 0 60 110">
        <rect data-z="front" x="8" y="2" width="44" height="22" rx="8"/>
        <rect data-z="left" x="2" y="26" width="12" height="58" rx="4"/>
        <rect data-z="right" x="46" y="26" width="12" height="58" rx="4"/>
        <rect x="16" y="30" width="28" height="50" rx="4" class="dmg-cabin"/>
        <rect data-z="rear" x="8" y="86" width="44" height="22" rx="8"/>
      </svg>`;
    const q = (z: Zone) => bl.querySelector(`[data-z="${z}"]`) as SVGElement;
    this.zones = { front: q('front'), rear: q('rear'), left: q('left'), right: q('right') };
    const side = el('div', 'hud-bl-side');
    const boost = el('div', 'boost', '<span class="boost-label">NITRO</span>');
    boost.append(this.boostFill);
    const rams = el('div', 'rams');
    rams.append(this.ramL, el('span', 'ram-label', 'RAM'), this.ramR);
    side.append(el('div', 'dmg-label', 'SCHADE'), this.dmgPct, boost, rams);
    bl.append(side);

    const top = el('div', 'hud-top');
    top.append(this.wanted, this.bustBar);
    this.root.append(this.policeGlow, this.flashEl, top, this.nowPlaying);

    this.help.innerHTML =
      '↑↓ / WS gas-rem &nbsp;·&nbsp; ←→ / AD sturen &nbsp;·&nbsp; SPATIE handrem &nbsp;·&nbsp; SHIFT nitro &nbsp;·&nbsp; Q/E rammen &nbsp;·&nbsp; ⌫ terug op weg &nbsp;·&nbsp; R herstart &nbsp;·&nbsp; M geluid &nbsp;·&nbsp; N volgend nummer &nbsp;·&nbsp; −/+ muziekvolume';

    this.root.append(tl, tr, br, bl, this.messages, this.help, this.overlay);
  }

  update(h: HudState): void {
    const { player, position, total, rows, distanceLeft, raceTime } = h;
    if (h.stars !== this.lastStars) {
      this.lastStars = h.stars;
      this.wanted.innerHTML = Array.from({ length: 5 }, (_, i) => `<span class="${i < h.stars ? 'on' : ''}">★</span>`).join('');
      this.wanted.classList.toggle('active', h.stars > 0);
    }
    this.wanted.style.setProperty('--next', `${(h.heat % 1) * 100}%`);
    this.policeGlow.classList.toggle('on', h.sirenNear && h.stars > 0);
    this.bustBar.classList.toggle('show', h.bust > 0.02);
    (this.bustBar.lastElementChild as HTMLElement).style.width = `${h.bust * 100}%`;
    const kmh = Math.round(player.speed * 3.6);
    this.speed.textContent = String(kmh);
    const frac = Math.min(1, kmh / 300);
    this.gaugeArc.style.strokeDasharray = `${frac * 252} 400`;
    this.gaugeArc.classList.toggle('nitro', player.nitroActive);

    if (position !== this.lastPos) {
      this.pos.innerHTML = `<span class="label">POSITIE</span><b>${position}</b><small>/${total}</small>`;
      this.pos.classList.remove('pop');
      void this.pos.offsetWidth;
      this.pos.classList.add('pop');
      this.lastPos = position;
    }
    this.standings.innerHTML = rows
      .map((r, i) => `<div class="row ${r.isPlayer ? 'me' : ''} ${r.wrecked ? 'out' : ''}"><span>${i + 1}</span>${r.name}${r.wrecked ? ' <em>WRAK</em>' : ''}</div>`)
      .join('');

    this.stage.innerHTML = `<div class="stage-name">ETAPPE 5/5 · HENGELO → ENSCHEDE</div>
      <div class="stage-info"><span>${(Math.max(0, distanceLeft) / 1000).toFixed(2)} km</span><span>${fmtTime(raceTime)}</span></div>`;

    for (const z of Object.keys(this.zones) as Zone[]) this.zones[z].style.fill = zoneColor(player.damage[z]);
    const maxD = player.wreckLevel;
    this.dmgPct.textContent = `${Math.round(maxD)}%`;
    this.dmgPct.classList.toggle('critical', maxD > 75);
    this.boostFill.style.width = `${player.nitro * 100}%`;
    this.boostFill.classList.toggle('active', player.nitroActive);
    this.boostFill.classList.toggle('full', player.nitro > 0.99);
    const ready = player.ramCooldown <= 0;
    this.ramL.classList.toggle('ready', ready);
    this.ramR.classList.toggle('ready', ready);
  }

  message(text: string, color = '#ffd400', big = false, duration = 1.4): void {
    const m = el('div', `msg ${big ? 'big' : ''}`, text);
    m.style.color = color;
    m.style.animationDuration = `${duration}s`;
    this.messages.appendChild(m);
    while (this.messages.children.length > 4) this.messages.firstElementChild?.remove();
    setTimeout(() => m.remove(), duration * 1000);
  }

  showTitle(gamepad: boolean): void {
    this.overlay.className = 'overlay show title';
    this.overlay.innerHTML = `
      <div class="logo"><span class="a35">A35</span><span class="racer">RACER</span></div>
      <div class="sub">Mijlpaal 2 · verkeer, politie & muziek · Hengelo → Enschede</div>
      <div class="press">${gamepad ? 'Druk op ✕ / A' : 'Druk op ENTER'} om te starten</div>
      <div class="controls">
        <div><b>↑ ↓ / W S</b> gas & rem</div>
        <div><b>← → / A D</b> sturen</div>
        <div><b>SPATIE</b> handrem (drift)</div>
        <div><b>SHIFT</b> nitro</div>
        <div><b>Q / E</b> ram links / rechts</div>
        <div><b>⌫</b> terug op de weg</div>
        <div><b>N</b> volgend nummer</div>
        <div><b>− / +</b> muziekvolume</div>
        <div><b>M</b> geluid aan/uit</div>
      </div>
      <div class="tip">Duw ze de vangrail in. Nitro vul je door te beuken, rakelings te passeren en te driften. Te veel chaos of te hard langs een flitspaal? Dan komt de politie.</div>`;
  }

  showPause(on: boolean): void {
    if (!on) {
      this.hideOverlay();
      return;
    }
    this.overlay.className = 'overlay show pause';
    this.overlay.innerHTML = `<div class="big-title">PAUZE</div><div class="press">ESC om verder te gaan · R om te herstarten</div>`;
  }

  showResults(rows: StandingRow[], playerPos: number): void {
    this.overlay.className = 'overlay show results';
    const verdict = playerPos <= 3 ? `Gas geaven! Je bent ${playerPos}e geworden.` : `${playerPos}e... Dat mot beter, noaber!`;
    this.overlay.innerHTML = `
      <div class="big-title">${playerPos === 1 ? 'WINNAAR!' : 'FINISH'}</div>
      <div class="sub">${verdict}</div>
      <table>
        <tr><th>#</th><th>Coureur</th><th>Auto</th><th>Tijd</th><th>Takedowns</th></tr>
        ${rows
          .map(
            (r, i) => `<tr class="${r.isPlayer ? 'me' : ''}"><td>${i + 1}</td><td>${r.name}</td><td>${r.car}</td><td>${
              r.wrecked ? 'WRAK' : r.finished && r.time !== undefined ? fmtTime(r.time) + (r.penalty ? ` <em>(+${r.penalty}s)</em>` : '') : '—'
            }</td><td>${r.takedowns}</td></tr>`,
          )
          .join('')}
      </table>
      <div class="press">R / SELECT om opnieuw te rijden</div>`;
  }

  hideOverlay(): void {
    this.overlay.className = 'overlay';
    this.overlay.innerHTML = '';
  }

  /** A rival talking trash: smaller, subtitle-style. */
  taunt(name: string, text: string): void {
    const m = el('div', 'msg taunt', `<b>${name}</b> “${text}”`);
    m.style.animationDuration = '2.2s';
    this.messages.appendChild(m);
    setTimeout(() => m.remove(), 2200);
  }

  /** Speed camera flash. */
  flash(): void {
    this.flashEl.classList.remove('go');
    void this.flashEl.offsetWidth;
    this.flashEl.classList.add('go');
  }

  showNowPlaying(title: string): void {
    this.nowPlaying.innerHTML = `<span>♪ Nu speelt</span>${title}`;
    this.nowPlaying.classList.remove('show');
    void this.nowPlaying.offsetWidth;
    this.nowPlaying.classList.add('show');
  }

  countdown(text: string, go = false): void {
    const m = el('div', `countdown ${go ? 'go' : ''}`, text);
    this.messages.appendChild(m);
    setTimeout(() => m.remove(), 900);
  }

  setHelpVisible(v: boolean): void {
    this.help.style.opacity = v ? '1' : '0';
  }

  setVisible(v: boolean): void {
    this.root.classList.toggle('hidden-hud', !v);
  }
}
