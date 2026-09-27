#pragma once
// game.h — motore di gioco per il volo (stile supereroe) in C++ puro.
// Nessuna dipendenza: la shell Swift chiama l'API C (game_api.h).

#include <cstdint>
#include <vector>
#include <array>
#include "math.h"

namespace fly {

constexpr int MAX_BUILDINGS = 380;
constexpr int MAX_RINGS = 40;
constexpr int MAX_LASER_SEGS = 48;   // scie residue dei raggi oculari
constexpr int MAX_NPCS = 40;         // pedoni simulati (limite da impostazioni)
constexpr int MAX_PARTICLES = 600;   // limite particelle da impostazioni
constexpr int CITY_GRID = 8;          // 8x8 blocchi città
constexpr float BLOCK = 120.0f;       // metri per blocco città
constexpr float DESPAWN_BEHIND = 200.0f;

enum class GameState : int32_t {
    Menu = 0,        // menu iniziale / game over (camera in orbita sulla città)
    Flying = 1,      // in volo
    Crashed = 2,     // crash → poi torna al Menu
    Walking = 3,     // a terra: cammina, corri, salta
};

struct Building {
    Vec3 pos;         // base al suolo (y = 0)
    Vec3 size;        // metà-larghezza, altezza, metà-profondità (x, y, z)
    float hue;        // 0..1 per la tinta delle finestre
    float damage = 0.0f; // danni accumulati dai raggi oculari (1 = distrutto)
};

struct Ring {
    Vec3 pos;
    Quat orient;
    float radius;
    bool passed;
    bool alive;
};

struct Particle {
    Vec3 pos;
    Vec3 vel;
    float life;       // secondi rimasti
    float maxLife;
    float size;
    float hue;
};

// Pedone NPC: cammina per le strade, scappa se un raggio gli passa vicino.
struct Npc {
    Vec3 pos;         // piedi
    float yaw;        // direzione di cammino
    float speed;      // m/s attuali
    float walkSpeed;
    float runSpeed;
    float phase;      // fase animazione camminata
    int flee;         // 0 = normale, 1 = in fuga
    float fleeTimer;  // secondi rimasti di fuga
    float bodyTint;   // variante colori abiti 0..1
};

struct GameStateData {
    // --- stato logico ---
    GameState state = GameState::Menu;
    double time = 0.0;
    int score = 0;
    int bestScore = 0;
    int ringsPassed = 0;
    float speed = 40.0f;             // m/s
    float altitude = 60.0f;
    float boostFuel = 1.0f;          // 0..1
    float shake = 0.0f;              // trauma camera shake 0..1
    float crashTimer = 0.0f;

    // --- giocatore ---
    Vec3 playerPos{0, 60, 0};        // = piedi del personaggio
    Quat playerQuat;
    float pitch = 0;                 // radianti
    float yaw = 0;
    float roll = 0;

    // --- modalità a piedi ---
    float vy = 0;                    // velocità verticale (salto/caduta)
    bool onGround = true;
    bool landing = false;            // discesa in atterraggio dal volo
    float animPhase = 0;             // fase animazione camminata/corsa (legge il renderer)

    // --- input (valori normalizzati -1..1) ---
    float inputPitch = 0;
    float inputYaw = 0;
    float inputRoll = 0;
    bool  inputBoost = false;

    // --- raggi oculari (laser) ---
    bool  laserActive = false;       // raffica in corso
    float laserHeat = 0.0f;          // 0..1, 1 = surriscaldato
    bool  laserOverheat = false;     // blocco fino a raffreddamento
    float laserTimer = 0.0f;         // durata raffica corrente
    Vec3  laserEnd{0, 0, 0};         // punto d'impatto corrente
    bool  laserHit = false;          // ha colpito qualcosa in questo frame

    struct LaserSegment {
        Vec3 a, b;    // estremi world
        float width;
        float life;   // secondi rimasti
    };
    std::vector<LaserSegment> laserSegs;

    // --- mondo ---
    std::vector<Building> buildings;
    std::vector<Ring> rings;
    std::vector<Particle> particles;
    std::vector<Npc> npcs;
    std::vector<std::pair<Vec3, Vec3>> chunks; // (min, max) per collisioni rapide
    float nextSpawnZ = -400.0f;

    // --- statistiche ---
    double lastFrameMs = 0;
    int frames = 0;

    // --- limiti da impostazioni (qualità grafica) ---
    int npcLimit = MAX_NPCS;
    int particleLimit = MAX_PARTICLES;

    void reset(int best);            // reset mondo + stato Menu
    void startGame();                // "AVVIA PARTITA": spawn a piedi in città
    void jump();                     // salto (solo a piedi, da terra)
    void toggleFly();                // decollo (a piedi) / atterraggio (in volo)
    void setLimits(int maxNpcs, int maxParticles);
    void update(double dt, int32_t screenW, int32_t screenH);
    void updateFlying(double dt);
    void updateWalking(double dt);
    void updateCrashed(double dt);
    float supportHeightAt(float x, float z, float maxY) const;  // quota di supporto (tetti/strada)
    void spawnChunk();
    void spawnRing(const Vec3& pos);
    void spawnBurst(const Vec3& pos, int n, float hue);
    void spawnNpcs();
    void updateNpcs(double dt);
    void recycleWorld();
    bool checkCollisions();
    void updateLaser(double dt);
    void updateParticles(double dt);
    Vec3 camPos() const;
    Quat camQuat() const;
    void camReset() const;   // riallinea la camera smorzata dopo un reset
};

} // namespace fly
