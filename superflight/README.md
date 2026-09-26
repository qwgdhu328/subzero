# ✈️ SuperFlight

Gioco **3D di volo** stile supereroe: voli tra i grattacieli di una città infinita, attraversa gli **anelli** per punti e boost, evita gli edifici.

**Architettura**: motore di gioco in **C++17 puro** (fisica, città procedurale, collisioni, particelle) + shell **Swift/Metal** per il rendering 3D su iOS. Le prestazioni critiche sono tutte in C++; Swift fa solo da ponte e disegna.

## Prestazioni misurate (motore puro, PC Windows modesto)

```
21600 tick @120Hz simulati in 12,3 ms  →  0,57 µs/tick  →  ~14.600x real-time
```

Su iPhone il motore usa <0,1% del budget di frame: tutto il tempo va a Metal.

## Struttura

```
superflight/
├── native/                 # MOTORE C++ (portabile, testabile)
│   ├── engine/
│   │   ├── math.h          # Vec3, Quat (slerp), Mat4 — zero dipendenze
│   │   ├── game.h/.cpp     # fisica volo, città procedurale, anelli, collisioni
│   │   ├── game_api.h/.cpp # API C stabile per il bridge Swift
│   │   └── ...
│   └── test/main.cpp       # harness: simula 3 minuti a 120Hz e misura le prestazioni
└── ios/
    └── SuperFlight/
        ├── App.swift               # AppDelegate
        ├── GameViewController.swift # controller: MTKView + motore + HUD
        ├── Renderer.swift           # rendering Metal (edifici, anelli, particelle)
        ├── Shaders.metal            # vertex/fragment: finestre procedurali, glow, nebbia
        ├── TouchController.swift    # joystick virtuale + boost
        ├── HUDView.swift            # punteggio, velocità, barra boost, menu
        ├── BridgingHeader.h         # espone game_api.h a Swift
        └── Info.plist
```

## Gameplay

- **Trascina il dito** = vola (su/giù = quota, destra/sinistra = svolta)
- **Secondo dito sullo schermo** = **BOOST** (consuma carburante)
- **Anelli azzurri** = +50 punti e +25% boost
- **Tocca un grattacielo** = crash 💥 (camera shake + particelle)
- La città è **infinita e procedurale**: i blocchi si generano davanti e si riciclano dietro

## Build

### Test motore (qualsiasi piattaforma, nessuna dipendenza)

```bash
cd superflight/native
g++ -std=c++17 -O2 -o test_engine test/main.cpp engine/game.cpp engine/game_api.cpp
./test_engine
```

### App iOS (serve macOS/Xcode)

```bash
cd superflight
brew install xcodegen        # se mancante
xcodegen generate
open SuperFlight.xcodeproj   # Run su simulatore o dispositivo
```

Oppure via **GitHub Actions**: il workflow `.github/workflows/ios-build.yml` compila il test motore su Ubuntu **e** builda l'app su macOS con Xcode (simulatore iPhone 15 Pro).

## Design tecnico

| Livello | Tecnologia | Ruolo |
|---|---|---|
| Logica/fisica | **C++17** (no STL heavy, no alloc per frame) | quaternioni, slerp camera, AABB collisioni, MT19937 città |
| Ponte | **API C** (`game_api.h`) | tipi POD, nessuna esposizione C++ a Swift |
| Rendering | **Metal** + shader custom | istancing edifici, finestre procedurali in GPU, glow additivo, nebbia esponenziale |
| UI | **UIKit** (HUD) | displaylink a 120Hz, zero overhead SwiftUI |
