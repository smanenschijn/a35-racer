import * as THREE from 'three';

// GPU point-sprite particle pool. One instance per blend mode (sparks/fire additive, smoke normal).

const vert = /* glsl */ `
  attribute float size;
  attribute float alpha;
  attribute vec3 tint;
  varying float vAlpha;
  varying vec3 vTint;
  uniform float pixelRatio;
  void main() {
    vAlpha = alpha;
    vTint = tint;
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    gl_PointSize = size * pixelRatio * (420.0 / -mv.z);
    gl_Position = projectionMatrix * mv;
  }
`;

const frag = /* glsl */ `
  varying float vAlpha;
  varying vec3 vTint;
  uniform float softness;
  void main() {
    vec2 c = gl_PointCoord - 0.5;
    float d = length(c) * 2.0;
    float a = smoothstep(1.0, softness, d) * vAlpha;
    if (a < 0.003) discard;
    gl_FragColor = vec4(vTint, a);
  }
`;

export interface ParticleOptions {
  max: number;
  additive: boolean;
  softness: number;
}

export interface SpawnParams {
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  life: number;
  size: number;
  grow?: number;
  r: number;
  g: number;
  b: number;
  alpha?: number;
  gravity?: number;
  drag?: number;
}

export class ParticleSystem {
  readonly points: THREE.Points;
  private max: number;
  private pos: Float32Array;
  private vel: Float32Array;
  private tint: Float32Array;
  private size: Float32Array;
  private alpha: Float32Array;
  private life: Float32Array;
  private maxLife: Float32Array;
  private baseSize: Float32Array;
  private grow: Float32Array;
  private baseAlpha: Float32Array;
  private gravity: Float32Array;
  private drag: Float32Array;
  private cursor = 0;
  private geo: THREE.BufferGeometry;

