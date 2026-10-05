import type { Vehicle } from '../vehicle/Vehicle';

export type ImpactKind = 'car' | 'rail';

export interface GameEventMap {
  impact: { x: number; y: number; z: number; strength: number; kind: ImpactKind; a: Vehicle; b?: Vehicle };
  scrape: { x: number; y: number; z: number; intensity: number; vehicle: Vehicle; nx: number; nz: number };
  wreck: { victim: Vehicle; attacker: Vehicle | null };
  ram: { vehicle: Vehicle; dir: number };
  nearMiss: { vehicle: Vehicle; other: Vehicle };
  message: { text: string; color?: string; big?: boolean };
  flash: { kmh: number };
  busted: { penalty: number };
}

type Handler<T> = (payload: T) => void;

export class EventBus {
  private handlers: { [K in keyof GameEventMap]?: Handler<GameEventMap[K]>[] } = {};

  on<K extends keyof GameEventMap>(type: K, fn: Handler<GameEventMap[K]>): void {
    const list = (this.handlers[type] ??= []) as Handler<GameEventMap[K]>[];
    list.push(fn);
  }

  emit<K extends keyof GameEventMap>(type: K, payload: GameEventMap[K]): void {
    const list = this.handlers[type];
    if (list) for (const fn of list) fn(payload);
  }
}
