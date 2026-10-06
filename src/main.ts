import './style.css';
import { Game } from './game/Game';
import { LANDMARK_MODELS } from './track/Landmarks';
import { loadModels } from './vehicle/models';

// Detailed Blender models first; anything that fails to load falls back to procedural cars.
await loadModels(['rx7', 'supremo', 'golv', 'civik', 'corso', 'calibro', 'volvi', 'spacewagen', ...LANDMARK_MODELS]);
document.getElementById('loading')?.remove();
const game = new Game(document.getElementById('app')!);
game.start();
