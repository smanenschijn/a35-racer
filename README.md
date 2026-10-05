# A35 Racer

Arcade-racegame in de browser: *Destruction Derby* meets *A2 Racer*, over de N35/A35 van Raalte naar Enschede.
Zie [docs/GDD.md](docs/GDD.md) voor het volledige game design.

**Speel:** https://smanenschijn.github.io/a35-racer/

## Status: mijlpaal 1 (rijden + beuken)

Grey-box stuk A35 (Hengelo-Zuid → Enschede) met:

- Semi-arcade handling (gewicht, handrem-drift), chase cam met camera-shake
- 3 AI-tegenstanders (Sanne, Henk-Jan, Gerrit) die racen, inhalen, blokkeren en rammen
- Botsingen auto–auto en auto–vangrail, zijwaartse ram-aanval (Q/E)
- Schade per zone (voor/achter/links/rechts) met effect op rijgedrag, deuken, losse onderdelen, rook en vuur
- Takedowns met slow-mo, total loss → respawn
- Nitro, gevuld door beuken, rakelings passeren en driften
- Toetsenbord + gamepad, HUD, gesynthetiseerd geluid, tuningpaneel (T)

## Besturing

| Actie | Toetsenbord | Gamepad |
|---|---|---|
| Gas / rem | ↑ ↓ of W S | R2 / L2 |
| Sturen | ← → of A D | linkerstick |
| Handrem | Spatie | ✕ / A |
| Nitro | Shift | ○ / B |
| Ram links / rechts | Q / E | L1 / R1 |
| Terug op de weg | Backspace | △ / Y |
| Herstart | R | Select |
| Pauze | Esc / P | Start |
| Geluid aan/uit | M | |
| Tuningpaneel | T | |

## Ontwikkelen

```bash
npm install
npm run dev
```

- `npm run build`: typecheck + productie-build naar `dist/`
- `?autopilot` achter de URL laat een AI jouw auto besturen (handig om te testen)
- In de console is `game` beschikbaar voor debuggen
- Push naar `main` deployt automatisch naar GitHub Pages

## Techniek

TypeScript, Vite, Three.js en `postprocessing` (bloom, tone mapping). Eigen arcade-physics: de weg is een spline,
auto's zijn 2D rigid bodies met impuls-botsingen, vangrails zijn zijdelingse grenzen in weg-coördinaten.

| Map | Inhoud |
|---|---|
| `src/track` | Wegspline, projectie, wereldopbouw, procedurele texturen |
| `src/vehicle` | Auto-physics, schade, AI, procedurele 3D-modellen met deuken |
| `src/physics` | Botsingen tussen auto's |
| `src/game` | Game loop, race-logica, camera |
| `src/fx`, `src/ui`, `src/core` | Particles, HUD, tuning, invoer, audio, events |
| `src/config.ts` | Alle tuningwaarden, auto's en AI-persoonlijkheden |
