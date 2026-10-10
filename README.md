# A35 Racer

Arcade-racegame in de browser: *Destruction Derby* meets *A2 Racer*, over de N35/A35 van Raalte naar Enschede.
Zie [docs/GDD.md](docs/GDD.md) voor het volledige game design.

**Speel:** https://smanenschijn.github.io/a35-racer/ · **iPhone, iPad en Mac:** de Godot-versie in [godot/](godot/README.md)

## Status: mijlpaal 5 (de volledige race)

- De hele N35/A35 van Raalte naar Enschede uit OpenStreetMap, in vijf etappes: Raalte → Nijverdal → Wierden → Almelo → Hengelo → Enschede
- De N35 als enkelbaansweg met tegenverkeer, de Combiwet-tunnel bij Nijverdal en de Sallandse Heuvelrug
- Landmarks gebouwd in Blender: raadhuis Raalte, Tokko Locco, Bouwhaus, IKEO, Het Ravijn, gemeentehuis Nijverdal, Koninklijke Stoomweverij, watertoren Wierden, Heraklus-stadion, Metropool, Universiteit Twente, Grolsj Veste, Grolsj-brouwerij, Thuisbesteld-hoofdkantoor en een binnenvaartschip
- 8 coureurs in gedetailleerde Blender-auto's, verkeer, politie met wanted level, flitspalen en wegblokkades
- Etappes los of als "hele race", auto's vrijspelen, statistieken en highscores per etappe
- Muziekspeler (zie [docs/muziek.md](docs/muziek.md))

Kaartdata © [OpenStreetMap](https://www.openstreetmap.org/copyright)-bijdragers (ODbL). De route opnieuw opbouwen: `python3 tools/osm/build_campaign.py`.

## Besturing

| Actie | Toetsenbord | Gamepad |
|---|---|---|
| Gas / rem | ↑ ↓ of W S | R2 / L2 |
| Sturen | ← → of A D | linkerstick |
| Handrem | Spatie | ✕ / A |
| Nitro | Shift | ○ / B |
| Bullet time (slow-motion) | C | L3 of R3 (stick indrukken) |
| Ram links / rechts | Q / E (licht geel op als er iemand binnen bereik is) | L1 / R1 |
| Achterom kijken | V (vasthouden) | rechterstick naar beneden |
| Terug op de weg | F (of de ↺-knop; gaat ook vanzelf als je vastzit) | △ / Y |
| Herstart | R vasthouden | Select vasthouden |
| Pauze | Esc / P | Start |
| Geluid aan/uit | M | |
| Volgend nummer | N | ▢ / X |
| Muziekvolume | − / + | |
| Tuningpaneel | T | |

De rijtoetsen zijn te wijzigen via *Besturing → Toetsen instellen* (bewaard in de browser).
Op een telefoon kun je met je duim tussen ◀ en ▶ schuiven, kiest de RAM-knop zelf de kant en houdt AUTO GAS het gas voor je ingedrukt.

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
