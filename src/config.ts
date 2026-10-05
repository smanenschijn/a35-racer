// Central tuning values. Everything here is exposed in the debug panel (press T).

export const tuning = {
  // Handling
  engineAccel: 11, // m/s² at standstill
  brakeDecel: 18,
  dragCoef: 0.0016, // aerodynamic drag factor (per m)
  rollingDecel: 0.6,
  grip: 7.5, // lateral velocity damping (1/s)
  handbrakeGrip: 1.3,
  driftGripFactor: 0.65, // grip multiplier while already sliding (keeps drifts alive)
  steerRateLow: 1.4, // max yaw rate (rad/s) at low speed
  steerRateHigh: 0.52, // max yaw rate (rad/s) at top speed
  yawResponse: 4, // how fast yaw rate follows steering (1/s)
  handbrakeYawBoost: 1.55,

  // Nitro
  nitroAccel: 9,
  nitroTopSpeedFactor: 1.22,
  nitroDrain: 0.28, // per second
  nitroFillPerDamage: 0.006,
  nitroFillTakedown: 0.35,
  nitroFillNearMiss: 0.08,
  nitroFillDriftPerSec: 0.16,

  // Ram attack
  ramSideSpeed: 12, // m/s lateral velocity during ram
  ramDuration: 0.32,
  ramCooldown: 2,
  ramMassFactor: 2.5, // rammer counts as this much heavier during a hit
  aggressorRecoil: 0.65, // share of the impulse the aggressor does NOT feel (keeps its line)
  ramDamageFactor: 1.4,
  ramShoveSpeed: 11, // m/s sideways a rammed car gets launched with
  ramDamage: 30, // damage points a landed ram deals to the victim

  // Collisions & damage
  carRestitution: 0.1,
  carFriction: 0.35,
  railRestitution: 0.06,
  railGlide: 8, // how fast the car straightens along a rail it touches (1/s)
  railFriction: 0.25, // fraction of tangential speed lost per hard hit
  damagePerImpulse: 0.0008, // damage points per N·s of impulse
  railDamagePerSpeed: 1.8, // damage points per m/s of normal impact speed
  railScrapeDamage: 0.03, // damage points per m/s per second while scraping
  takedownWindow: 2, // seconds a hit counts as cause for a rail wreck
  takedownRailBonus: 1.2, // rail damage multiplier when recently rammed by someone
  playerDamageFactor: 0.6,
  aiDamageFactor: 1.0,
  stunTime: 0.45,
  wreckTotal: 45, // average damage over all zones that also means total loss // seconds of reduced control after a hard hit

  // AI
  aiCornerLatAccel: 13,
  aiAggression: 1,
  rubberBandBehind: 1.08, // power factor when far behind the player
  rubberBandAhead: 0.96, // power factor when far ahead of the player

  // Camera
  camDistance: 7.2,
  camHeight: 2.6,
  camFov: 68,
  camFovNitro: 84,

  // Debug
  showColliders: false,
};

export type Tuning = typeof tuning;

export interface CarSpec {
  id: string;
  name: string;
  driver: string;
  color: number;
  mass: number; // kg
  length: number;
  width: number;
  topSpeed: number; // m/s
  accelFactor: number;
  gripFactor: number;
  // Visual shape
  bodyHeight: number;
  cabinLength: number;
  cabinOffset: number; // + forward
  cabinHeight: number;
  hatch: boolean;
  spoiler: boolean;
  plate: string;
}

export const CARS: Record<string, CarSpec> = {
  rx: {
    id: 'rx', name: 'Mazdo RX-Zeven', driver: 'Jij', color: 0xd81e1e,
    mass: 1250, length: 4.3, width: 1.78, topSpeed: 69, accelFactor: 1.0, gripFactor: 1.0,
    bodyHeight: 0.52, cabinLength: 1.8, cabinOffset: -0.25, cabinHeight: 0.46, hatch: false, spoiler: true, plate: 'A35-RX-7',
  },
  golv: {
    id: 'golv', name: 'Wolfsburg Golv G60', driver: 'Henk-Jan', color: 0x1d4fd8,
    mass: 1150, length: 4.0, width: 1.72, topSpeed: 67, accelFactor: 1.05, gripFactor: 1.0,
    bodyHeight: 0.6, cabinLength: 2.0, cabinOffset: -0.45, cabinHeight: 0.55, hatch: true, spoiler: false, plate: 'HJ-60-G',
  },
  volvi: {
    id: 'volvi', name: 'Volvi 240 Kombi', driver: 'Gerrit', color: 0x24563a,
    mass: 1650, length: 4.8, width: 1.76, topSpeed: 64, accelFactor: 0.9, gripFactor: 0.95,
    bodyHeight: 0.66, cabinLength: 2.7, cabinOffset: -0.55, cabinHeight: 0.6, hatch: true, spoiler: false, plate: 'GR-24-OE',
  },
  supremo: {
    id: 'supremo', name: 'Toyoda Supremo', driver: 'Sanne', color: 0xf2c014,
    mass: 1400, length: 4.5, width: 1.82, topSpeed: 70, accelFactor: 1.03, gripFactor: 1.05,
    bodyHeight: 0.5, cabinLength: 1.9, cabinOffset: -0.3, cabinHeight: 0.44, hatch: false, spoiler: true, plate: 'SN-53-NE',
  },
};

export interface AIPersonality {
  skill: number; // 0..1, affects cornering speed and line
  aggression: number; // 0..1, likelihood of ramming/blocking
  taunts: string[];
}

export const AI_PERSONALITIES: Record<string, AIPersonality> = {
  golv: { skill: 0.85, aggression: 0.9, taunts: ['Ik zal di wal kriegen!', 'Wat mot dat noe?'] },
  volvi: { skill: 0.7, aggression: 0.6, taunts: ['Aan de kaante, noaber!', 'Kump wal goed!'] },
  supremo: { skill: 1.0, aggression: 0.2, taunts: ['Gas geaven!', 'Tot in Enschede!'] },
};

// Road cross-section (meters). d is the lateral offset, positive to the right of travel.
export const ROAD = {
  halfWidth: 5.5, // our carriageway: railing at ±5.5
  laneCenters: [-2.75, 0.75], // left lane, right lane (vluchtstrook ≈ 4.0)
  medianWidth: 3,
  oppositeWidth: 11,
  sampleSpacing: 1, // meters between track samples
};
