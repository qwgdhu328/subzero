# Piano di lavoro — SuperFlight (Superman 3D)

> **Come usare questo file**: in una nuova chat scrivi solo:
> *"Leggi superflight/Piano.md e continua il task, rispetta le regole operative."*
> L'agente riprende da dove si era fermato, senza dover rispiegare nulla.

---

## Regole operative per l'agente AI (LEGGI PRIMA DI TUTTO)

1. **Il turno di lavoro dura 50 minuti dall'inizio della sessione.**
   - Lavora in continuo ai task della sezione "Prossimi task", senza chiedere conferma a ogni passaggio.
   - Quando sono passati ~50 minuti (o se la sessione sta per scadere): **STOP PULITO**, in quest'ordine:
     a. chiudi il punto di lavoro corrente in uno stato stabile (compila, test passa);
     b. esegui la verifica (punto 4 qui sotto);
     c. **commit + push** di ciò che è completo;
     d. **aggiorna questo file**: sposta il task completato in "Fatto", aggiorna "Prossimo task" con lo stato preciso di quello interrotto (cosa è fatto, cosa manca);
     e. termina la risposta con: `STOP 50 MIN — riprendere con: leggi superflight/Piano.md e continua`.
2. Non aspettare il limite: se un task finisce in anticipo, passa subito al successivo.
3. **Un task = un commit** (o più commit se è lungo). Messaggi descrittivi in italiano.
4. Verifica obbligatoria prima di ogni commit:
   ```bash
   cd superflight/native && g++ -std=c++17 -O2 -Wall -Wextra -o /tmp/test_engine \
     test/main.cpp engine/game.cpp engine/game_api.cpp && /tmp/test_engine
   ```
5. Non rompere la build CI: modifiche piccole e verificabili, niente rewrite completi a fine turno.
6. Se l'utente chiede qualcos'altro, fallo: le regole valgono per il lavoro in autonomia.

---

## Stato del progetto (aggiornato al 27/09/2026)

> **Mappa dal documento di design "Project Krypton" (v4.0)** — cosa è già nel motore:
> - **Modulo 2** (drag atmosferico Cd(Mach) + rho esponenziale): ✅ implementato nel volo
> - **Modulo 3** (FOV quadratico in Mach, kick boom): ✅ implementato; aberrazione cromatica in coda
> - **Modulo 9** (streaming predittivo): ✅ versione semplificata (spawn chunk lungo traiettoria)
> - **Modulo 10** (atmosfera): ✅ semplificato (cielo scurisce con la quota, fog svanisce)
> - **Modulo 13** (folla): ✅ versione ridotta (40 NPC con fuga dal laser)
> - **Modulo 17** (Doppler): da fare con il task Audio
> - **Moduli 4/5/7/8/11/12** (Voronoi, GPU PBD, SPH, X-Ray, SVO, Utility AI): fuori scope per
>   engine custom Metal/iOS; adattamenti semplificati già in Piano (droni, soffio toy)
> - **Modulo 14/15** (pipeline AI 3D locale): richiede GPU NVIDIA; see Piano §asset esterni

- **Motore C++** (`superflight/native/engine`): volo, camminata/salto/corsa, laser oculari con
  calore e raycast, 40 NPC pedoni che scappano dal raggio, anelli, crash/respawn,
  camera smorzata con reset reale. Test nativi OK (menu/salto/volo/atterraggio + NPC in fuga).
- **Renderer Metal** (`superflight/ios/SuperFlight/Renderer.swift`): mesh sferiche/capsulari
  generate a runtime, Superman articolato (2 segmenti per arto), mantello animato su griglia
  5×4 (12 quad), NPC animati con abiti variati, strade con corsie/strisce, nuvole, finestre
  procedurali per edifici, glow additivo per laser/particelle/anelli.
- **HUD**: menu AVVIA PARTITA, tasti SALTO/VOLO/LASER con barra calore, pass-through dei
  tocchi (joystick dinamico funzionante dopo fix `touch.attach(to:)`).
- **CI**: GitHub Actions (`superflight-ios.yml`) compila motore + app, produce IPA non firmata
  come artifact `superflight-ipa-unsigned`. Ultima run verde: 36286175367 (commit 2a02c1c).
- **Ultimo fix**: crash all'avvio (mantello: 16 quad su griglia da 10 punti) — risolto.

---

## Prossimi task (in ordine, con stima)

> Roadmap adattata dal "Documento di architettura Project Superman" (design AAA): le idee
> grandi (Voronoi destruction, SPH, SVO pathfinding, nuvole volumetriche) sono riportate qui
> in versione fattibile per il nostro engine Metal/iOS. Le versioni complete restano fuori
> scope per un engine custom su iPhone.

1. **[45 min] Audio minimal**: effetti senza asset esterni via AVAudioEngine — laser,
   esplosioni, passi, vento in volo, **boom sonico**. Toggle nel pannello IMPOSTAZIONI.
2. **[40 min] Effetto velocità (da §2.3)**: linee di vento/steak alle alte velocità,
   aberrazione simulata con vignette dinamica, turbo-roll della camera sopra Mach 1.
3. **[60 min] Droni nemici (da §6.1, semplificato)**: volano con steering Basilare (senza
   SVO), sparano proiettili lenti, distruttibili col laser (+50 punti); i detriti usano
   il sistema Debris già presente.
4. **[30 min] Minimappa HUD**: Superman, NPC, anelli, edifici danneggiati.
5. **[20 min] README**: installazione IPA (Sideloadly/AltStore) + comandi CI.
6. **[45 min, opzionale] Soffio congelante (da §4.2, semplificato)**: jet di particelle
   azzurre che congela gli NPC in posa rigida per 5 s (versione toy del sistema SPH).

> Nota settings (fatto, commit 73b08ca): il pannello IMPOSTAZIONI è raggiungibile col
> pulsante ⚙ nel menu. Qualità Alta/Media/Lite cambia limiti NPC/particelle (via
> `fly_set_limits`), nuvole e cielo. Se si aggiungono nuove opzioni grafiche, inserirle
> in quel pannello e in `GameSettings.swift`.

---

## Fatto

- [x] Menu AVVIA PARTITA + modalità a piedi (cammina/salta/corri) + tasti HUD
- [x] Fix joystick morto (weak view mai assegnata)
- [x] Superman mesh 3D articolata + mantello animato + NPC che scappano dai laser
- [x] Strade 3D, nuvole, finestre realistiche
- [x] Fix crash mantello (2a02c1c)
- [x] Blindatura anti-crash: bound renderer + drawParticles buffer coerente (73b08ca)
- [x] IMPOSTAZIONI: qualità grafica Alta/Media/Lite, sensibilità joystick, 60/120 FPS,
      persistite in UserDefaults e applicabili al volo (73b08ca, run CI 36288970870 verde)
- [x] Animazioni cinematiche: corsa con bounce/gomiti, fase dal motore, volo 3000 km/h (1c8d819)
- [x] Boom sonico a Mach 1: FOV dinamico 70→102°, shockwave anello, vetri che scoppano,
      shake + burst (87fdef2, run CI 36290007626 verde)
- [x] Detriti fisici dal collasso edifici: gravità, rimbalzo smorzato, tumble, despawn
      (MAX_DEBRIS 120; disegnati come cubi cemento con rotazione)
