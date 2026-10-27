# A35 Racer

Arcade-racegame: *Destruction Derby* meets *A2 Racer*, over de N35/A35 van Raalte naar Enschede.
Gebouwd in Godot 4.7 voor de browser, iPhone, iPad en macOS (alles in [godot/](godot/README.md)).
Zie [docs/GDD.md](docs/GDD.md) voor het volledige game design.

## Status

- De hele N35/A35 van Raalte naar Enschede uit OpenStreetMap, in vijf etappes: Raalte → Nijverdal → Wierden → Almelo → Hengelo → Enschede
- Brede weg (rijstroken van 4,2 m, brede vluchtstrook en redresseerstrook): op de N35 wijken verkeer en tegenliggers uit, zodat je er tussendoor kunt
- Echte kruisingen uit OSM met verkeerslichten (door rood = politie), kruisend verkeer, een fietsoversteek en een spoorwegovergang met slagbomen en trein
- Op- en afritten, afgezet met hekken, pionnen, een pijlwagen en "AFGESLOTEN"-borden
- Herkenningspunten: Blender-landmarks (raadhuis Raalte, Tokko Locco, Het Ravijn, Combiwet-tunnel, Stoomweverij, watertoren Wierden, Heraklus, Bouwhaus/IKEO, Metropool, UT, Grolsj Veste en brouwerij, Thuisbesteld) plus kerktorens, molens, een watertoren, tankstation, McDuck's, zendmast, schoorstenen, Avonturenpark Hellendoorn en De Waarbeek
- 8 coureurs met eigen stickers en liveries; schade met deuken, krassen, gebarsten ruiten, vuil, onderdelen en zelfs een voorwiel die eraf vliegen, slijpvonken met rook en vuur, motorbrand en explosies
- Verkeer, politie met wanted level, flitspalen en wegblokkades; etappes los of als "hele race", auto's vrijspelen, highscores, muziekspeler (zie [docs/muziek.md](docs/muziek.md))

Kaartdata © [OpenStreetMap](https://www.openstreetmap.org/copyright)-bijdragers (ODbL). De route opnieuw opbouwen: `python3 tools/osm/build_campaign.py`
(de OSM-snapshots en Overpass-queries staan in `tools/osm/`).

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
Op een telefoon kun je met je duim tussen ◀ en ▶ schuiven, kiest de RAM-knop zelf de kant en staat AUTO GAS standaard aan. Rechts zitten de actieknoppen in een ruit, zoals op een controller: NITRO onder je duim, REM links, RAM rechts, DRIFT boven en SLOW in de hoek. Zet je AUTO GAS uit, dan verschijnt er een GAS-pedaal naast de ruit.

## Ontwikkelen

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path godot      # spelen op de Mac
```

Bouwen en uitrollen (details in [godot/README.md](godot/README.md)):

| Doel | Commando |
|---|---|
| Mac-app | `scripts/macos-build.sh --open` |
| iPhone / iPad | `scripts/ios-deploy.sh` (alle aangesloten, ontgrendelde toestellen) |
| Web (lokaal testen) | Godot `--export-release Web build/web/index.html`, dan `python3 scripts/serve-web.py` |
| Web (eigen domein) | Dokploy met de `Dockerfile` in de root (poort 80) |

## Uitrollen via Dokploy

De `Dockerfile` downloadt Godot en de web-template, exporteert het spel naar WebAssembly en serveert het met nginx
(`deploy/nginx.conf`). In Dokploy: nieuwe *Application* → bron deze repository (branch `main`) → *Build Type: Dockerfile*
→ poort 80 → domein koppelen. Elke push naar `main` kan zo automatisch opnieuw uitrollen.