  constructor(opts: ParticleOptions) {
    const n = (this.max = opts.max);
    this.pos = new Float32Array(n * 3);
    this.vel = new Float32Array(n * 3);
    this.tint = new Float32Array(n * 3);
    this.size = new Float32Array(n);
    this.alpha = new Float32Array(n);
    this.life = new Float32Array(n);
    this.maxLife = new Float32Array(n);
    this.baseSize = new Float32Array(n);
    this.grow = new Float32Array(n);
    this.baseAlpha = new Float32Array(n);
    this.gravity = new Float32Array(n);
    this.drag = new Float32Array(n);
    this.geo = new THREE.BufferGeometry();
    this.geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    this.geo.setAttribute('tint', new THREE.BufferAttribute(this.tint, 3).setUsage(THREE.DynamicDrawUsage));
    this.geo.setAttribute('size', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    this.geo.setAttribute('alpha', new THREE.BufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage));
    const mat = new THREE.ShaderMaterial({
      vertexShader: vert,
      fragmentShader: frag,
      uniforms: { pixelRatio: { value: Math.min(window.devicePixelRatio, 2) }, softness: { value: opts.softness } },
      transparent: true,
      depthWrite: false,
      blending: opts.additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.points = new THREE.Points(this.geo, mat);
    this.points.frustumCulled = false;
  }

  spawn(p: SpawnParams): void {
    const i = this.cursor;
    this.cursor = (this.cursor + 1) % this.max;
    this.pos.set([p.x, p.y, p.z], i * 3);
    this.vel.set([p.vx, p.vy, p.vz], i * 3);
    this.tint.set([p.r, p.g, p.b], i * 3);
    this.life[i] = this.maxLife[i] = p.life;
    this.baseSize[i] = p.size;
    this.grow[i] = p.grow ?? 0;
    this.baseAlpha[i] = p.alpha ?? 1;
    this.gravity[i] = p.gravity ?? 0;
    this.drag[i] = p.drag ?? 0;
  }

  update(dt: number): void {
    for (let i = 0; i < this.max; i++) {
      if (this.life[i] <= 0) {
        this.alpha[i] = 0;
        continue;
      }
      this.life[i] -= dt;
      const t = 1 - Math.max(0, this.life[i]) / this.maxLife[i];
      const k = i * 3;
      const drag = Math.exp(-this.drag[i] * dt);
      this.vel[k] *= drag;
      this.vel[k + 1] = this.vel[k + 1] * drag - this.gravity[i] * dt;
      this.vel[k + 2] *= drag;
      this.pos[k] += this.vel[k] * dt;
      this.pos[k + 1] += this.vel[k + 1] * dt;
      this.pos[k + 2] += this.vel[k + 2] * dt;
      this.size[i] = this.baseSize[i] * (1 + this.grow[i] * t);
      this.alpha[i] = this.baseAlpha[i] * (1 - t) * Math.min(1, t * 12 + 0.2);
    }
    for (const name of ['position', 'tint', 'size', 'alpha']) this.geo.attributes[name].needsUpdate = true;
  }
}

/** Convenience layer with the game's effect presets. */
export class Effects {
  readonly sparks = new ParticleSystem({ max: 1500, additive: true, softness: 0.1 });
  readonly fire = new ParticleSystem({ max: 600, additive: true, softness: 0.0 });
  readonly smoke = new ParticleSystem({ max: 900, additive: false, softness: 0.0 });

  constructor(scene: THREE.Scene) {
    this.smoke.points.renderOrder = 1;
    this.fire.points.renderOrder = 2;
    this.sparks.points.renderOrder = 3;
    scene.add(this.smoke.points, this.fire.points, this.sparks.points);
  }

  sparkBurst(x: number, y: number, z: number, count: number, baseVx = 0, baseVz = 0, spread = 9): void {
    for (let i = 0; i < count; i++) {
      const hot = Math.random();
      this.sparks.spawn({
        x, y, z,
        vx: baseVx + (Math.random() - 0.5) * spread,
        vy: Math.random() * spread * 0.6 + 1,
        vz: baseVz + (Math.random() - 0.5) * spread,
        life: 0.25 + Math.random() * 0.45,
        size: 0.09 + Math.random() * 0.08,
        r: 4, g: 1.6 + hot * 1.4, b: 0.35 * hot,
        gravity: 14, drag: 1.5,
      });
    }
  }

  debris(x: number, y: number, z: number, count: number, vx: number, vz: number): void {
    for (let i = 0; i < count; i++) {
      this.smoke.spawn({
        x, y, z,
        vx: vx * 0.6 + (Math.random() - 0.5) * 8,
        vy: 2 + Math.random() * 5,
        vz: vz * 0.6 + (Math.random() - 0.5) * 8,
        life: 0.9, size: 0.12, r: 0.12, g: 0.12, b: 0.13, gravity: 16, drag: 0.6,
      });
    }
  }

  smokePuff(x: number, y: number, z: number, darkness: number, vx = 0, vz = 0): void {
    const c = 0.55 - darkness * 0.45;
    this.smoke.spawn({
      x: x + (Math.random() - 0.5) * 0.4, y, z: z + (Math.random() - 0.5) * 0.4,
      vx: vx * 0.3 + (Math.random() - 0.5), vy: 1.5 + Math.random() * 1.5, vz: vz * 0.3 + (Math.random() - 0.5),
      life: 1.4 + Math.random() * 1.2, size: 0.8 + Math.random() * 0.5, grow: 3.5,
      r: c, g: c * 0.97, b: c * 0.95, alpha: 0.5, drag: 0.8,
    });
  }

  tyreSmoke(x: number, y: number, z: number): void {
    this.smoke.spawn({
      x, y, z, vx: (Math.random() - 0.5) * 0.6, vy: 0.4 + Math.random() * 0.5, vz: (Math.random() - 0.5) * 0.6,
      life: 1 + Math.random() * 0.6, size: 0.6, grow: 4, r: 0.85, g: 0.85, b: 0.88, alpha: 0.28, drag: 1,
    });
  }

  flame(x: number, y: number, z: number): void {
    this.fire.spawn({
      x: x + (Math.random() - 0.5) * 0.8, y, z: z + (Math.random() - 0.5) * 0.8,
      vx: (Math.random() - 0.5) * 0.6, vy: 2 + Math.random() * 2, vz: (Math.random() - 0.5) * 0.6,
      life: 0.35 + Math.random() * 0.35, size: 0.45 + Math.random() * 0.35, grow: -0.6,
      r: 2.2, g: 0.7 + Math.random() * 0.5, b: 0.1, alpha: 0.7,
    });
  }

  nitroFlame(x: number, y: number, z: number, vx: number, vz: number): void {
    this.fire.spawn({
      x, y, z, vx: vx * 0.85, vy: 0, vz: vz * 0.85, life: 0.12, size: 0.35, grow: -0.5,
      r: 0.6, g: 1.4, b: 4.5, alpha: 0.9,
    });
  }

  update(dt: number): void {
    this.sparks.update(dt);
    this.fire.update(dt);
    this.smoke.update(dt);
  }
}
