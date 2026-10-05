# A35 Racer

Arcade-racegame in de browser: *Destruction Derby* meets *A2 Racer*, over de N35/A35 van Raalte naar Enschede.
Zie [docs/GDD.md](docs/GDD.md) voor het volledige game design.

**Speel:** https://smanenschijn.github.io/a35-racer/

## Status: mijlpaal 2 (verkeer, politie en muziek)

Grey-box stuk A35 (Hengelo-Zuid → Enschede) met:

- 8 coureurs: jij en 7 tegenstanders met eigen rijstijl en scheldteksten
- Verkeer in jouw richting dat je kunt beuken en als wapen kunt gebruiken, plus tegenliggers op de andere rijbaan
- Politie: wanted level door chaos en flitspalen, achtervolging, wegblokkades vanaf 3 sterren, boete als je wordt klemgezet
- Semi-arcade handling, rammen (Q/E), schade per zone, takedowns, nitro
- Muziekspeler (de nummers zelf komen nog, zie [docs/muziek.md](docs/muziek.md))

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
| Volgend nummer | N | ▢ / X |
| Muziekvolume | − / + | |
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
- Muziek: zet de mp3's in `public/music/` (namen in [docs/muziek.md](docs/muziek.md)); ontbrekende nummers worden overgeslagen

## Techniek

TypeScript, Vite, Three.js en `postprocessing` (bloom, tone mapping). Eigen arcade-physics: de weg is een spline,
auto's zijn 2D rigid bodies met impuls-botsingen, vangrails zijn zijdelingse grenzen in weg-coördinaten.

| Map | Inhoud |
|---|---|
| `src/track` | Wegspline, projectie, wereldopbouw, procedurele texturen |
| `src/vehicle` | Auto-physics, schade, AI, procedurele 3D-modellen met deuken |
| `src/physics` | Botsingen tussen auto's |
| `src/game` | Game loop, race-logica, camera, verkeer, politie |
| `src/fx`, `src/ui`, `src/core` | Particles, HUD, tuning, invoer, audio, events |
| `src/config.ts` | Alle tuningwaarden, auto's en AI-persoonlijkheden |
