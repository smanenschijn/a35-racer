// Synthesized audio (Web Audio API): engine drone, crash bursts, rail scrape, ram whoosh.
// No sample files needed; real recorded sounds and music come in milestone 4.

export class GameAudio {
  private ctx: AudioContext | null = null;
  private master!: GainNode;
  private engineOsc: OscillatorNode[] = [];
  private engineGain!: GainNode;
  private engineFilter!: BiquadFilterNode;
  private scrapeGain!: GainNode;
  private scrapeFilter!: BiquadFilterNode;
  private noiseBuf!: AudioBuffer;
  muted = false;

  /** Must be called from a user gesture. */
  start(): void {
    if (this.ctx) {
      void this.ctx.resume();
      return;
    }
    const ctx = (this.ctx = new AudioContext());
    this.master = ctx.createGain();
    this.master.gain.value = this.muted ? 0 : 0.6;
    const comp = ctx.createDynamicsCompressor();
    this.master.connect(comp).connect(ctx.destination);

    // White noise buffer shared by crash/scrape.
    this.noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
    const data = this.noiseBuf.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;

    // Engine: two detuned saws + square sub through a lowpass.
    this.engineFilter = ctx.createBiquadFilter();
    this.engineFilter.type = 'lowpass';
    this.engineFilter.frequency.value = 900;
    this.engineFilter.Q.value = 4;
    this.engineGain = ctx.createGain();
    this.engineGain.gain.value = 0;
    this.engineFilter.connect(this.engineGain).connect(this.master);
    for (const [type, detune, gain] of [['sawtooth', 0, 0.35], ['sawtooth', 9, 0.3], ['square', -1200, 0.25]] as const) {
      const o = ctx.createOscillator();
      o.type = type;
      o.detune.value = detune;
      o.frequency.value = 60;
      const g = ctx.createGain();
      g.gain.value = gain;
      o.connect(g).connect(this.engineFilter);
      o.start();
      this.engineOsc.push(o);
    }

    // Scrape loop: band-passed noise.
    const scrape = ctx.createBufferSource();
    scrape.buffer = this.noiseBuf;
    scrape.loop = true;
    this.scrapeFilter = ctx.createBiquadFilter();
    this.scrapeFilter.type = 'bandpass';
    this.scrapeFilter.frequency.value = 2500;
    this.scrapeFilter.Q.value = 3;
    this.scrapeGain = ctx.createGain();
    this.scrapeGain.gain.value = 0;
    scrape.connect(this.scrapeFilter).connect(this.scrapeGain).connect(this.master);
    scrape.start();
  }

  setMuted(m: boolean): void {
    this.muted = m;
    if (this.ctx) this.master.gain.setTargetAtTime(m ? 0 : 0.6, this.ctx.currentTime, 0.05);
  }

  /** speed in m/s, throttle 0..1 */
  engine(speed: number, throttle: number, nitro: boolean, active: boolean): void {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    // Fake 5-speed gearbox: rpm saws up through each gear.
    const gearTop = [14, 26, 38, 52, 80];
    let gear = 0;
    while (gear < gearTop.length - 1 && speed > gearTop[gear]) gear++;
    const lo = gear === 0 ? 0 : gearTop[gear - 1];
    const ratio = Math.min(1, (speed - lo) / (gearTop[gear] - lo));
    const rpm = 0.25 + ratio * 0.75;
    const freq = 45 + rpm * 110 + gear * 6;
    for (const o of this.engineOsc) o.frequency.setTargetAtTime(freq, t, 0.04);
    this.engineFilter.frequency.setTargetAtTime(500 + throttle * 1400 + (nitro ? 1200 : 0), t, 0.05);
    this.engineGain.gain.setTargetAtTime(active ? 0.13 + throttle * 0.1 : 0.05, t, 0.08);
  }

  scrape(intensity: number): void {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.scrapeGain.gain.setTargetAtTime(intensity * 0.35, t, 0.03);
    this.scrapeFilter.frequency.setTargetAtTime(1800 + intensity * 2500, t, 0.05);
  }

  crash(strength: number): void {
    if (!this.ctx) return;
    const ctx = this.ctx;
    const t = ctx.currentTime;
    const vol = Math.min(1, strength / 18);
    const src = ctx.createBufferSource();
    src.buffer = this.noiseBuf;
    src.playbackRate.value = 0.6 + Math.random() * 0.3;
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.setValueAtTime(3500, t);
    f.frequency.exponentialRampToValueAtTime(300, t + 0.4);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.9 * vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.35 + vol * 0.3);
    src.connect(f).connect(g).connect(this.master);
    src.start(t, Math.random());
    src.stop(t + 0.8);
    // Low thump
    const o = ctx.createOscillator();
    o.frequency.setValueAtTime(120, t);
    o.frequency.exponentialRampToValueAtTime(40, t + 0.2);
    const og = ctx.createGain();
    og.gain.setValueAtTime(0.8 * vol, t);
    og.gain.exponentialRampToValueAtTime(0.001, t + 0.25);
    o.connect(og).connect(this.master);
    o.start(t);
    o.stop(t + 0.3);
  }

  whoosh(): void {
    if (!this.ctx) return;
    const ctx = this.ctx;
    const t = ctx.currentTime;
    const src = ctx.createBufferSource();
    src.buffer = this.noiseBuf;
    const f = ctx.createBiquadFilter();
    f.type = 'bandpass';
    f.Q.value = 1.5;
    f.frequency.setValueAtTime(400, t);
    f.frequency.exponentialRampToValueAtTime(2500, t + 0.2);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.4, t + 0.06);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.3);
    src.connect(f).connect(g).connect(this.master);
    src.start(t, Math.random());
    src.stop(t + 0.35);
  }

  beep(high: boolean): void {
    if (!this.ctx) return;
    const ctx = this.ctx;
    const t = ctx.currentTime;
    const o = ctx.createOscillator();
    o.type = 'square';
    o.frequency.value = high ? 1320 : 660;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.18, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + (high ? 0.6 : 0.25));
    o.connect(g).connect(this.master);
    o.start(t);
    o.stop(t + 0.7);
  }
}
