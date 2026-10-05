import './style.css';
import { Game } from './game/Game';

const game = new Game(document.getElementById('app')!);
game.start();
