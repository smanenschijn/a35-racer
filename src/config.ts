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

  // Traffic & police
  trafficCount: 26,
  oncomingCount: 14,
  heatDecayDelay: 6, // seconds without trouble before the wanted level starts dropping
  heatDecay: 0.09, // stars per second
  speedCameraKmh: 140,
  bustSeconds: 1.4, // how long the police must pin you down
  bustPenalty: 5, // seconds per wanted star

  // Camera
  camDistance: 7.2,
  camHeight: 2.6,
  camFov: 68,
  camFovNitro: 84,

  // Debug
  showColliders: false,
};

export type Tuning = typeof tuning;

export type VehicleKind = 'car' | 'van' | 'truck';
export type Livery = 'plain' | 'police' | 'delivery';

export interface CarSpec {
  id: string;
  name: string;
  driver: string;
  color: number;
  mass: number; // kg
  length: number; // body length of the car itself (a towed caravan comes on top)
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
  kind?: VehicleKind;
  livery?: Livery;
  stripeColor?: number; // racing stripes over bonnet and roof
  roofColor?: number;
  armor?: number; // damage multiplier (lower = tougher)
  trailerLength?: number; // towed caravan length (traffic)
  trailerText?: string; // lettering on a truck trailer
  model?: string; // detailed Blender model in public/models/<model>.glb
}

/** Physics length including a towed caravan. */
export const totalLength = (s: CarSpec) => s.length + (s.trailerLength ? s.trailerLength + 0.9 : 0);

type Shape = Pick<CarSpec, 'bodyHeight' | 'cabinLength' | 'cabinOffset' | 'cabinHeight' | 'hatch' | 'spoiler'>;
const coupe: Shape = { bodyHeight: 0.52, cabinLength: 1.8, cabinOffset: -0.25, cabinHeight: 0.46, hatch: false, spoiler: true };

export const CARS: Record<string, CarSpec> = {
  rx: {
    id: 'rx', name: 'Mazdo RX-Zeven', driver: 'Jij', color: 0xd81e1e,
    mass: 1250, length: 4.3, width: 1.78, topSpeed: 69, accelFactor: 1.0, gripFactor: 1.0,
    ...coupe, plate: 'A35-RX-7', model: 'rx7',
  },
  supremo: {
    id: 'supremo', name: 'Toyoda Supremo', driver: 'Sanne', color: 0xf2c014,
    mass: 1400, length: 4.5, width: 1.82, topSpeed: 70, accelFactor: 1.03, gripFactor: 1.05,
    bodyHeight: 0.5, cabinLength: 1.9, cabinOffset: -0.3, cabinHeight: 0.44, hatch: false, spoiler: true, plate: 'SN-53-NE',
  },
  golv: {
    id: 'golv', name: 'Wolfsburg Golv G60', driver: 'Henk-Jan', color: 0x1d4fd8,
    mass: 1150, length: 4.0, width: 1.72, topSpeed: 67, accelFactor: 1.05, gripFactor: 1.0,
    bodyHeight: 0.6, cabinLength: 2.0, cabinOffset: -0.45, cabinHeight: 0.55, hatch: true, spoiler: false, plate: 'HJ-60-G',
  },
  civik: {
    id: 'civik', name: 'Hondo Civik', driver: 'Joost', color: 0x8fd3ff,
    mass: 1080, length: 4.1, width: 1.7, topSpeed: 68, accelFactor: 1.08, gripFactor: 0.98,
    bodyHeight: 0.54, cabinLength: 1.9, cabinOffset: -0.35, cabinHeight: 0.48, hatch: true, spoiler: true, plate: 'UT-01-JO',
  },
  corso: {
    id: 'corso', name: 'Opal Corso', driver: 'Mehmet', color: 0xff6a00,
    mass: 1050, length: 3.9, width: 1.66, topSpeed: 66, accelFactor: 1.06, gripFactor: 1.0,
    bodyHeight: 0.58, cabinLength: 1.9, cabinOffset: -0.4, cabinHeight: 0.52, hatch: true, spoiler: false, plate: 'TB-24-7',
    livery: 'delivery',
  },
  spacewagen: {
    id: 'spacewagen', name: 'Mitsubushi Space Wagen', driver: 'Tante Riek', color: 0xb03a7a,
    mass: 1450, length: 4.6, width: 1.76, topSpeed: 64, accelFactor: 0.95, gripFactor: 0.93,
    bodyHeight: 0.8, cabinLength: 3.0, cabinOffset: -0.2, cabinHeight: 0.62, hatch: true, spoiler: false, plate: 'RK-19-AL',
  },
  calibro: {
    id: 'calibro', name: 'Opal Calibro', driver: 'Bennie', color: 0x111111,
    mass: 1300, length: 4.5, width: 1.76, topSpeed: 68, accelFactor: 1.0, gripFactor: 1.0,
    bodyHeight: 0.5, cabinLength: 1.9, cabinOffset: -0.3, cabinHeight: 0.45, hatch: false, spoiler: false, plate: 'HE-18-AC',
    stripeColor: 0xf5f5f5,
  },
  volvi: {
    id: 'volvi', name: 'Volvi 240 Kombi', driver: 'Gerrit', color: 0x24563a,
    mass: 1650, length: 4.8, width: 1.76, topSpeed: 64, accelFactor: 0.9, gripFactor: 0.95,
    bodyHeight: 0.66, cabinLength: 2.7, cabinOffset: -0.55, cabinHeight: 0.6, hatch: true, spoiler: false, plate: 'GR-24-OE',
    armor: 0.85,
  },
};

