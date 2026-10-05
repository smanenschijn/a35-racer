import * as THREE from 'three';
import { Sky } from 'three/addons/objects/Sky.js';
import {
  BloomEffect, EffectComposer, EffectPass, RenderPass, SMAAEffect, ToneMappingEffect, ToneMappingMode,
  VignetteEffect,
} from 'postprocessing';
import { GameAudio } from '../core/Audio';
import { EventBus } from '../core/Events';
import { Input } from '../core/Input';
import { MusicPlayer } from '../core/Music';
import { Effects } from '../fx/Particles';
import { Track } from '../track/Track';
import { TrackBuilder } from '../track/TrackBuilder';
import { DebugPanel } from '../ui/DebugPanel';
import { Hud } from '../ui/Hud';
import { ChaseCamera } from './ChaseCamera';
import { Race } from './Race';

const FIXED_DT = 1 / 120;

export class Game {
  private renderer: THREE.WebGLRenderer;
  private composer: EffectComposer;
  private scene = new THREE.Scene();
  private cam: ChaseCamera;
  private sun = new THREE.DirectionalLight(0xffc48a, 3.2);
  private sunDir = new THREE.Vector3();
  private fill = new THREE.DirectionalLight(0x9fb8ff, 0.9);
  private input = new Input();
  private audio = new GameAudio();
  private music = new MusicPlayer(this.audio);
  private events = new EventBus();
  private track = new Track();
  private hud: Hud;
  private race: Race;
  private debug: DebugPanel;
  private accumulator = 0;
  private last = performance.now();
  private time = 0;
  private titleGamepad = false;

  constructor(container: HTMLElement) {
    this.renderer = new THREE.WebGLRenderer({ powerPreference: 'high-performance', antialias: false, stencil: false, depth: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.75));
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.toneMapping = THREE.NoToneMapping; // tone mapping happens in the post chain
    container.appendChild(this.renderer.domElement);

    this.cam = new ChaseCamera(window.innerWidth / window.innerHeight);
    this.setupWorld();

    this.composer = new EffectComposer(this.renderer, { frameBufferType: THREE.HalfFloatType });
    this.composer.addPass(new RenderPass(this.scene, this.cam.camera));
    this.composer.addPass(
      new EffectPass(
        this.cam.camera,
        new BloomEffect({ luminanceThreshold: 1.0, luminanceSmoothing: 0.3, intensity: 0.9, mipmapBlur: true, radius: 0.7 }),
        new VignetteEffect({ darkness: 0.45, offset: 0.3 }),
        new ToneMappingEffect({ mode: ToneMappingMode.ACES_FILMIC }),
      ),
      );
    this.composer.addPass(new EffectPass(this.cam.camera, new SMAAEffect()));

    const fx = new Effects(this.scene);
    this.hud = new Hud(document.body);
    this.race = new Race({
      scene: this.scene,
      track: this.track,
      events: this.events,
      fx,
      hud: this.hud,
      audio: this.audio,
      music: this.music,
      cam: this.cam,
      rumble: (s, w, ms) => this.input.rumble(s, w, ms),
    });
    this.debug = new DebugPanel(() => this.race.reset());
    this.hud.showTitle(false);
    this.music.onTrack = (t) => this.hud.showNowPlaying(t.title);
    this.audio.onReady = () => this.music.resume();
    this.music.playTitle();

    window.addEventListener('resize', () => this.resize());
    // Expose for debugging in the console.
    (window as unknown as { game: Game }).game = this;
  }

  private setupWorld(): void {
    const scene = this.scene;
    // Golden-hour sun low in the west, ahead-left of the road.
    const elevation = THREE.MathUtils.degToRad(3.5);
    const azimuth = THREE.MathUtils.degToRad(55);
    this.sunDir.setFromSphericalCoords(1, Math.PI / 2 - elevation, azimuth);

    const sky = new Sky();
    sky.scale.setScalar(20000);
    const u = sky.material.uniforms;
    u.turbidity.value = 9;
    u.rayleigh.value = 2.6;
    u.mieCoefficient.value = 0.0035;
    u.mieDirectionalG.value = 0.8;
    u.sunPosition.value.copy(this.sunDir);
    if (u.cloudCoverage) u.cloudCoverage.value = 0.35;
    scene.add(sky);

    // Environment map from the sky for reflections on paint and water.
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    const envScene = new THREE.Scene();
    const envSky = new Sky();
    envSky.scale.setScalar(1000);
    for (const k of Object.keys(u)) envSky.material.uniforms[k].value = u[k].value;
    envScene.add(envSky);
    scene.environment = pmrem.fromScene(envScene, 0.02).texture;
    scene.environmentIntensity = 0.75;

    scene.fog = new THREE.Fog(0xe8a070, 250, 2600);

    scene.add(new THREE.HemisphereLight(0xffd2a8, 0x3a4a2a, 1.1));
    // Soft fill from behind the camera so cars facing away from the low sun keep their colour.
    this.fill.castShadow = false;
    scene.add(this.fill, this.fill.target);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(2048, 2048);
    const sc = this.sun.shadow.camera;
    sc.left = -70;
    sc.right = 70;
    sc.top = 70;
    sc.bottom = -70;
    sc.near = 1;
    sc.far = 600;
    this.sun.shadow.bias = -0.0004;
    this.sun.shadow.normalBias = 0.04;
    scene.add(this.sun, this.sun.target);

    scene.add(new TrackBuilder(this.track).build());
  }

  private resize(): void {
    const w = window.innerWidth;
    const h = window.innerHeight;
    this.renderer.setSize(w, h);
    this.composer.setSize(w, h);
    this.cam.camera.aspect = w / h;
    this.cam.camera.updateProjectionMatrix();
  }

  start(): void {
    const loop = () => {
      requestAnimationFrame(loop);
      this.frame();
    };
    loop();
  }

  private frame(): void {
    const now = performance.now();
    const realDt = Math.min(0.1, (now - this.last) / 1000);
    this.last = now;
    this.time += realDt;

    const controls = this.input.poll(realDt);
    if (controls.debug) this.debug.toggle();
    if (controls.mute) {
      this.audio.setMuted(!this.audio.muted);
      this.hud.message(this.audio.muted ? 'GELUID UIT' : 'GELUID AAN', '#fff', false, 0.8);
    }
    this.race.handleInput(controls, realDt);
    if (this.race.state === 'title' && this.input.usingGamepad !== this.titleGamepad) {
      this.titleGamepad = this.input.usingGamepad;
      this.hud.showTitle(this.titleGamepad);
    }

    // Fixed-step physics, scaled by slow-mo.
    if (!this.race.paused) {
      this.accumulator += realDt * this.race.timeScale;
      let steps = 0;
      while (this.accumulator >= FIXED_DT && steps < 24) {
        this.race.step(FIXED_DT);
        this.accumulator -= FIXED_DT;
        steps++;
      }
      if (steps >= 24) this.accumulator = 0;
    }

    this.race.render(realDt, this.time);

    // Shadow camera follows the player.
    const p = this.race.player;
    this.sun.target.position.set(p.x, p.y, p.z);
    this.sun.position.set(p.x + this.sunDir.x * 300, p.y + this.sunDir.y * 300 + 60, p.z + this.sunDir.z * 300);
    const cp = this.cam.camera.position;
    this.fill.position.set(cp.x * 2 - p.x, cp.y + 8, cp.z * 2 - p.z);
    this.fill.target.position.set(p.x, p.y, p.z);

    this.composer.render(realDt);
  }
}
