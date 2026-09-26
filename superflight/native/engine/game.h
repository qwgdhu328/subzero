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
constexpr int CITY_GRID = 8;          // 8x8 blocchi città
constexpr float BLOCK = 120.0f;       // metri per blocco città
constexpr float DESPAWN_BEHIND = 200.0f;

enum class GameState : int32_t {
    Menu = 0,
    Flying = 1,
    Crashed = 2,
};

struct Building {
    Vec3 pos;         // base al suolo (y = 0)
    Vec3 size;        // metà-larghezza, altezza, metà-profondità (x, y, z)
    float hue;        // 0..1 per la tinta delle finestre
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
    Vec3 playerPos{0, 60, 0};
    Quat playerQuat;
    float pitch = 0;                 // radianti
    float yaw = 0;
    float roll = 0;

    // --- input (valori normalizzati -1..1) ---
    float inputPitch = 0;
    float inputYaw = 0;
    float inputRoll = 0;
    bool  inputBoost = false;

    // --- mondo ---
    std::vector<Building> buildings;
    std::vector<Ring> rings;
    std::vector<Particle> particles;
    std::vector<std::pair<Vec3, Vec3>> chunks; // (min, max) per collisioni rapide
    float nextSpawnZ = -400.0f;

    // --- statistiche ---
    double lastFrameMs = 0;
    int frames = 0;

    void reset(int best);
    void update(double dt, int32_t screenW, int32_t screenH);
    void updateFlying(double dt);
    void updateCrashed(double dt);
    void spawnChunk();
    void spawnRing(const Vec3& pos);
    void spawnBurst(const Vec3& pos, int n, float hue);
    void recycleWorld();
    bool checkCollisions();
    void updateParticles(double dt);
    Vec3 camPos() const;
    Quat camQuat() const;
    void camReset() const;   // riallinea la camera smorzata dopo un reset
};

} // namespace fly