/** The seven rivals, in grid order (front to back). The player starts last. */
export const RIVALS = ['supremo', 'golv', 'civik', 'corso', 'calibro', 'volvi', 'spacewagen'];

export const POLICE_CAR: CarSpec = {
  id: 'police', name: 'Politie Volvi V70', driver: 'Politie', color: 0xf4f6f8,
  mass: 1700, length: 4.8, width: 1.8, topSpeed: 73, accelFactor: 1.1, gripFactor: 1.05,
  bodyHeight: 0.64, cabinLength: 2.6, cabinOffset: -0.5, cabinHeight: 0.56, hatch: true, spoiler: false, plate: 'POL-112',
  livery: 'police', armor: 0.7,
};

export interface AIPersonality {
  skill: number; // 0..1, affects cornering speed and line
  aggression: number; // 0..1, likelihood of ramming/blocking
  /** 0..1: how much this driver singles out the player. */
  playerFocus: number;
  /** Seconds between lane changes when weaving through traffic (lower = twitchier). */
  laneChangeDelay: number;
  /** Meters ahead that the driver looks for slower traffic (lower = reckless). */
  awareness: number;
  /** Random brake taps (Tante Riek). */
  erratic: number;
  /** Prefers shunting the car in front instead of overtaking (Bennie). */
  shunter: boolean;
  taunts: string[];
}

const base: Omit<AIPersonality, 'skill' | 'aggression' | 'taunts'> = {
  playerFocus: 0.5, laneChangeDelay: 1.5, awareness: 30, erratic: 0, shunter: false,
};

export const AI_PERSONALITIES: Record<string, AIPersonality> = {
  supremo: { ...base, skill: 1.0, aggression: 0.15, awareness: 40, taunts: ['Gas geaven!', 'Tot in Enschede!'] },
  golv: { ...base, skill: 0.85, aggression: 0.9, playerFocus: 1, taunts: ['Ik zal di wal kriegen!', 'Wat mot dat noe?'] },
  civik: { ...base, skill: 0.8, aggression: 0.5, awareness: 14, laneChangeDelay: 1, taunts: ['Tentamen gehaald, nu racen!', 'Yolo!'] },
  corso: { ...base, skill: 0.8, aggression: 0.75, laneChangeDelay: 0.5, awareness: 26, taunts: ['Bestelling onderweg!', 'Opzij, eten wordt koud!'] },
  calibro: { ...base, skill: 0.8, aggression: 0.7, playerFocus: 0.3, shunter: true, taunts: ['Heraklus!', 'Van achteren is ook raak!'] },
  volvi: { ...base, skill: 0.7, aggression: 0.6, taunts: ['Aan de kaante, noaber!', 'Kump wal goed!'] },
  spacewagen: { ...base, skill: 0.65, aggression: 0.35, erratic: 1, taunts: ['Oh, was dat rood?', 'Ik moet nog naar de Jumbo!'] },
};

