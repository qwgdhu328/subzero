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

1. **[30 min] Blindatura anti-crash**: rassegna tutti gli accessi ad array/buffer nel renderer
   (drawNpcs, drawParticles, beamMatrix, cape grid) e assicura bounds coerenti; controlla che
   ogni `ensure()` sia seguito da bind del buffer restituito.
2. **[45 min] Audio minimal**: effetti senza asset esterni via AVAudioEngine — laser (tono
   rovesciato), esplosioni (rumore filtrato), passi, vento in volo. Toggle audio nell'HUD.
3. **[40 min] Esplosioni migliori**: quando un edificio collassa, detriti (particelle con
   gravità e rimbalzo sul terreno) + colonna di fumo + onda d'urto della camera.
4. **[60 min] Droni nemici**: volano nella città, sparano proiettili lenti, distruttibili con
   un colpo di laser (+50 punti); punteggio salvato nel best.
5. **[30 min] Minimappa HUD**: posizione Superman, NPC, anelli e edifici danneggiati.
6. **[20 min] README**: istruzioni installazione IPA (Sideloadly/AltStore) e comandi CI.

---

## Fatto

- [x] Menu AVVIA PARTITA + modalità a piedi (cammina/salta/corri) + tasti HUD
- [x] Fix joystick morto (weak view mai assegnata)
- [x] Superman mesh 3D articolata + mantello animato + NPC che scappano dai laser
- [x] Strade 3D, nuvole, finestre realistiche
- [x] Fix crash mantello (2a02c1c)
