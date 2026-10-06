import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

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

/** Same-looking materials (built one per call in places) collapse onto one shared instance. */
function materialKey(m: THREE.Material): string {
  const s = m as THREE.MeshStandardMaterial & THREE.MeshPhysicalMaterial;
  const tex = (t: THREE.Texture | null | undefined) => (t ? t.uuid : '-');
  return [
    m.type, s.color?.getHexString(), s.emissive?.getHexString(), s.emissiveIntensity, s.roughness, s.metalness,
    s.clearcoat, tex(s.map), tex(s.normalMap), tex(s.emissiveMap), tex(s.alphaMap), m.transparent, m.opacity, m.side,
    m.vertexColors, s.flatShading, m.depthWrite, m.alphaTest, s.envMapIntensity, m.polygonOffset, m.polygonOffsetFactor,
  ].join('|');
}

/**
 * Merge every static mesh under `root` into one mesh per (grid cell, material). Long road and verge
 * ribbons are cut into cells triangle by triangle, so whatever is out of view or past the far plane
 * is skipped. Subtrees marked `userData.dynamic` (things that move) are left alone.
 */
export function mergeStaticByCell(root: THREE.Object3D, cell = 2000): void {
  root.updateMatrixWorld(true);
  const toRoot = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const meshes: THREE.Mesh[] = [];
  const visit = (o: THREE.Object3D) => {
    if (o.userData.dynamic) return;
    const mesh = o as THREE.Mesh;
    if (mesh.isMesh && !(o as THREE.InstancedMesh).isInstancedMesh && !Array.isArray(mesh.material) && o.visible) meshes.push(mesh);
    for (const c of o.children) visit(c);
  };
  visit(root);

  const shared = new Map<string, THREE.Material>();
  interface Bucket { mat: THREE.Material; cast: boolean; receive: boolean; order: number; geos: THREE.BufferGeometry[] }
  const buckets = new Map<string, Bucket>();
  const m = new THREE.Matrix4();
  const tmp = new THREE.Vector3();
  for (const mesh of meshes) {
    const src = mesh.geometry;
    if (Object.keys(src.morphAttributes).length) continue;
    let g = src.clone();
    if (!g.index) g.setIndex([...Array(g.attributes.position.count).keys()]);
    m.multiplyMatrices(toRoot, mesh.matrixWorld);
    g.applyMatrix4(m);
    const index = g.index!.array;
    const flip = m.determinant() < 0; // mirrored: keep the winding facing outwards
    const pos = g.attributes.position;
    const names = Object.keys(g.attributes).sort();
    const sig = names.map((n) => `${n}${g.attributes[n].itemSize}`).join(',');
    const mk = materialKey(mesh.material as THREE.Material);
    if (!shared.has(mk)) shared.set(mk, mesh.material as THREE.Material);
    const mat = shared.get(mk)!;
    // Triangles per cell.
    const perCell = new Map<string, number[]>();
    for (let t = 0; t < index.length; t += 3) {
      tmp.set(0, 0, 0);
      for (let k = 0; k < 3; k++) {
        const v = index[t + k];
        tmp.x += pos.getX(v);
        tmp.z += pos.getZ(v);
      }
      const key = `${Math.floor(tmp.x / 3 / cell)},${Math.floor(tmp.z / 3 / cell)}`;
      let list = perCell.get(key);
      if (!list) perCell.set(key, (list = []));
      if (flip) list.push(index[t], index[t + 2], index[t + 1]);
      else list.push(index[t], index[t + 1], index[t + 2]);
    }
    for (const [key, tris] of perCell) {
      // Compact copy holding only the vertices these triangles use.
      const remap = new Map<number, number>();
      const newIndex: number[] = [];
      for (const v of tris) {
        let n = remap.get(v);
        if (n === undefined) remap.set(v, (n = remap.size));
        newIndex.push(n);
      }
      const part = new THREE.BufferGeometry();
      for (const name of names) {
        const a = g.attributes[name] as THREE.BufferAttribute;
        const arr = new Float32Array(remap.size * a.itemSize);
        for (const [oldI, newI] of remap) for (let c = 0; c < a.itemSize; c++) arr[newI * a.itemSize + c] = a.getComponent(oldI, c);
        part.setAttribute(name, new THREE.BufferAttribute(arr, a.itemSize, a.normalized));
      }
      part.setIndex(newIndex);
      const bkey = `${key}|${mk}|${mesh.castShadow}|${mesh.receiveShadow}|${mesh.renderOrder}|${sig}`;
      let b = buckets.get(bkey);
      if (!b) buckets.set(bkey, (b = { mat, cast: mesh.castShadow, receive: mesh.receiveShadow, order: mesh.renderOrder, geos: [] }));
      b.geos.push(part);
    }
    g.dispose();
    mesh.removeFromParent();
  }
  for (const b of buckets.values()) {
    const geo = b.geos.length === 1 ? b.geos[0] : mergeGeometries(b.geos, false);
    if (!geo) continue;
    geo.computeBoundingSphere();
    const mesh = new THREE.Mesh(geo, b.mat);
    mesh.castShadow = b.cast;
    mesh.receiveShadow = b.receive;
    mesh.renderOrder = b.order;
    root.add(mesh);
  }
  // Drop the now empty groups.
  const prune = (o: THREE.Object3D) => {
    for (const c of [...o.children]) {
      prune(c);
      if (!c.userData.dynamic && c.type === 'Group' && c.children.length === 0) c.removeFromParent();
    }
  };
  prune(root);
}

/** Static scenery: compute its matrices once and stop recomputing them every frame. */
export function freezeStatic(root: THREE.Object3D): void {
  root.updateMatrixWorld(true);
  const visit = (o: THREE.Object3D) => {
    if (o.userData.dynamic) return;
    o.matrixAutoUpdate = false;
    for (const c of o.children) visit(c);
  };
  visit(root);
}
