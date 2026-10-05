# A35 Racer: Game Design Document

> *Gas geaven, beuken, winnen!* Van Salland naar Twente.

Versie 0.1, 5 oktober 2026. Opgesteld na het intake-interview.

---

## 1. Concept

**A35 Racer** is een arcade-racegame in de browser. Het combineert het beuken van *Destruction Derby* met het snelweg-racen van *A2 Racer*. Je racet over de N35 en de A35 van Raalte naar Enschede, verdeeld over vijf etappes die naadloos in elkaar overgaan, zoals in *Cruis'n USA*. Plaatsnaamborden markeren de overgangen. Je ontwijkt verkeer en politie en probeert je tegenstanders de vangrail in te duwen.

| | |
|---|---|
| **Genre** | Arcade racing / vehicular combat |
| **Platform** | Webbrowser (desktop en mobiel) |
| **Spelers** | Singleplayer tegen 7 AI-tegenstanders |
| **Inspiratie** | Destruction Derby, A2 Racer, Need for Speed 2 SE, Cruis'n USA |
| **Toon** | Nederlands, met Twentse en Sallandse humor |
| **Doel nu** | Speelbaar prototype, te beginnen met de etappe Hengelo → Enschede |

## 2. Etappes en route

Elke etappe loopt punt-naar-punt, van plaatsnaambord tot plaatsnaambord, en duurt **2 tot 3 minuten**. De hele race duurt zo'n 12 tot 15 minuten.

| # | Etappe | Wegtype | Landmarks |
|---|---|---|---|
| 1 | Raalte → Nijverdal | N35, deels enkelbaans met tegenverkeer | Raadhuis Raalte, Sallandse Heuvelrug, Combiwet-tunnel |
| 2 | Nijverdal → Wierden | N35 | Watertoren Wierden |
| 3 | Wierden → Almelo | N35 → A35 | Heraklus-stadion (Heracles) |
| 4 | Almelo → Hengelo | A35 | Metropool Concertgebouw |
| 5 | **Hengelo → Enschede** *(prototype)* | A35 | zie hieronder |

**Routegetrouwheid:** het echte wegverloop uit OpenStreetMap, dus bochten, afritten, viaducten en wegtype (enkelbaans, 2x2, snelweg). Lange rechte stukken zonder interesse worden ingekort.

**Landmarks voor de prototype-etappe Hengelo → Enschede** (precieze volgorde controleren met OSM):

1. **Metropool Hengelo** (Hart van Zuid), bij de start
2. **Twentekanaal-brug**, een spectaculair crashmoment
3. **Universiteit Twente**, de campus naast de snelweg
4. **Grolsj Veste**, het stadion, verlicht bij zonsondergang
5. **Grolsj-brouwerij Boekelo**, de fabriek met grote tanks bij Enschede-West
6. **Hoofdkantoor Thuisbesteld.nl** (De Ruyterlaan 25), in de stad als finish-landmark

## 3. Kern-gameplay

### 3.1 Winnen

- Je racet tegen **7 tegenstanders**, dus 8 auto's in totaal.
- Je haalt **checkpoints op tijd**. Elk checkpoint geeft extra tijd, en als de tijd op is, is het game over.
- Om door te gaan naar de volgende etappe moet je **in de top 3 eindigen**.
- Punten krijg je voor je finishpositie en voor elke uitgeschakelde tegenstander. Die punten tellen mee voor de highscore.

### 3.2 Beuken en rammen

- Je duwt tegenstanders de vangrail in door gewoon te sturen en te botsen.
- **Ram-aanval (Q/E):** een korte, harde zijwaartse ruk naar links of rechts, met een cooldown van ongeveer 2 seconden.
- **Railing-takedown:** een tegenstander die hard tegen de vangrail wordt gedrukt, krijgt extra schade. Bij total loss volgt een takedown-camera met een korte slow-mo.

### 3.3 Schade per zone (Destruction Derby-stijl)

Elke auto heeft vier zones met elk een eigen schadepercentage:

| Zone | Effect bij schade |
|---|---|
| **Voor** (motor) | Lagere topsnelheid en acceleratie, rook uit de motorkap |
| **Achter** | Minder grip achter, dus sneller uitbreken |
| **Links / Rechts** | Auto trekt naar die kant, en de wielen sturen slechter |

- De schade is ook te zien: deuken (vervormde vertices), losse onderdelen, vonken en rook.
- Een auto is **total loss** als een zone of de totale schade de grens bereikt.
- **Total loss van de speler:** er volgt een wrakmoment en daarna een **respawn** op de weg met een opgelapte auto. De checkpointklok tikt intussen door, dus je verliest tijd.
- **Total loss van een tegenstander:** die is uitgeschakeld voor de rest van de etappe.

### 3.4 Nitro

Er is een boostmeter die je vult door:

