# Blender-modellen

De voertuigen worden in Blender opgebouwd uit veel kleine, losse onderdelen. In het `.blend`-bestand blijven die onderdelen los, zodat je ze kunt bijwerken. De game krijgt één `.glb` per voertuig. Daarin zijn de onderdelen samengevoegd tot één model, maar ze houden hun naam. Zo kan de game per paneel deuken maken en onderdelen laten afbreken.

## Bouwen

Alle auto's worden gemaakt met één algemene bouwer (`carbuilder.py`). De ontwerpen staan in `designs.py`. Vanuit de root van de repo:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python blender/build_cars.py
```

Wil je maar een paar auto's bouwen, zet dan hun namen achter `--`, bijvoorbeeld `... --python blender/build_cars.py -- golv volvi`.

Per auto levert dat:

| Bestand | Inhoud |
|---|---|
| `assets/blender/<naam>.blend` | Alle onderdelen als losse objecten, om te openen en te bewerken |
| `public/models/<naam>.glb` | Het model dat de game laadt |
| `assets/renders/<naam>_*.png` | Voorbeeldrenders (voor, achter, zij) |

## Het wagenpark

| Naam | Auto | Kenmerken |
|---|---|---|
| `rx7` | Mazdo RX-Zeven (jij) | Klapkoplampen, vleugelspoiler, vier ronde achterlichten, velgen met tien spaken |
| `supremo` | Toyoda Supremo (Sanne) | Lange neus, hoge hoepelspoiler, ovale achterlichten |
| `golv` | Wolfsburg Golv G60 (Henk-Jan) | Driedeurs hatchback, ronde lampen in een zwarte grille met rode streep, zwarte bumpers, kruisspaakvelgen |
| `civik` | Hondo Civik (Joost) | Aflopende hatchback, lichtbalk achter, dikke uitlaat |
| `corso` | Opal Corso (Mehmet) | Kleine hatchback, stalen velgen, Thuisbesteld-dakbox |
| `calibro` | Opal Calibro (Bennie) | Zwarte wig met witte strepen, smalle lampen, turbinevelgen |
| `volvi` | Volvi 240 Kombi (Gerrit) | Hoekige stationwagon, eierkratgrille, chromen bumpers, dakdragers, wieldoppen |
| `spacewagen` | Mitsubushi Space Wagen (Tante Riek) | Hoge MPV, dakrails, staande achterlichten |

### Verkeer en politie

Deze ontwerpen hebben `lod=True`: minder ringen in de carrosserie, eenvoudige banden en geen stuurwiel (~15.000 driehoeken in plaats van ~38.000). De game voegt ze per auto samen tot ongeveer 10 draw calls. Alle effen kleuren komen dan in één materiaal met vertexkleuren. Lak, glas, lampen, kenteken en zwaailichten blijven apart.

| Naam | Auto | Kenmerken |
|---|---|---|
| `police` | Politie Volvi V70 | Blauwe en rood-oranje striping (`side_band`), POLITIE op de portieren, lichtbalk met materialen `BeaconL` en `BeaconR` |
| `tr_sedan` | Opal Vectro | Sedan met kofferbak, zwarte bumpers |
| `tr_hatch` | Fiat Ponto | Vijfdeurs hatchback |
| `tr_estate` | Skodo Octavio Kombi | Stationwagen met dakdragers, trekt de caravan |
| `tr_van` | Volkswagon Transpoorter | Gesloten bestelbus (`gh_inset` en `seal_mat` maken de laadruimte vlak) |

De vrachtwagen en de caravan zijn nog procedureel (de oplegger krijgt per spawn een bedrijfsnaam).

Een ontwerp bestaat uit profielcurves (breedte, hoogte, onderkant, schouderlijn, dakhoogte en dakbreedte langs de lengte), de raamindeling met stijlen, en stijlkeuzes voor neus, achterkant, bumpers, spoiler, uitlaat, velgen en extra's.

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

Je kunt het `.blend`-bestand openen en onderdelen aanpassen. Houd daarbij de objectnamen, custom properties en materiaalnamen aan. Exporteer daarna via *File → Export → glTF 2.0*, met *Include → Custom Properties* aan. Let op: als je `build_cars.py` daarna opnieuw draait, overschrijft het je handmatige wijzigingen.

## Landmarks

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python blender/build_landmarks.py
```

Bouwt `metropool`, `utwente`, `veste`, `brouwerij`, `thuisbesteld` en `barge` uit `landmarks.py` naar `public/models/lm_<naam>.glb`. Een landmark staat met de kant die naar de snelweg moet kijken richting -Y. De game draait hem naar de weg en zet hem op de plek uit het routebestand.
