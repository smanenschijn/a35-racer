import './style.css';
import { Game } from './game/Game';
import { loadModels } from './vehicle/models';

// Detailed Blender models first; anything that fails to load falls back to procedural cars.
await loadModels(['rx7']);
const game = new Game(document.getElementById('app')!);
game.start();
