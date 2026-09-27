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
constexpr int MAX_NPCS = 60;         // pedoni simulati (limite da impostazioni; 60 = Ultra 4K)
constexpr int MAX_DEBRIS = 120;      // detriti fisici simultanei
constexpr int MAX_PARTICLES = 900;   // limite particelle da impostazioni (900 = Ultra 4K)
constexpr int MAX_ENEMIES = 12;      // nemici simultanei (GAMEPLAY_PHYSICS_AAA §2)
constexpr int MAX_PROJECTILES = 80;  // proiettili nemici simultanei
constexpr int CITY_GRID = 8;          // 8x8 blocchi città
constexpr float BLOCK = 120.0f;       // metri per blocco città
constexpr float DESPAWN_BEHIND = 200.0f;

enum class GameState : int32_t {
    Menu = 0,        // menu iniziale / game over (camera in orbita sulla città)
    Flying = 1,      // in volo
    Crashed = 2,     // crash → poi torna al Menu
    Walking = 3,     // a terra: cammina, corre, salta
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

// Detriti fisici (§3.2 del design): cadono con gravità e rimbalzano sulla strada.
struct Debris {
    Vec3 pos;
    Vec3 vel;
    Vec3 size;        // mezzo-lato del cubetto (0.8..2.5 m)
    float spinAxis;   // asse di rotazione casuale per il tumble
    float spinRate;
    float spin;
    float rest;       // tempo di riposo rimanente (poi despawn)
    bool active;
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

// ---------------------------------------------------------------------- //
//  Gameplay AAA (GAMEPLAY_PHYSICS_AAA.md): fluidodinamica, nemici, carriera

struct FluidDynamics {
    Vec3 windVelocity;         // vento corrente al punto giocatore (m/s)
    float turbulenceLevel = 0; // 0..1 (scie di vortice + effetto suolo)
};

enum class EnemyType : int32_t {
    Drone = 0,   // nemico base: insegue e spara
    Scout = 1,   // veloce, mantiene le distanze
    Turret = 2,  // (futuro) stazionario ma accurato
    Boss = 3,    // (futuro) boss fight 1v1
    Swarm = 4,   // (futuro) sciame coordinato
};

// Nemico volante con macchina a stati AI: 0=patrol 1=chase 2=attack 3=retreat.
struct Enemy {
    EnemyType type = EnemyType::Drone;
    Vec3 pos;
    Vec3 vel;
    float health = 1.0f;
    float maxHealth = 1.0f;
    float radius = 2.4f;
    float yaw = 0;
    int aiState = 0;
    float stateTimer = 0;
    Vec3 targetPos;
    float detectionRange = 320.0f;
    float attackRange = 160.0f;
    float fireTimer = 1.0f;
    float fireCooldown = 2.0f;
    float aggression = 0.2f;    // 0..1, cresce quando subisce danno
    float intelligence = 0.6f;  // qualità AI: Scout 0.9, Drone 0.6
    float phase = 0;            // variazione individuale traiettoria
};

struct Projectile {
    Vec3 pos;
    Vec3 vel;
    float life = 4.0f;
    float maxLife = 4.0f;
    float radius = 1.6f;
    int owner = 1;              // 0 = Superman, 1 = nemico
    float damage = 0.15f;       // frazione di salute tolta a pieno colpo
};

// Albero abilità (5 rami, 0..5 livelli ciascuno): effetti cablati nel motore.
struct PlayerSkills {
    float speedMax = 0;         // +6%/livello alla velocità di boost
    float maneuverability = 0;  // +10%/livello a virata e rollio
    float durability = 0;       // -12%/livello ai danni subiti
    float laserPower = 0;       // +25%/livello al danno laser sui nemici
    float detection = 0;        // -10%/livello al raggio di rilevamento nemico

    float level(int i) const {
        switch (i) {
            case 0: return speedMax;
            case 1: return maneuverability;
            case 2: return durability;
            case 3: return laserPower;
            default: return detection;
        }
    }
    void upgrade(int i) {
        switch (i) {
            case 0: if (speedMax < 5.0f) speedMax += 1.0f; break;
            case 1: if (maneuverability < 5.0f) maneuverability += 1.0f; break;
            case 2: if (durability < 5.0f) durability += 1.0f; break;
            case 3: if (laserPower < 5.0f) laserPower += 1.0f; break;
            default: if (detection < 5.0f) detection += 1.0f; break;
        }
    }
};

// Profilo carriera: sopravvive ai reset della partita (progressione permanente).
struct PlayerProfile {
    int totalScore = 0;
    int enemiesDefeated = 0;
    int comboBest = 0;
    PlayerSkills skills;
    int skillPoints = 0;
    int nextSkillScore = 3000;  // punteggio per il prossimo punto abilità
};

// Combo: azioni consecutive entro 3 s → moltiplicatore punteggio fino a 2.0x.
struct ComboState {
    int combo = 0;
    float comboTimer = 0;
    float multiplier = 1.0f;

    void addAction() {
        combo++;
        comboTimer = 3.0f;
        multiplier = 1.0f + combo * 0.05f;
        if (multiplier > 2.0f) multiplier = 2.0f;
    }
    void update(float dt) {
        if (comboTimer > 0.0f) {
            comboTimer -= dt;
            if (comboTimer <= 0.0f) { combo = 0; multiplier = 1.0f; }
        }
    }
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
    float sonicRipple = 0.0f;        // onda d'urto post-Mach 1 (0..1, decade)
    bool  supersonic = false;        // oltre Mach 1 (per FOV/effetti)

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
    std::vector<Debris> debris;
    std::vector<Npc> npcs;
    std::vector<std::pair<Vec3, Vec3>> chunks; // (min, max) per collisioni rapide
    float nextSpawnZ = -400.0f;

    // --- statistiche ---
    double lastFrameMs = 0;
    int frames = 0;

    // --- limiti da impostazioni (qualità grafica) ---
    int npcLimit = MAX_NPCS;
    int particleLimit = MAX_PARTICLES;

    // --- gameplay AAA ---
    FluidDynamics fluid;              // vento + turbolenza correnti
    PlayerProfile profile;            // carriera: NON viene azzerata dal reset
    ComboState combo;                 // combo corrente della partita
    float health = 1.0f;              // integrità giocatore 0..1
    float hitTimer = 0;               // secondi dall'ultimo colpo subito
    std::vector<Enemy> enemies;
    std::vector<Projectile> projectiles;
    float enemySpawnTimer = 3.0f;

    void updateEnemies(double dt);
    void updateProjectiles(double dt);
    void updateFluid(double dt);      // vento procedurale + turbolenza + effetti
    void spawnEnemyWave();
    void damagePlayer(float amount);
    void addComboAction(int baseScore);
    bool upgradeSkill(int skill);

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
    void spawnDebris(const Vec3& pos, int n);
    void updateDebris(double dt);
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
