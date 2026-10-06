import * as THREE from 'three';
import { Sky } from 'three/addons/objects/Sky.js';
import {
  BloomEffect, EffectComposer, EffectPass, RenderPass, SMAAEffect, ToneMappingEffect, ToneMappingMode,
  VignetteEffect,
} from 'postprocessing';
import { Announcer } from '../core/Announcer';
import { recordRace } from '../core/Progress';
import { GameAudio } from '../core/Audio';
import { EventBus } from '../core/Events';
import { Input } from '../core/Input';
import { MusicPlayer } from '../core/Music';
import { Effects } from '../fx/Particles';
import { Track } from '../track/Track';
import route from '../track/routes/campaign.json';
import { Landmarks } from '../track/Landmarks';
import { TrackBuilder } from '../track/TrackBuilder';
import { DebugPanel } from '../ui/DebugPanel';
import { Hud } from '../ui/Hud';
import { Menu } from '../ui/Menu';
import { TouchControls } from '../ui/Touch';
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
  // Adaptive resolution: full sharpness whenever the machine keeps up, a step down only when it doesn't.
  private readonly maxRatio = Math.min(window.devicePixelRatio, 1.75);
  private ratio = Math.min(window.devicePixelRatio, 1.75);
  private dtAvg = 1 / 60;
  private slowT = 0;
  private fastT = 0;
  private upWait = 6;
  private lastDrop = -99;
  private warmup = 3;
  /** Sky box: follows the camera, the route is 31 km long. */
  private sky!: Sky;
  private fill = new THREE.DirectionalLight(0x9fb8ff, 0.9);
  private input = new Input();
  private audio = new GameAudio();
  private music = new MusicPlayer(this.audio);
  private events = new EventBus();
  private track = new Track(route);
  private hud: Hud;
  private race: Race;
  private debug: DebugPanel;
  private accumulator = 0;
  private last = performance.now();
  private time = 0;
  private landmarks!: Landmarks;
  private announcer = new Announcer();
  private menu: Menu;
  private touch: TouchControls;
  private previewId = 'rx';
  private viewOffset = false;
  /** Running "hele race" campaign: accumulated time of the cleared stages. */
  private campaign: { total: number } | null = null;

  constructor(container: HTMLElement) {
    this.renderer = new THREE.WebGLRenderer({ powerPreference: 'high-performance', antialias: false, stencil: false, depth: true });
    this.renderer.setPixelRatio(this.maxRatio);
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
    this.hud.onReset = () => this.input.press('reset');
    this.race = new Race({
      scene: this.scene,
      track: this.track,
      events: this.events,
      fx,
      hud: this.hud,
      audio: this.audio,
      music: this.music,
      announcer: this.announcer,
      cam: this.cam,
      rumble: (s, w, ms) => this.input.rumble(s, w, ms),
      keyLabel: (a) => this.input.label(a),
    });
    this.debug = new DebugPanel(() => this.race.reset());
    this.music.onTrack = (t) => this.hud.showNowPlaying(t.title);
    this.audio.onReady = () => this.music.resume();
    this.music.playTitle();

    this.touch = new TouchControls(this.input);
    this.menu = new Menu({
      startStage: (i, campaign) => {
        this.campaign = campaign ? { total: 0 } : null;
        this.menu.close();
        this.race.setStage(i);
        this.race.start();
      },
      nextStage: () => {
        this.menu.close();
        this.race.setStage(this.race.stageIndex + 1);
        this.race.start();
      },
      restartRace: () => {
        this.menu.close();
        this.race.paused = false;
        this.race.start();
      },
      resume: () => {
        this.menu.close();
        this.race.paused = false;
      },
      toMenu: () => {
        this.race.paused = false;
        this.race.toMenu();
        this.announcer.stop();
        this.music.playTitle();
        this.menu.open('main');
      },
      chooseCar: (id) => this.race.setPlayerCar(id),
      previewCar: (id) => {
        this.previewId = id;
      },
      sound: () => this.toggleSound(),
    }, this.track.features.stages, this.input);
    this.race.onFinished = (r) => {
      const stageId = this.track.features.stages[r.stage].id;
      const unlocked = recordRace(stageId, r.position, r.qualified, r.takedowns, r.stats);
      if (this.campaign) {
        if (r.qualified) this.campaign.total += r.time;
      }
      this.menu.showResult(r, { campaign: !!this.campaign, campaignTotal: this.campaign?.total ?? 0, unlocked });
      if (this.campaign && !r.qualified) this.campaign = null; // failed: campaign over, the stage can be retried
    };
    this.menu.open('title');
    // Touch/click also counts as the user gesture that unlocks audio.
    window.addEventListener('pointerdown', () => this.audio.start());

    window.addEventListener('resize', () => this.resize());
    // Expose for debugging in the console.
    (window as unknown as { game: Game }).game = this;
  }

  private setupWorld(): void {
    const scene = this.scene;
    // Golden-hour sun low in the west, ahead-left of the road.
    const elevation = THREE.MathUtils.degToRad(3.5);
    // Real orientation: the route starts heading south (+Z) and runs east (+X) to Enschede.
    // An October sunset sits in the west-southwest: behind you on the long run east.
    const azimuth = THREE.MathUtils.degToRad(-75);
    this.sunDir.setFromSphericalCoords(1, Math.PI / 2 - elevation, azimuth);

    const sky = (this.sky = new Sky());
    sky.scale.setScalar(10000);
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

    const builder = new TrackBuilder(this.track);
    scene.add(builder.build());
    this.landmarks = new Landmarks(this.track, builder);
    scene.add(this.landmarks.group);
    // Nothing moves the scene root: children only recompute their matrices when they move themselves.
    scene.matrixAutoUpdate = false;
  }

  private toggleSound(): void {
    this.audio.setMuted(!this.audio.muted);
    this.announcer.muted = this.audio.muted;
    this.hud.message(this.audio.muted ? 'GELUID UIT' : 'GELUID AAN', '#fff', false, 0.8);
  }

  /** In the menus the camera slowly circles the car you're looking at on the grid. */
  private showroomCamera(): void {
    const v = this.race.racers.find((r) => r.spec.id === this.previewId) ?? this.race.player;
    this.race.showroom = v;
    const cam = this.cam.camera;
    const a = this.time * 0.25;
    const r = 4.2 + v.halfL * 1.25;
    cam.position.set(v.x + Math.sin(a) * r, v.y + 1.7, v.z + Math.cos(a) * r);
    cam.lookAt(v.x, v.y + 0.7, v.z);
    cam.fov = 50;
    // Shift the picture so the car sits right of the menu panel (wide screens only).
    const w = window.innerWidth;
    const h = window.innerHeight;
    if (w > 720) cam.setViewOffset(w, h, -w * 0.17, 0, w, h);
    else cam.clearViewOffset();
    cam.updateProjectionMatrix();
    this.viewOffset = true;
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

  /**
   * Below ~52 fps for two seconds: render a quarter step less sharp. Smooth again for a while: step
   * back up. If stepping up made it slow again, wait longer before the next try.
   */
  private adaptResolution(realDt: number): void {
    if (document.hidden || this.race.state === 'menu' || this.race.paused) {
      this.slowT = this.fastT = 0;
      return;
    }
    if (this.warmup > 0) {
      this.warmup -= realDt; // shaders compiling, models uploading
      return;
    }
    this.dtAvg += (realDt - this.dtAvg) * 0.05;
    if (this.dtAvg > 1 / 52) {
      this.slowT += realDt;
      this.fastT = 0;
    } else if (this.dtAvg < 1 / 58 && this.ratio < this.maxRatio) {
      this.fastT += realDt;
      this.slowT = 0;
    } else {
      this.slowT = this.fastT = 0;
    }
    if (this.slowT > 2 && this.ratio > 1) {
      if (this.time - this.lastDrop < this.upWait + 4) this.upWait = Math.min(60, this.upWait * 2);
      this.setRatio(this.ratio - 0.25);
      this.lastDrop = this.time;
      this.slowT = 0;
    } else if (this.fastT > this.upWait) {
      this.setRatio(this.ratio + 0.25);
      this.fastT = 0;
    }
  }

  private setRatio(r: number): void {
    this.ratio = Math.max(1, Math.min(this.maxRatio, r));
    this.renderer.setPixelRatio(this.ratio);
    this.resize();
    this.warmup = 0.5;
  }

  private frame(): void {
    const now = performance.now();
    const realDt = Math.min(0.1, (now - this.last) / 1000);
    this.last = now;
    this.time += realDt;

    this.adaptResolution(realDt);
    this.input.vehicleSpeed = this.race.player.speed;
    const controls = this.input.poll(realDt);
    if (controls.any) this.audio.start();
    if (controls.debug) this.debug.toggle();
    if (controls.mute) this.toggleSound();
    if (this.menu.isOpen) {
      this.menu.setGamepad(this.input.usingGamepad);
      this.menu.handle(controls);
      this.music.setMuffled(this.menu.screen === 'pause');
    } else if (controls.pause && (this.race.state === 'racing' || this.race.state === 'countdown')) {
      this.race.paused = true;
      this.menu.open('pause');
    } else {
      this.race.handleInput(controls, realDt);
    }
    const inMenu = this.race.state === 'menu';
    this.hud.setVisible(!inMenu);
    this.touch.setVisible(!this.menu.isOpen && !inMenu);

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
    if (this.race.state === 'menu') this.showroomCamera();
    else if (this.viewOffset) {
      this.cam.camera.clearViewOffset();
      this.viewOffset = false;
    }
    this.landmarks.update(this.race.paused ? 0 : realDt);

    // Shadow camera follows the player.
    const p = this.race.player;
    this.sun.target.position.set(p.x, p.y, p.z);
    this.sun.position.set(p.x + this.sunDir.x * 300, p.y + this.sunDir.y * 300 + 60, p.z + this.sunDir.z * 300);
    const cp = this.cam.camera.position;
    this.fill.position.set(cp.x * 2 - p.x, cp.y + 8, cp.z * 2 - p.z);
    this.fill.target.position.set(p.x, p.y, p.z);

    this.sky.position.copy(this.cam.camera.position);
    this.composer.render(realDt);
  }
}
