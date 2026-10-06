// Race announcer using the browser's speech synthesis with a Dutch voice (when available).
// Lines are short and rate-limited so it never talks over itself.

export class Announcer {
  private voice: SpeechSynthesisVoice | null = null;
  private last = 0;
  muted = false;
  enabled = typeof window !== 'undefined' && 'speechSynthesis' in window;

  constructor() {
    if (!this.enabled) return;
    const pick = () => {
      const voices = speechSynthesis.getVoices();
      this.voice = voices.find((v) => v.lang === 'nl-NL') ?? voices.find((v) => v.lang.startsWith('nl')) ?? null;
    };
    pick();
    speechSynthesis.addEventListener?.('voiceschanged', pick);
  }

  /** priority lines interrupt whatever is being said. */
  say(text: string, opts: { priority?: boolean; rate?: number; pitch?: number } = {}): void {
    if (!this.enabled || this.muted || !this.voice) return;
    const now = performance.now();
    if (!opts.priority && (speechSynthesis.speaking || now - this.last < 1200)) return;
    if (opts.priority) speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.voice = this.voice;
    u.lang = this.voice.lang;
    u.rate = opts.rate ?? 1.15;
    u.pitch = opts.pitch ?? 0.9;
    u.volume = 1;
    speechSynthesis.speak(u);
    this.last = now;
  }

  stop(): void {
    if (this.enabled) speechSynthesis.cancel();
  }
}
