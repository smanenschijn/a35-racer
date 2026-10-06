import * as THREE from 'three';

/**
 * Splits big instanced meshes (trees, posts, lamps along 31 km of road) into grid cells,
 * so frustum culling and the camera's far plane can skip everything out of sight.
 */
export function chunkInstances(root: THREE.Object3D, cell = 500, minCount = 48): void {
  const list: THREE.InstancedMesh[] = [];
  root.traverse((o) => {
    const inst = o as THREE.InstancedMesh;
    if (inst.isInstancedMesh && inst.count >= minCount) list.push(inst);
  });
  const m = new THREE.Matrix4();
  const p = new THREE.Vector3();
  const c = new THREE.Color();
  for (const inst of list) {
    const parent = inst.parent;
    if (!parent) continue;
    const cells = new Map<string, number[]>();
    for (let i = 0; i < inst.count; i++) {
      inst.getMatrixAt(i, m);
      p.setFromMatrixPosition(m);
      const key = `${Math.floor(p.x / cell)},${Math.floor(p.z / cell)}`;
      let ids = cells.get(key);
      if (!ids) cells.set(key, (ids = []));
      ids.push(i);
    }
    if (cells.size < 2) continue;
    for (const ids of cells.values()) {
      const part = new THREE.InstancedMesh(inst.geometry, inst.material, ids.length);
      ids.forEach((i, j) => {
        inst.getMatrixAt(i, m);
        part.setMatrixAt(j, m);
        if (inst.instanceColor) {
          inst.getColorAt(i, c);
          part.setColorAt(j, c);
        }
      });
      part.name = inst.name;
      part.castShadow = inst.castShadow;
      part.receiveShadow = inst.receiveShadow;
      part.renderOrder = inst.renderOrder;
      part.position.copy(inst.position);
      part.quaternion.copy(inst.quaternion);
      part.scale.copy(inst.scale);
      part.computeBoundingSphere();
      parent.add(part);
    }
    parent.remove(inst);
    inst.dispose();
  }
}
