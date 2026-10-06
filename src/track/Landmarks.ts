import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { getModel } from '../vehicle/models';
import type { Track } from './Track';
import type { TrackBuilder } from './TrackBuilder';

export const LANDMARK_MODELS = ['lm_metropool', 'lm_utwente', 'lm_veste', 'lm_brouwerij', 'lm_thuisbesteld', 'lm_barge'];

/** Merge a static model into one mesh per material (far fewer draw calls). */
function mergeStatic(src: THREE.Object3D): THREE.Group {
  const out = new THREE.Group();
  const groups = new Map<THREE.Material, THREE.BufferGeometry[]>();
  src.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(src.matrixWorld).invert();
  const m = new THREE.Matrix4();
  src.traverse((o) => {
    if (!(o instanceof THREE.Mesh)) return;
    const g = o.geometry.clone();
    g.applyMatrix4(m.multiplyMatrices(inv, o.matrixWorld));
    for (const name of Object.keys(g.attributes)) if (name !== 'position' && name !== 'normal') g.deleteAttribute(name);
    if (!g.index) g.setIndex([...Array(g.attributes.position.count).keys()]);
    const mat = o.material as THREE.Material;
    if (!groups.has(mat)) groups.set(mat, []);
    groups.get(mat)!.push(g);
  });
  for (const [mat, geos] of groups) {
    const geo = mergeGeometries(geos, false);
    if (!geo) continue;
    const mesh = new THREE.Mesh(geo, mat);
    const transparent = (mat as THREE.MeshStandardMaterial).transparent;
    mesh.castShadow = !transparent;
    mesh.receiveShadow = true;
    out.add(mesh);
  }
  return out;
}

/**
 * Places the Blender landmarks along the route (each turned to face the motorway) and sails
 * a barge on the Twentekanaal.
 */
export class Landmarks {
  readonly group = new THREE.Group();
  private barges: { obj: THREE.Object3D; phase: number; width: number }[] = [];
  private time = 0;

  constructor(track: Track, builder: TrackBuilder) {
    for (const lm of track.features.landmarks) {
      const tpl = getModel(`lm_${lm.id}`);
      if (!tpl) continue;
      const obj = mergeStatic(tpl);
      // Model front is +Z; its depth decides how far back it must stand from the road.
      const box = new THREE.Box3().setFromObject(obj);
      const side = Math.sign(lm.d) || 1;
      // Keep the front edge (max z) at least ~30 m from the road centre (clear of verge and trees).
      const dist = Math.max(Math.abs(lm.d), 30 + box.max.z);
      const fr = track.frame(lm.s);
      obj.position.set(fr.x + fr.rx * dist * side, 0, fr.z + fr.rz * dist * side);
      // Face the road: the road lies opposite to our side.
      const fx = -side * fr.rx;
      const fz = -side * fr.rz;
      obj.rotation.y = Math.atan2(fx, fz);
      obj.userData.landmark = lm.id;
      this.group.add(obj);
    }

    const barge = getModel('lm_barge');
    if (barge) {
      for (const canal of builder.canals) {
        const obj = mergeStatic(barge);
        obj.position.set(0, 0.08, 0);
        canal.holder.add(obj);
        this.barges.push({ obj, phase: Math.random() * Math.PI * 2, width: canal.width });
      }
    }
  }

  update(dt: number): void {
    this.time += dt;
    for (const b of this.barges) {
      // Slowly back and forth along the canal, passing under the bridge.
      const x = Math.sin(this.time * 0.012 + b.phase) * 260;
      const dir = Math.cos(this.time * 0.012 + b.phase) >= 0 ? 0 : Math.PI;
      b.obj.position.set(x, 0.08, b.width * 0.18 * (dir ? -1 : 1));
      b.obj.rotation.y = dir;
    }
  }
}
