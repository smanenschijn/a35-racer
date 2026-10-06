import * as THREE from 'three';
import { tuning } from '../config';
import type { Vehicle } from '../vehicle/Vehicle';

/** Spring-damped chase cam with impact shake and a wider FOV on nitro. */
export class ChaseCamera {
  readonly camera: THREE.PerspectiveCamera;
  private pos = new THREE.Vector3();
  private look = new THREE.Vector3();
  private yaw = 0;
  private shake = 0;
  private initialized = false;
  /** Held by the player: look over the rear bumper. */
  lookBack = false;
  private wasLookingBack = false;

  constructor(aspect: number) {
    this.camera = new THREE.PerspectiveCamera(tuning.camFov, aspect, 0.3, 2800) // fog ends at 2600;
  }

  addShake(amount: number): void {
    this.shake = Math.min(1.2, this.shake + amount);
  }

  snap(): void {
    this.initialized = false;
  }

  update(v: Vehicle, dt: number, time: number): void {
    // Follow the direction of travel rather than the nose, so drifts show the car sideways.
    const speed = v.speed;
    const velYaw = speed > 4 && v.forwardSpeed > 0 ? Math.atan2(v.vx, v.vz) : v.heading;
    let diff = velYaw - v.heading;
    diff = Math.atan2(Math.sin(diff), Math.cos(diff));
    const targetYaw = v.heading + diff * 0.55;
    if (!this.initialized) this.yaw = targetYaw;
    let dy = targetYaw - this.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    this.yaw += dy * Math.min(1, dt * 3.5);

    const speedT = Math.min(1, speed / 70);
    const dist = tuning.camDistance + speedT * 1.4;
    const height = tuning.camHeight + speedT * 0.3;
    // Looking back: the same rig turned around, a little closer so the car stays out of the way.
    const back = this.lookBack;
    const camYaw = back ? v.heading + Math.PI : this.yaw;
    const fx = Math.sin(camYaw);
    const fz = Math.cos(camYaw);
    const camDist = back ? dist * 0.8 : dist;
    const target = new THREE.Vector3(v.x - fx * camDist, v.y + height, v.z - fz * camDist);
    const lookTarget = new THREE.Vector3(v.x + fx * 6, v.y + 1.1, v.z + fz * 6);

    // Cut, don't swing, when switching between forward and backward views.
    if (back !== this.wasLookingBack) {
      this.wasLookingBack = back;
      this.initialized = false;
    }
    if (!this.initialized) {
      this.pos.copy(target);
      this.look.copy(lookTarget);
      this.initialized = true;
    }
    this.pos.lerp(target, Math.min(1, dt * 6));
    this.pos.y += (target.y - this.pos.y) * Math.min(1, dt * 4);
    this.look.lerp(lookTarget, Math.min(1, dt * 14));

    this.camera.position.copy(this.pos);
    if (this.shake > 0.001) {
      const s = this.shake * this.shake * 0.35;
      this.camera.position.x += (Math.sin(time * 71) + Math.sin(time * 37)) * s;
      this.camera.position.y += Math.sin(time * 53) * s;
      this.shake *= Math.exp(-dt * 6);
    }
    this.camera.lookAt(this.look);

    const fov = v.nitroActive ? tuning.camFovNitro : tuning.camFov + speedT * 6;
    this.camera.fov += (fov - this.camera.fov) * Math.min(1, dt * 4);
    this.camera.updateProjectionMatrix();
  }
}