- **beuken**: schade toebrengen, met een grote bonus voor een takedown;
- **bijna-botsingen**: rakelings langs verkeer of tegenliggers scheren;
- **driften**: lang driften door bochten.

### 3.5 Verkeer

- Een mix van personenauto's, vrachtwagens, busjes, caravans en trekkers. Als easter egg rijden er oranje bezorgscooters van Thuisbesteld door de stad.
- **Tegenverkeer** op de enkelbaans N35-stukken.
- **Al het verkeer is beukbaar.** Het reageert op duwen, botst door en kun je als wapen gebruiken tegen tegenstanders.

### 3.6 Politie

- Een **wanted level** van 1 tot 5 sterren, dat stijgt door chaos: rammen, botsingen met verkeer en te hard langs flitspalen.
- Hoe hoger het level, hoe meer achtervolgers, met **wegblokkades** verderop.
- Als de politie je klemzet, krijg je een tijdstraf (boete) en zakt het wanted level.

### 3.7 AI-tegenstanders: Twentse personages

Elk personage heeft een eigen auto, een eigen rijstijl en korte taunts in dialect. De namen en teksten zijn een voorstel; de dialectteksten moet een Tukker nog controleren.

| Personage | Auto (fictief) | Rijstijl |
|---|---|---|
| **Gerrit Oude Egberink**, boer uit Wierden | Volvi 240 Kombi met trekhaak | Zwaar, defensief, duwt iedereen opzij |
| **Joost**, UT-student | Hondo Civik met grote spoiler | Snel, roekeloos, crasht vaak zelf |
| **Mehmet**, Thuisbesteld-bezorger | Oranje Opal Corso | Agressief, zigzagt door het verkeer |
| **Henk-Jan**, Tukker met tuningdrang | Wolfsburg Golv G60 | Heeft het op de speler gemunt |
| **Tante Riek** uit Almelo | Mitsubushi Space Wagen | Onvoorspelbaar, remt op rare momenten |
| **Bennie**, Heraklus-supporter | Zwart-witte Opal Calibro | Ramt vooral wie voor hem rijdt |
| **Sanne**, Enschedees racetalent | Toyoda Supremo | Snelste rijder, rijdt schoon |

Voorbeelden van taunts: *"Gas geaven!"*, *"Kump wal goed!"*, *"Wat mot dat noe?"*, *"Ik zal di wal kriegen!"*

**Balans:** lichte rubber-banding. Achterblijvers krijgen een beetje hulp, maar goed rijden levert echt een voorsprong op.

### 3.8 Auto's

- Fictieve **90s-klassiekers** met parodienamen, geïnspireerd op de Supra, Calibra, Golf, Civic en 240.
- De speler kiest een auto. Extra auto's speel je vrij door etappes te winnen.

## 4. Besturing en camera

| Actie | Toetsenbord | Gamepad |
|---|---|---|
| Gas / rem | ↑ / ↓ of W / S | R2 / L2 |
| Sturen | ← / → of A / D | Linkerstick |
| Handrem (drift) | Spatie | ✕ / A |
| Nitro | Shift | ○ / B |
| Ram links / rechts | Q / E | L1 / R1 |
| Pauze | Esc | Options / Start |

- **Touch (mobiel):** knoppen op het scherm voor sturen, gas/rem, nitro en ram. Kantelbesturing is optioneel.
- **Gamepad:** trillen waar de browser dat ondersteunt.
- **Camera:** alleen een chase cam achter de auto. Die schudt bij botsingen, en het beeldveld wordt breder bij nitro.

## 5. Presentatie

- **Visuele stijl:** moderne arcade zoals het conceptplaatje. Felle kleuren, bloom, vonken, motion blur en speed lines.
- **Licht:** **zonsondergang** in alle etappes, het gouden uur. Landmarks zoals de Grolsj Veste zijn verlicht.
- **Muziek:** eigen nummers in de stijl van 90s Nederlandse eurodance en happy hardcore, met Nederlandstalige zang door een vrouwenstem over de route en het beuken. Gemaakt met een AI-muziekplatform; teksten en stijlomschrijvingen staan in [muziek.md](muziek.md).
- **Geluid:** het motorgeluid wordt gesynthetiseerd met de Web Audio API (toerental-afhankelijk). Verder crashes, metaalgeschraap langs de vangrail, sirenes en een omroeper met Twentse kreten.
- **Taal:** Nederlands met Twentse humor.
- **Merknamen:** **parodienamen** (Grolsj, Heraklus, Thuisbesteld.nl). Dat past bij de humor en is veilig als de game ooit gepubliceerd wordt.
- **HUD:** positie (4/8), etappe (5/5), snelheid in km/u, checkpointtijd, boostmeter, schadediagram met de vier zones, wanted-sterren en een minimap van de route.

## 6. Progressie (op termijn)

