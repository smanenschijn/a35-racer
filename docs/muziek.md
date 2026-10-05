# A35 Racer: muziek

Eigen nummers in de sfeer van 90s Nederlandse eurodance en happy hardcore, met Nederlandstalige zang door een vrouwenstem over de route en het beuken. Ze worden gemaakt met een AI-muziekplatform en in mijlpaal 2 in de game ingebouwd.

## Platform

| Platform | Waarom |
|---|---|
| **Suno** *(aanbevolen)* | Je geeft je eigen songtekst en een stijlomschrijving. Je krijgt een volledig nummer met zang terug. Sterk in dance-genres en Nederlandse zang. |
| **Udio** | Alternatief met vergelijkbare werking. Probeer het als Suno niet de juiste klank geeft. |

**Werkwijze in Suno:** kies *Custom*. Plak de **songtekst** in het tekstveld en de **stijl** in het stijlveld. Genereer een paar versies en kies de beste. Bevalt een deel niet, dan kun je het opnieuw laten maken met *Extend* of *Replace section*.

**Twee aandachtspunten:**
- **Geen artiestennamen in de stijlomschrijving.** Platforms weigeren die meestal, en het nummer moet een eigen nummer zijn, geen kopie. De stijl hieronder beschrijft de klank zelf: tempo, kick, synths en zang.
- **Gebruiksrechten.** Bij Suno mocht je bij mijn laatste kennis nummers van het gratis abonnement alleen niet-commercieel gebruiken. Met een betaald abonnement kreeg je commerciële rechten op nummers die je in die periode maakt. Controleer de actuele voorwaarden. Wil je de game ooit publiceren of verkopen, maak de definitieve versies dan op een betaald abonnement.

## Nummers

Drie nummers: twee racenummers met zang en een instrumentale loop voor het titelscherm.

---

### 1. "A35" (eurodance-anthem, racenummer)

**Stijl** (plak in het stijlveld):

```
90s eurodance, 140 bpm, powerful female diva vocals, Dutch lyrics, punchy four-on-the-floor kick, offbeat bass, bright synth stabs, euro piano chords, rave hoover lead in the drop, big uplifting sing-along chorus, energetic 1995 dance anthem
```

**Songtekst:**

```
[Intro]
(Gas geaven!)

[Verse 1]
De zon zakt weg achter Salland
Raalte in de spiegel, het stuur in mijn hand
Acht motoren brullen, wachten op het sein
Drie, twee, één — wie er wint, dat zal ik zijn!

[Pre-Chorus]
Nijverdal, Wierden, Almelo
Hengelo — de borden vliegen zo!
Hou je vast, hou je vast...

[Chorus]
A35 — rij met me mee
Door de nacht van Raalte naar Enschede!
A35 — gas erop
Gas geaven, niemand houdt ons op!

[Drop]
(A35!)

[Verse 2]
Een blauwe Golf die kruipt naast mij
Ik geef een ram en hij schuift opzij
Vonken op de vangrail, staal tegen staal
In Twente rijden wij het snelst van allemaal!

[Pre-Chorus]
Nijverdal, Wierden, Almelo
Hengelo — de borden vliegen zo!
Hou je vast, hou je vast...

[Chorus]
A35 — rij met me mee
Door de nacht van Raalte naar Enschede!
A35 — gas erop
Gas geaven, niemand houdt ons op!

[Bridge]
Van Salland naar Twente... (Twente!)
Kump wal goed... (Gas geaven!)

[Final Chorus]
A35 — rij met me mee
Door de nacht van Raalte naar Enschede!
A35 — gas erop
Gas geaven, niemand houdt ons op!

[Outro]
(A35...)
```

---

### 2. "Beuk 'm de vangrail in" (happy hardcore, racenummer)

**Stijl:**

```
90s Dutch happy hardcore, 170 bpm, distorted gabber kick drum, pitched-up female vocals, Dutch lyrics, hoover synth lead, rave piano riff, air horns, euphoric sing-along chorus, fast and energetic rave
```

**Songtekst:**

```
[Intro]
(Beuken! Beuken!)

[Verse 1]
Hoor je die sirene, zie je dat blauwe licht?
Henk-Jan in m'n spiegel met een grijns op z'n gezicht
Gerrit in z'n Volvo gaat voor niemand opzij
Maar vannacht is de vangrail voor hem — niet voor mij!

[Chorus]
Beuk 'm, beuk 'm, beuk 'm de vangrail in!
Gas geaven, gas geaven, ik wil winnen, ik wil winnen!
Beuk 'm, beuk 'm, harder dan het licht
Beuk 'm, beuk 'm, tot z'n motor zwicht!

[Drop]
(Beuken!)

[Verse 2]
Nitro in de tank en de teller op het rood
Ik scheer langs een vrachtwagen, centimeters, bijna dood
Vonken in de nacht, de A35 staat in brand
Dit is Twente, schatje — ga maar aan de kant!

[Chorus]
Beuk 'm, beuk 'm, beuk 'm de vangrail in!
Gas geaven, gas geaven, ik wil winnen, ik wil winnen!
Beuk 'm, beuk 'm, harder dan het licht
Beuk 'm, beuk 'm, tot z'n motor zwicht!

[Bridge]
Alle handen omhoog voor Twente!
Alle handen omhoog!

[Final Chorus]
Beuk 'm, beuk 'm, beuk 'm de vangrail in!
Gas geaven, gas geaven, ik wil winnen, ik wil winnen!
Beuk 'm, beuk 'm, harder dan het licht
Beuk 'm, beuk 'm, tot z'n motor zwicht!
```

---

### 3. "Plaatsnaambord" (instrumentaal, titelscherm)

Zet in Suno de optie **Instrumental** aan; er is geen songtekst nodig.

**Stijl:**

```
instrumental 90s eurodance, 132 bpm, sunset mood, warm analog synth pads, euro piano chords, light four-on-the-floor kick, melodic synth lead, nostalgic and uplifting, seamless loop, no vocals
```

## Aanleveren

- Zet de bestanden in `public/music/` met deze namen:
  - `a35.mp3`
  - `beuk-m-de-vangrail-in.mp3`
  - `plaatsnaambord.mp3`
- Ik voeg ze toe aan de game en comprimeer ze waar nodig (doel: rond de 3 à 4 MB per nummer).
- Laat in een notitie weten waarmee en op welk abonnement je ze gemaakt hebt. Dan zet ik dat in de credits.

## Inbouw in de game (mijlpaal 2)

- Op het titelscherm speelt *Plaatsnaambord* als loop.
- Tijdens de race spelen de twee racenummers om en om.
- Aan het begin van elk nummer verschijnt kort een "Nu speelt"-melding in beeld.
- Met **N** ga je naar het volgende nummer; het muziekvolume staat los van de geluidseffecten.
- Tijdens pauze en bij een takedown in slow-motion klinkt de muziek gedempt, alsof hij door een muur komt.

## Teksten nakijken

- De dialectwoorden (*"Gas geaven"*, *"Kump wal goed"*) moet een Tukker nog controleren.
- Pas gerust regels aan. AI-zang klinkt het best met korte regels en een vast ritme per regel.
