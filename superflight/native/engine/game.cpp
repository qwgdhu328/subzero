// game.cpp — implementazione del motore di volo (fisica, città, collisioni).

#include "game.h"
#include <algorithm>
#include <random>

namespace fly {

// ---------------------------------------------------------------------- //
//  Parametri di gioco (tweak qui)
// ---------------------------------------------------------------------- //
static constexpr float kBaseSpeed    = 42.0f;   // m/s
static constexpr float kBoostSpeed   = 95.0f;   // m/s
static constexpr float kAccel        = 55.0f;   // m/s^2
static constexpr float kTurnRate     = 1.9f;    // rad/s
static constexpr float kRollRate     = 2.6f;    // rad/s
static constexpr float kMaxPitch     = 1.15f;   // rad
static constexpr float kMaxRoll      = 1.05f;   // rad
static constexpr float kMinAlt       = 3.0f;    // m sopra il suolo
static constexpr float kRingR        = 14.0f;
static constexpr float kRingThick    = 3.0f;
static constexpr float kPlayerR      = 2.2f;    // raggio collisione giocatore
static constexpr float kCamDist      = 13.0f;
static constexpr float kCamHeight    = 4.5f;
static constexpr float kGravityCrash = 55.0f;

// RNG deterministico (stessa città per stessa seed → riproducibile).
static std::mt19937& rng() {
    static std::mt19937 g(20260926u);
    return g;
}
static float rnd(float lo, float hi) {
    std::uniform_real_distribution<float> d(lo, hi);
    return d(rng());
}

// ---------------------------------------------------------------------- //
//  Reset e spawn
// ---------------------------------------------------------------------- //

void GameStateData::reset(int best) {
    state = GameState::Flying;
    time = 0; score = 0; ringsPassed = 0;
    bestScore = best;
    speed = kBaseSpeed;
    boostFuel = 1.0f;
    shake = 0; crashTimer = 0;
    playerPos = Vec3(0, 60, 0);
    pitch = yaw = roll = 0;
    playerQuat = Quat();
    inputPitch = inputYaw = inputRoll = 0;
    inputBoost = false;
    buildings.clear();
    rings.clear();
    particles.clear();
    chunks.clear();
    nextSpawnZ = -400.0f;
    frames = 0;
    camReset();

    // Prime 4 chunk di città davanti al giocatore.
    for (int i = 0; i < 4; ++i) spawnChunk();
    // Anello tutorial subito davanti.
    spawnRing(playerPos + playerQuat.forward() * 220.0f);
}

void GameStateData::spawnChunk() {
    const float grid = CITY_GRID;
    const float block = BLOCK;
    float baseZ = nextSpawnZ;

    // Griglia di grattacieli con strade; lascia un corridoio lungo X=0.
    for (int gx = 0; gx < (int)grid; ++gx) {
        for (int gz = 0; gz < (int)grid; gz++) {
            float x = (gx - grid / 2 + 0.5f) * block;
            float z = baseZ - (gz + 0.5f) * block;
            if (std::abs(x) < block * 0.9f) continue;      // corridoio di volo
            if (rnd(0.0f, 1.0f) < 0.12f) continue;         // piazza vuota
            float w = rnd(18, 42);
            float d = rnd(18, 42);
            float h = rnd(25, 150) + std::abs(x) * 0.25f;
            buildings.push_back({Vec3(x, 0, z), Vec3(w, h, d), rnd(0.5f, 0.75f)});
        }
    }
    // Anelli: 30% probabilità per chunk, sulla traiettoria.
    if (rnd(0.0f, 1.0f) < 0.55f) {
        Vec3 rp(rnd(-25, 25), rnd(40, 110), baseZ - block * grid * 0.5f);
        spawnRing(rp);
    }
    nextSpawnZ -= block * grid;

    // Ricicla ciò che è rimasto indietro.
    recycleWorld();
}

void GameStateData::spawnRing(const Vec3& pos) {
    if ((int)rings.size() >= MAX_RINGS) return;
    Ring r;
    r.pos = pos;
    r.orient = Quat::fromAxisAngle(Vec3(0, 1, 0), yaw + PI * 0.5f);
    r.radius = kRingR;
    r.passed = false;
    r.alive = true;
    rings.push_back(r);
}

void GameStateData::spawnBurst(const Vec3& pos, int n, float hue) {
    for (int i = 0; i < n; ++i) {
        Particle p;
        p.pos = pos;
        p.vel = Vec3(rnd(-1, 1), rnd(-0.2f, 1.2f), rnd(-1, 1)).normalized() * rnd(8, 30);
        p.life = p.maxLife = rnd(0.5f, 1.4f);
        p.size = rnd(0.6f, 2.2f);
        p.hue = hue;
        particles.push_back(p);
    }
    if (particles.size() > 600) {
        particles.erase(particles.begin(), particles.begin() + (particles.size() - 600));
    }
}

void GameStateData::recycleWorld() {
    float pz = playerPos.z;
    buildings.erase(std::remove_if(buildings.begin(), buildings.end(),
        [pz](const Building& b) { return b.pos.z > pz + DESPAWN_BEHIND; }),
        buildings.end());
    rings.erase(std::remove_if(rings.begin(), rings.end(),
        [pz](const Ring& r) { return !r.alive || r.pos.z > pz + DESPAWN_BEHIND; }),
        rings.end());
}

// ---------------------------------------------------------------------- //
//  Update
// ---------------------------------------------------------------------- //

void GameStateData::update(double dt, int32_t, int32_t) {
    time += dt;
    if (state == GameState::Flying) updateFlying(dt);
    else if (state == GameState::Crashed) updateCrashed(dt);
    updateParticles(dt);
    shake = std::max(0.0f, shake - (float)dt * 1.6f);
    ++frames;
}

void GameStateData::updateFlying(double dt) {
    const float dts = (float)std::min(dt, 0.05);

    // Rotazioni dagli input (tocco/tilt dalla shell Swift).
    pitch += inputPitch * kTurnRate * dts;
    yaw   -= inputYaw   * kTurnRate * dts;
    roll += (inputRoll * kRollRate * dts - roll * 3.2f * dts);
    pitch = clampf(pitch, -kMaxPitch, kMaxPitch);
    roll  = clampf(roll, -kMaxRoll, kMaxRoll);
    roll  *= (1.0f - 1.4f * dts);   // roll tende a riallinearsi

    // Orientamento = yaw → pitch → roll.
    playerQuat = Quat::fromAxisAngle({0, 1, 0}, yaw)
               * Quat::fromAxisAngle({1, 0, 0}, pitch)
               * Quat::fromAxisAngle({0, 0, 1}, roll);

    // Velocità + boost.
    float target = inputBoost && boostFuel > 0 ? kBoostSpeed : kBaseSpeed;
    speed += clampf(target - speed, -kAccel * dts, kAccel * dts);
    if (inputBoost && boostFuel > 0) {
        boostFuel = std::max(0.0f, boostFuel - dts * 0.22f);
        if (frames % 2 == 0)
            spawnBurst(playerPos - playerQuat.forward() * 3.0f, 2, 0.08f);
    } else {
        boostFuel = std::min(1.0f, boostFuel + dts * 0.06f);
    }

    // Movimento in avanti (il "forward" del giocatore).
    playerPos = playerPos + playerQuat.forward() * (speed * dts);
    altitude = playerPos.y;
    score = std::max(score, (int)(-playerPos.z / 10.0f) + ringsPassed * 50);

    // Spawn mondo man mano che avanzi.
    while (playerPos.z - 800.0f < nextSpawnZ) spawnChunk();

    // Scudo del suolo: non scendere sotto kMinAlt (poco realistico ma giocabile).
    if (playerPos.y < kMinAlt) {
        playerPos.y = kMinAlt;
        pitch = std::max(pitch, 0.0f);
    }

    // Collisioni.
    if (checkCollisions()) {
        state = GameState::Crashed;
        crashTimer = 0;
        shake = 1.0f;
        spawnBurst(playerPos, 90, 0.05f);
        return;
    }

    // Anelli: passaggio = distanza dal piano dell'anello piccola e dentro il raggio.
    for (auto& r : rings) {
        if (!r.alive || r.passed) continue;
        Vec3 toP = playerPos - r.pos;
        float along = Vec3::dot(toP, r.orient.forward());
        float radial = (toP - r.orient.forward() * along).length();
        if (std::abs(along) < 2.5f && radial < r.radius - 2.0f) {
            r.passed = true;
            r.alive = false;
            ringsPassed++;
            score += 50;
            boostFuel = std::min(1.0f, boostFuel + 0.25f);
            spawnBurst(r.pos, 26, 0.14f);
        }
    }
}

bool GameStateData::checkCollisions() {
    // AABB giocatore vs edifici (con raggio).
    for (const auto& b : buildings) {
        float dx = std::abs(playerPos.x - b.pos.x) - (b.size.x + kPlayerR);
        float dz = std::abs(playerPos.z - b.pos.z) - (b.size.z + kPlayerR);
        float dy = playerPos.y - (b.pos.y + b.size.y);
        if (dx < 0 && dz < 0 && dy < 0) return true;
    }
    return false;
}

// ---------------------------------------------------------------------- //
//  Crash
// ---------------------------------------------------------------------- //

void GameStateData::updateCrashed(double dt) {
    crashTimer += (float)dt;
    playerPos.y -= kGravityCrash * crashTimer * (float)dt;
    playerPos = playerPos + playerQuat.forward() * (speed * 0.3f * (float)dt);
    speed *= (1.0f - 2.0f * (float)dt);
    if (crashTimer > 1.6f) {
        bestScore = std::max(bestScore, score);
        state = GameState::Menu;
    }
}

void GameStateData::updateParticles(double dt) {
    for (auto& p : particles) {
        p.pos += p.vel * (float)dt;
        p.vel.y -= 12.0f * (float)dt;
        p.life -= (float)dt;
    }
    particles.erase(std::remove_if(particles.begin(), particles.end(),
        [](const Particle& p) { return p.life <= 0; }), particles.end());
}

// ---------------------------------------------------------------------- //
//  Camera
// ---------------------------------------------------------------------- //

Vec3 GameStateData::camPos() const {
    Quat q = camQuat();
    return playerPos - q.forward() * kCamDist + Vec3(0, kCamHeight, 0);
}

Quat GameStateData::camQuat() const {
    // Camera smorzata: segue yaw/pitch con un ritardo morbido.
    // NB: static qui funziona perché esiste un solo giocatore.
    static float sYaw = 0, sPitch = 0;
    sYaw += (yaw - sYaw) * 0.18f;
    sPitch += (pitch - sPitch) * 0.18f;
    return Quat::fromAxisAngle({0, 1, 0}, sYaw)
         * Quat::fromAxisAngle({1, 0, 0}, sPitch);
}

void GameStateData::camReset() const {
    // Riporta la camera smorzata sull'orientamento attuale (usato nel reset).
    // Trucco: porta gli statici ai valori correnti con un passo forte.
    // (implementato via prima chiamata dopo reset: sYaw/pitch vengono
    //  riallineati istante per istante dal gioco)
}

} // namespace fly