- Lokale highscores, met beste tijden en punten per etappe (opgeslagen in de browser).
- Unlockbare auto's.
- Statistieken: aantal tegenstanders in de vangrail, grootste crash, topsnelheid, bijna-botsingen.

Online leaderboards en multiplayer vallen voorlopig buiten de scope.

## 7. Techniek

| Onderdeel | Keuze |
|---|---|
| Taal / build | TypeScript + Vite |
| Rendering | Three.js + `postprocessing` (bloom, motion blur, tone mapping) |
| Physics | Eigen arcade-physics, geen physics-engine (zie hieronder) |
| Audio | Web Audio API |
| Invoer | Keyboard events, Gamepad API, touch-overlay |
| Tuning | `lil-gui` debugpaneel om handling en AI live af te stellen |
| Assets | CC0-packs (Kenney, Quaternius, Poly Haven) plus gestileerde landmarks in code, later te vervangen door betere modellen |
| Route-data | OpenStreetMap-export van de N35/A35, omgezet naar een wegspline |
| Hosting | Git-repo op GitHub, automatische deploy naar **GitHub Pages** via Actions |

**Physics-aanpak:** de weg is een spline. Auto's rijden in weg-coördinaten: de afstand langs de weg plus de zijwaartse positie. De vangrail is dan een eenvoudige zijwaartse grens met een stevige botsrespons, en dat maakt railing-takedowns robuust en goed af te stellen. Auto-tegen-auto-botsingen worden afgehandeld als georiënteerde rechthoeken (2D-OBB) met impuls en draaiing. Hoogte (heuvels, bruggen) komt uit de spline. Zo krijg je een NFS2SE-gevoel: auto's met gewicht, driften met de handrem, en stevige maar vergevingsgezinde botsingen.

## 8. Mijlpalen

### M1: Rijden + beuken *(afgerond, oktober 2026)*

Een grey-box stuk A35 (2x2 met vangrail, ongeveer 3 km, een paar bochten en een viaduct).

- [x] Projectopzet: Vite, TypeScript, Three.js, git en een GitHub Pages-deploy
- [x] Spelersauto met semi-arcade handling (gewicht, handrem-drift)
- [x] Chase cam met camera-shake
- [x] 3 AI-auto's die racen en terugduwen
- [x] Botsingen tussen auto's onderling en met de vangrail
- [x] Ram-aanval Q/E met cooldown
- [x] Schade per zone, met effect op het rijgedrag en zichtbare deuken, vonken en rook
- [x] Total loss en takedown voor de AI, respawn voor de speler
- [x] Nitro gevuld door beuken, bijna-botsingen en driften
- [x] Besturing met toetsenbord en gamepad
- [x] Debugpaneel voor tuning
- [x] Minimale HUD: snelheid, positie, boost, schade

**Klaar als:** het rijden lekker voelt en iemand de vangrail in duwen bevredigend is.

### M2: Verkeer, politie en het volledige veld

- 7 tegenstanders met verschillende rijstijlen en lichte rubber-banding
- Verkeer in alle richtingen, beukbaar, met bijna-botsing-detectie
- Politie met wanted level, achtervolging en wegblokkades
- Muziek: een titelloop en twee racenummers met zang (zie [muziek.md](muziek.md)), een muziekspeler met eigen volume, "Nu speelt"-melding en volgende nummer, en een gedempt (gefilterd) geluid tijdens pauze en slow-motion

### M3: De echte etappe Hengelo → Enschede

- OSM-route omgezet naar een wegspline, met afritten en viaducten
- Omgeving: bomen, geluidsschermen, borden en bebouwing
- De zes landmarks
- Sfeer: zonsondergang, post-processing en verlichting

### M4: Verticale slice

- Checkpoint-timer, finish en top-3-regel
- Twentse personages met hun taunts, en een omroeper
- Geluidseffecten (opgenomen samples in plaats van synthese)
- Menu's, autokeuze, lokale highscores
- Touch-besturing voor mobiel

### M5: De volledige race

- De etappes 1 tot en met 4, met naadloze overgangen via plaatsnaamborden
- Tegenverkeer op de N35
- Unlocks en statistieken

## 9. Open punten en aannames

- **Dialect:** de Twentse teksten moet iemand uit de regio controleren en aanvullen.
- **GitHub:** publieke repo `a35-racer`, met automatische deploy naar GitHub Pages.
- **Snelheden:** de km/u op de HUD worden overdreven weergegeven (topsnelheid rond 250+ km/u) voor het arcadegevoel.
- **Checkpointtijden** en de **balans van schade en boost** stellen we af tijdens het testen.
- **Muziek:** zelf gemaakt met een AI-muziekplatform. Bij publicatie moeten de gebruiksrechten van dat platform kloppen (zie [muziek.md](muziek.md)).
