# A35 Racer (Godot 4)

Het spel voor **browser, iPhone, iPad en macOS**. Oorspronkelijk geport van een TypeScript/Three.js-versie
(sommige scripts noemen nog het bronbestand waar ze van afstammen); die versie is opgeheven.

## Eenmalig

Installeer [Godot 4.7](https://godotengine.org/download) in `/Applications` en daarin via
*Editor → Manage Export Templates* de export templates. Modellen, muziek en route staan in `assets/`.

## Spelen en bouwen

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path godot      # direct spelen op de Mac
scripts/macos-build.sh --open                                   # Mac-app bouwen: godot/build/macos/A35 Racer.app
scripts/ios-deploy.sh                                           # op alle aangesloten iPhones/iPads zetten
Godot --headless --path godot --export-release Web build/web/index.html   # webversie (gl_compatibility, zonder threads)
```

`ios-deploy.sh` exporteert een Xcode-project, bouwt het met je (gratis) Apple-team en installeert het op het
toestel dat aan de Mac hangt. Met een gratis Apple ID verloopt de app na 7 dagen; draai het script dan opnieuw.
Eén build werkt op iPhone én iPad (liggend).

## Besturing

Toetsenbord en gamepad zoals in de webversie (zie de README in de root; toetsen zijn te wijzigen via
*Besturing → Toetsen instellen*). Op iPhone en iPad verschijnen knoppen op het scherm: schuif met je duim
tussen ◀ en ▶, de RAM-knop kiest zelf de kant, AUTO GAS staat standaard aan en rechts zitten NITRO, REM, RAM en DRIFT in een
ruit zoals op een controller (GAS-pedaal verschijnt alleen als je AUTO GAS uitzet). Een MFi- of
PlayStation/Xbox-controller werkt ook.

## Hoe het in elkaar zit

| Script | Port van | Inhoud |
|---|---|---|
| `main.gd` | `main.ts`, `game/Game.ts` | opstarten, licht/lucht/mist, fixed-step loop (120 Hz), showroomcamera |
| `race.gd` | `game/Race.ts` | racestatus, checkpoints, takedowns, slipstream, bullet time, finish |
| `vehicle.gd`, `collisions.gd` | `vehicle/Vehicle.ts`, `physics/Collisions.ts` | arcade-physics en botsingen |
| `ai_driver.gd`, `traffic.gd`, `police.gd` | idem | rivalen, verkeer, tegenverkeer, politie en flitspalen |
| `track.gd`, `track_builder.gd`, `landmarks.gd`, `tex.gd` | `track/*` | weg, wereld (samengevoegd per km-vak), landmarks, procedurele texturen |
| `scenery.gd` | | kruisingen, verkeerslichten, op-/afritten, spoorwegovergang, kerken, molens, tankstation, pretparken |
| `car_model.gd` + `shaders/car*.gdshader` | `vehicle/CarModel.ts` | auto's: één mesh per auto, deuken, krassen, vuil en stickers in de shader |
| `livery.gd` | | stickers en liveries per coureur |
| `debris.gd` | | losgeslagen onderdelen, wielen en scherven op de weg |
| `effects.gd` | `fx/Particles.ts` | vonken, rook, vuur, explosies, nitro (MultiMesh) |
| `hud.gd`, `menu.gd`, `touch_controls.gd` | `ui/*` | HUD, menu's, touchknoppen |
| `input_ctl.gd`, `game_audio.gd`, `music.gd`, `announcer.gd`, `progress.gd` | `core/*` | invoer, geluid, muziek, omroeper (spraak van het systeem), voortgang en highscores |

De synthgeluiden van de webversie zijn met `python3 scripts/gen_sfx.py` naar WAV gerenderd
(`assets/sfx/`); motor, schuren, piepende banden en sirene zijn loops die het spel live filtert.

Niet meegenomen: het tuningpaneel (T) van de webversie.

## Testen zonder scherm

```bash
Godot --path godot -- --autoshot=/tmp/shot.png --autoplay --stage=4 --wait=20   # AI rijdt, screenshot na 20 s
Godot --path godot -- --autoshot=/tmp/menu.png --menu=cars --wait=3            # een menuscherm
Godot --headless --fixed-fps 30 --path godot -- --autoshot=/tmp/x.png --autoplay --stage=0 --wait=400
```

`--at=<meter>` zet de grid ergens op de route, `--heat=3` start met drie sterren en een volle nitrotank,
`--touch` toont de touchknoppen op een desktop, `--damage=200` beukt alle coureurs bij de start in elkaar,
`--showroom --car=golv` toont een auto van dichtbij zonder menu. De run print hoeveel milliseconden physics en beeld per frame kosten.

```bash
Godot --path godot -s res://tests/input_test.gd    # toetsen en touch door menu's en race heen, print ok/FAIL
```

Lettertypen: Bangers en Russo One (SIL Open Font License), Liberation Sans (SIL Open Font License),
DejaVu Sans (Bitstream Vera-licentie, `assets/fonts/DejaVu-LICENSE.txt`).
Kaartdata © OpenStreetMap-bijdragers (ODbL).
