import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

// Detailed vehicle models built in Blender (see blender/), loaded once at startup.
// A missing model just means that car falls back to its procedural geometry.

const cache = new Map<string, THREE.Object3D>();

export async function loadModels(names: string[]): Promise<void> {
  const loader = new GLTFLoader();
  await Promise.all(
    names.map(async (name) => {
      try {
        const gltf = await loader.loadAsync(`${import.meta.env.BASE_URL}models/${name}.glb`);
        // The exported scene holds one root node (the car); keep that.
        cache.set(name, gltf.scene.children.length === 1 ? gltf.scene.children[0] : gltf.scene);
      } catch (e) {
        console.warn(`Model ${name} niet geladen, val terug op procedureel model`, e);
      }
    }),
  );
}

export function getModel(name: string): THREE.Object3D | undefined {
  return cache.get(name);
}
