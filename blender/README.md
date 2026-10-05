# Blender-modellen

De voertuigen worden in Blender opgebouwd uit veel kleine, losse onderdelen. In het `.blend`-bestand blijven die onderdelen los, zodat je ze kunt bijwerken. De game krijgt één `.glb` per voertuig. Daarin zijn de onderdelen samengevoegd tot één model, maar ze houden hun naam. Zo kan de game per paneel deuken maken en onderdelen laten afbreken.

## Bouwen

Vanuit de root van de repo:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python blender/build_rx7.py
```

Dat levert:

| Bestand | Inhoud |
|---|---|
| `assets/blender/rx7.blend` | Alle onderdelen als losse objecten, om te openen en te bewerken |
| `public/models/rx7.glb` | Het model dat de game laadt |
| `assets/renders/rx7_*.png` | Voorbeeldrenders (voor, achter, zij) |

## Stijl

De carrosserie heeft een hoekige doorsnede met scherpe vouwlijnen: de sideskirt-rand, de schouderlijn en de rand van de motorkap of achterklep. Die vouwen zijn als *sharp* gemarkeerd, zodat ze in de game strak oplichten. Daarbovenop liggen paneelnaden, spatbordranden, een interieur achter getint glas en gedetailleerde wielen.

## Opbouw van een auto

- **Carrosserie:** één gladde loft die in panelen is geknipt: `nose`, `hood`, `fender_L/R`, `door_L/R`, `quarter_L/R`, `deck_lid`, `tail`, `tub` en `underbody`.
- **Cabine:** `cabin_glass`, `cabin_roof` en `cabin_seal`.
- **Losse details:** klapkoplampen met ronde lampen, grille met lamellen, mistlampen, remkoeling, splitter, ventilatieroosters, ruitenwissers, spoiler met vleugelprofiel en derde remlicht, spiegels, sideskirts, tankdop, antenne, achterlichten met chromen ringen, diffuser met vinnen, uitlaten en kentekenplaten met houders.
- **Paneelnaden:** `gap_*`, donkere stroken op de carrosserie.
- **Interieur:** dashboard, stuur, kuipstoelen, middenconsole en hoedenplank.
- **Wielen:** per wiel een `hub_XX` (stuurt), met daaronder `wheel_XX` (draait: band, velg, remschijf) en `caliper_XX` (draait niet mee).

## Afspraken met de game

- **Assen:** de voorkant van de auto wijst naar -Y en de linkerkant naar +X, met Z omhoog. De oorsprong ligt op de grond, halverwege de lengte. Na export wordt dat in de game +Z vooruit en +Y omhoog.
- **Custom properties** gaan als glTF-extras mee naar de game:
  - `zone` (`front` / `rear` / `left` / `right`): de schadezone.
  - `deform`: het paneel deukt in.
  - `detach`: het onderdeel kan afbreken.
  - `steer` / `spin`: voor de wielen.
- **Materiaalnamen** gebruikt de game om materialen te herkennen:
  - `Paint` krijgt per auto de juiste kleur.
  - `BrakeLight` en `HeadLight` worden door de game aangestuurd.
  - `Plate` krijgt de kentekentekst.
  - De overige materialen (`Glass`, `Trim`, `Chrome`, `Tyre`, `Rim`, `Caliper`, `Indicator`, `Reverse`, `Interior`, `Seat`) blijven zoals ze zijn.

## Met de hand bijwerken

Je kunt het `.blend`-bestand openen en onderdelen aanpassen. Houd daarbij de objectnamen, custom properties en materiaalnamen aan. Exporteer daarna via *File → Export → glTF 2.0*, met *Include → Custom Properties* aan. Let op: als je het bouwscript daarna opnieuw draait, overschrijft het je handmatige wijzigingen.