// Traffic vehicle templates; colours are randomised per spawn.
export const TRAFFIC: { weight: number; spec: CarSpec; lane: 'right' | 'any'; speed: [number, number] }[] = [
  {
    weight: 6, lane: 'any', speed: [29, 35],
    spec: {
      id: 'sedan', name: 'Personenauto', driver: 'Verkeer', color: 0x888888, mass: 1300, length: 4.5, width: 1.78,
      topSpeed: 40, accelFactor: 0.7, gripFactor: 1, bodyHeight: 0.6, cabinLength: 2.2, cabinOffset: -0.2, cabinHeight: 0.5,
      hatch: false, spoiler: false, plate: '12-ABC-3',
    },
  },
  {
    weight: 5, lane: 'any', speed: [28, 34],
    spec: {
      id: 'hatch', name: 'Hatchback', driver: 'Verkeer', color: 0x888888, mass: 1100, length: 4.0, width: 1.72,
      topSpeed: 38, accelFactor: 0.7, gripFactor: 1, bodyHeight: 0.62, cabinLength: 2.0, cabinOffset: -0.4, cabinHeight: 0.52,
      hatch: true, spoiler: false, plate: '45-XYZ-6',
    },
  },
  {
    weight: 3, lane: 'right', speed: [25, 30],
    spec: {
      id: 'van', name: 'Bestelbus', driver: 'Verkeer', color: 0xf0f0f0, mass: 2400, length: 5.3, width: 1.98,
      topSpeed: 33, accelFactor: 0.6, gripFactor: 0.9, bodyHeight: 1.0, cabinLength: 1.2, cabinOffset: 1.5, cabinHeight: 0.9,
      hatch: true, spoiler: false, plate: 'VB-123-K', kind: 'van', armor: 0.6,
    },
  },
  {
    weight: 3, lane: 'right', speed: [22, 24],
    spec: {
      id: 'truck', name: 'Vrachtwagen', driver: 'Verkeer', color: 0x2255aa, mass: 14000, length: 16.5, width: 2.55,
      topSpeed: 25, accelFactor: 0.3, gripFactor: 0.8, bodyHeight: 1.2, cabinLength: 2.3, cabinOffset: 0, cabinHeight: 1.6,
      hatch: false, spoiler: false, plate: 'BX-12-TT', kind: 'truck', armor: 0.15,
    },
  },
  {
    weight: 2, lane: 'right', speed: [23, 26],
    spec: {
      id: 'caravan', name: 'Auto met caravan', driver: 'Verkeer', color: 0x888888, mass: 2700, length: 4.7, width: 1.8,
      topSpeed: 28, accelFactor: 0.5, gripFactor: 0.85, bodyHeight: 0.64, cabinLength: 2.6, cabinOffset: -0.5, cabinHeight: 0.56,
      hatch: true, spoiler: false, plate: 'DE-77-NL', trailerLength: 5.2, armor: 0.7,
    },
  },
];

export const TRUCK_COMPANIES = ['Tukker Transport', 'Van Salland Logistiek', 'Twentse Melk', 'Boekelo Bier', 'Hengelose Koek'];
export const TRAFFIC_COLORS = [0xc9c9c9, 0x2b2b2b, 0xf2f2f2, 0x7a1f1f, 0x1f3f7a, 0x3f5f3f, 0x9a8a6a, 0x5a5a66, 0xb5b5b5, 0x223344];

// Road cross-section (meters). d is the lateral offset, positive to the right of travel.
export const ROAD = {
  halfWidth: 5.5, // our carriageway: railing at ±5.5
  laneCenters: [-2.75, 0.75], // left lane, right lane (vluchtstrook ≈ 4.0)
  shoulder: 4.0,
  medianWidth: 3,
  oppositeWidth: 11,
  /** Lane centres of the opposite carriageway (traffic coming towards us). */
  oncomingLanes: [-11.75, -15.25],
  sampleSpacing: 1, // meters between track samples
};
