// game.cpp — implementazione del motore di volo (fisica, città, collisioni).

#include "game.h"
#include <algorithm>
#include <random>

namespace fly {

// ---------------------------------------------------------------------- //
//  Parametri di gioco (tweak qui)
// ---------------------------------------------------------------------- //
static constexpr float kMachOne      = 343.0f;  // m/s: soglia boom sonico
static constexpr float kRho0         = 1.225f;  // kg/m^3 densità al livello del mare (§2 doc)
static constexpr float kScaleHeight  = 8500.0f; // scala di quota atmosferica
static constexpr float kBodyArea     = 0.85f;   // profilo frontale m^2
static constexpr float kBaseSpeed    = 42.0f;   // m/s
static constexpr float kBoostSpeed   = 833.0f;  // m/s ≈ 3000 km/h in boost
static constexpr float kAccel        = 210.0f;  // m/s^2: spinta da supereroe fino a max speed
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
// Raggi oculari
static constexpr float kLaserRange   = 450.0f;  // portata del raggio
static constexpr float kLaserWidth   = 0.55f;   // spessore visivo
static constexpr float kLaserHeatUp  = 0.55f;   // riscaldamento per secondo
static constexpr float kLaserCoolDn  = 0.35f;   // raffreddamento per secondo
static constexpr float kLaserHeatCap = 0.85f;   // soglia di surriscaldamento
static constexpr float kLaserDPS     = 1.35f;   // danno/sec agli edifici
// Modalità a piedi
static constexpr float kWalkSpeed    = 9.0f;    // camminata m/s
static constexpr float kRunSpeed     = 24.0f;   // corsa (tasto veloce) m/s
static constexpr float kWalkTurn     = 2.2f;    // rad/s svolta a terra
static constexpr float kJumpV        = 16.0f;   // velocità iniziale di salto m/s
static constexpr float kGravityWalk  = 26.0f;   // gravità in modalità a piedi
static constexpr float kEyeHeightWalk = 1.62f;  // occhi a 1.62 m quando in piedi
// Vento e fluidodinamica (GAMEPLAY_PHYSICS_AAA §1)
static constexpr float kWindBase     = 9.0f;    // m/s: intensità vento procedurale
static constexpr float kWindPush     = 0.18f;   // frazione del vento trasmessa al corpo
// Nemici (GAMEPLAY_PHYSICS_AAA §2)
static constexpr float kEnemySpeedDrone  = 32.0f;   // m/s
static constexpr float kEnemySpeedScout  = 52.0f;   // m/s
static constexpr float kEnemyHPDrone     = 1.0f;
static constexpr float kEnemyHPScout     = 0.7f;
static constexpr float kEnemyBulletSpeed = 130.0f;
static constexpr float kEnemyBulletLife  = 3.5f;
static constexpr float kEnemyDamage      = 0.12f;   // per colpo a resistenza base
static constexpr float kEnemyLaserDPS    = 2.0f;    // danno laser/sec ai nemici
static constexpr float kEnemySpawnEvery  = 5.0f;    // secondi tra le ondate
static constexpr int   kEnemyWaveSize    = 2;

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
    if ((int)particles.size() > particleLimit) {
        const int excess = (int)particles.size() - particleLimit;
        particles.erase(particles.begin(), particles.begin() + excess);
    }
}

// ---------------------------------------------------------------------- //
//  NPC: pedoni che camminano e scappano dai raggi oculari
// ---------------------------------------------------------------------- //

void GameStateData::setLimits(int maxNpcs, int maxParticles) {
    npcLimit = maxNpcs > 0 ? std::min(maxNpcs, MAX_NPCS) : 0;
    particleLimit = maxParticles > 0 ? std::min(maxParticles, MAX_PARTICLES) : 0;
}

// Detriti: cubetti con gravità e rimbalzo smorzato sulla strada (§3.2, versione CPU).
void GameStateData::spawnDebris(const Vec3& pos, int n) {
    for (int i = 0; i < n && (int)debris.size() < MAX_DEBRIS; ++i) {
        Debris d;
        d.pos = pos + Vec3(rnd(-12, 12), rnd(-4, 6), rnd(-12, 12));
        d.vel = Vec3(rnd(-1, 1), rnd(0.2f, 1.0f), rnd(-1, 1)).normalized() * rnd(10, 34);
        d.size = Vec3(rnd(0.8f, 2.4f), rnd(0.8f, 2.4f), rnd(0.8f, 2.4f));
        d.spinAxis = rnd(0.0f, TAU);
        d.spinRate = rnd(2.0f, 7.0f);
        d.spin = 0;
        d.rest = 3.5f;
        d.active = true;
        debris.push_back(d);
    }
}

void GameStateData::updateDebris(double dt) {
    const float dts = (float)dt;
    for (auto& d : debris) {
        if (!d.active) continue;
        d.vel.y -= 26.0f * dts;                       // gravità da gioco (non 9.81: più leggibile)
        d.pos = d.pos + d.vel * dts;
        d.spin += d.spinRate * dts;
        if (d.pos.y <= d.size.y) {                    // impatto strada: rimbalzo smorzato
            d.pos.y = d.size.y;
            d.vel.y *= -0.3f;
            d.vel.x *= 0.7f; d.vel.z *= 0.7f;
            if (d.vel.lengthSq() < 0.4f) {
                d.vel = Vec3();
                d.rest -= dts;                        // fermo: despawn dopo 3.5 s
                if (d.rest <= 0) d.active = false;
            }
        }
    }
    debris.erase(std::remove_if(debris.begin(), debris.end(),
        [](const Debris& d) { return !d.active; }), debris.end());
}

void GameStateData::spawnNpcs() {
    // Popola le strade attorno al giocatore; rispetta il limite di qualità.
    npcs.clear();
    const float block = BLOCK;
    const int count = npcLimit;
    for (int i = 0; i < count; ++i) {
        Npc n;
        // Strade = corridoio lungo X=0 oppure bordi blocchi.
        const bool corridor = rnd(0.0f, 1.0f) < 0.5f;
        const float along = playerPos.z + rnd(-350.0f, 250.0f);
        if (corridor) {
            n.pos = Vec3(rnd(-14.0f, 14.0f), 0, along);
        } else {
            const float laneX = (std::round(rnd(-3, 3)) * 0.5f + 0.5f) * block;
            n.pos = Vec3(laneX * (rnd(0, 1) < 0.5f ? 1 : -1) + rnd(-8, 8), 0, along);
        }
        n.yaw = rnd(0.0f, TAU);
        n.walkSpeed = rnd(1.1f, 1.9f);
        n.runSpeed = rnd(4.5f, 6.5f);
        n.speed = n.walkSpeed;
        n.phase = rnd(0.0f, TAU);
        n.flee = 0;
        n.fleeTimer = 0;
        n.bodyTint = rnd(0.0f, 1.0f);
        npcs.push_back(n);
    }
}

void GameStateData::updateNpcs(double dt) {
    const float dts = (float)dt;

    // Se il laser è attivo, chi è vicino al raggio scappa.
    if (laserActive && !laserOverheat) {
        const Vec3 a = playerPos + playerQuat.up() * ((state == GameState::Walking) ? kEyeHeightWalk : 0.75f);
        const Vec3 d = playerQuat.forward();
        for (auto& n : npcs) {
            const Vec3 toN = n.pos - a;
            const float along = Vec3::dot(toN, d);
            const float lateral = (toN - d * along).length();
            if (along > -5.0f && along < 90.0f && lateral < 7.0f && !n.flee) {
                n.flee = 1;
                n.fleeTimer = rnd(3.0f, 6.0f);
            }
        }
    }

    for (auto& n : npcs) {
        if (n.flee > 0) {
            n.fleeTimer -= dts;
            if (n.fleeTimer <= 0) n.flee = 0;
        }

        // Direzione: fuga (via dal giocatore, con panico laterale) o camminata.
        Vec3 want;
        if (n.flee) {
            n.speed = n.runSpeed;
            want = n.pos - playerPos;
            want.y = 0;
            if (want.lengthSq() < 1e-4f) want = Vec3(0, 0, 1);
            want = want.normalized();
            const Vec3 side = Vec3::cross(Vec3(0, 1, 0), want);
            want = (want + side * 0.35f * sinf(time * 7.0f + n.phase)).normalized();
        } else {
            n.speed = n.walkSpeed;
            want = Vec3(sinf(n.yaw), 0, cosf(n.yaw));
            n.yaw += rnd(-1.0f, 1.0f) * 0.8f * dts;   // svolte casuali dolci
        }

        // Evita gli edifici: se il passo finisce dentro un AABB, gira.
        Vec3 next = n.pos + want * (n.speed * dts);
        bool blocked = false;
        for (const auto& b : buildings) {
            if (b.damage >= 1.0f) continue;
            if (std::abs(next.x - b.pos.x) < b.size.x + 1.2f &&
                std::abs(next.z - b.pos.z) < b.size.z + 1.2f) {
                blocked = true;
                break;
            }
        }
        if (blocked) {
            n.yaw += 7.0f * dts;   // svolta ampia e riprova al prossimo tick
        } else {
            n.pos = next;
        }

        n.pos.y = supportHeightAt(n.pos.x, n.pos.z, 2.5f);
        n.phase += n.speed * 3.2f * dts + dts * 0.5f;
    }

    // Ricicla gli NPC rimasti troppo indietro o oltre il limite di qualità.
    npcs.erase(std::remove_if(npcs.begin(), npcs.end(),
        [this](const Npc& n) { return n.pos.z > playerPos.z + DESPAWN_BEHIND * 1.5f; }),
        npcs.end());
    while ((int)npcs.size() > npcLimit) npcs.pop_back();
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
    combo.update((float)dt);
    hitTimer = std::max(0.0f, hitTimer - (float)dt);
    // Rigenerazione lenta fuori dal combattimento (2 s senza colpi).
    if (hitTimer <= 0.0f && health < 1.0f) health = std::min(1.0f, health + (float)dt * 0.04f);
    if (state == GameState::Flying) {
        updateFlying(dt);
        updateFluid(dt);
        updateLaser(dt);
    } else if (state == GameState::Walking) {
        updateWalking(dt);
    } else if (state == GameState::Crashed) updateCrashed(dt);
    updateEnemies(dt);
    updateProjectiles(dt);
    updateNpcs(dt);
    updateDebris(dt);
    updateParticles(dt);
    // Progressione: un punto abilità ogni soglia di punteggio di carriera.
    while (profile.totalScore >= profile.nextSkillScore) {
        profile.skillPoints++;
        profile.nextSkillScore += 4000;
    }
    shake = std::max(0.0f, shake - (float)dt * 1.6f);
    ++frames;
}

void GameStateData::updateFlying(double dt) {
    const float dts = (float)std::min(dt, 0.05);

    // Rotazioni dagli input; l'abilità "manovrabilità" accelera virata e rollio.
    const float turnMul = 1.0f + profile.skills.maneuverability * 0.10f;
    pitch += inputPitch * kTurnRate * turnMul * dts;
    yaw   -= inputYaw   * kTurnRate * turnMul * dts;
    roll += (inputRoll * kRollRate * turnMul * dts - roll * 3.2f * dts);
    pitch = clampf(pitch, -kMaxPitch, kMaxPitch);
    roll  = clampf(roll, -kMaxRoll, kMaxRoll);
    roll  *= (1.0f - 1.4f * dts);   // roll tende a riallinearsi

    // Orientamento = yaw → pitch → roll.
    playerQuat = Quat::fromAxisAngle({0, 1, 0}, yaw)
               * Quat::fromAxisAngle({1, 0, 0}, pitch)
               * Quat::fromAxisAngle({0, 0, 1}, roll);

    // Velocità + boost con drag atmosferico reale (§2 del doc):
    // Cd(M) subsonico 0.3, spike transonico fino a 0.8, decadimento ipersonico 0.8/sqrt(M^2-1);
    // densità esponenziale rho(h) — salendo in alto il boost porta oltre Mach 1.
    // L'abilità "velocità massima" alza il tetto del boost (+6% per livello).
    float target = inputBoost && boostFuel > 0
        ? kBoostSpeed * (1.0f + profile.skills.speedMax * 0.06f) : kBaseSpeed;
    const float mach = speed / kMachOne;
    float cd;
    if (mach < 0.8f) cd = 0.3f;
    else if (mach <= 1.2f) cd = 0.3f + 0.5f * (mach - 0.8f) / 0.4f;
    else cd = 0.8f / std::sqrt(std::max(0.2f, mach * mach - 1.0f));
    const float rho = kRho0 * std::exp(-std::max(0.0f, playerPos.y) / kScaleHeight);
    const float dragAccel = 0.5f * rho * speed * speed * cd * kBodyArea / 90.0f;   // /massa ~90 kg
    const float effectiveAccel = kAccel;
    speed += clampf(target - speed, -effectiveAccel * dts, (effectiveAccel * 0.35f) * dts);
    speed = std::max(kBaseSpeed * 0.5f, speed - dragAccel * dts);   // il drag frena sempre
    if (speed > target) speed = std::max(target, speed - (effectiveAccel * 0.5f) * dts);
    if (inputBoost && boostFuel > 0) {
        boostFuel = std::max(0.0f, boostFuel - dts * 0.18f);
        if (frames % 2 == 0)
            spawnBurst(playerPos - playerQuat.forward() * 3.0f, 2, 0.08f);
    } else {
        boostFuel = std::min(1.0f, boostFuel + dts * 0.06f);
    }

    // Movimento in avanti + deriva del vento: vento procedurale e turbolenza
    // rendono il volo "pesante" (GAMEPLAY_PHYSICS_AAA §1).
    playerPos = playerPos + playerQuat.forward() * (speed * dts);
    playerPos = playerPos + fluid.windVelocity * (kWindPush * dts);
    altitude = playerPos.y;
    score = std::max(score, (int)(-playerPos.z / 10.0f) + ringsPassed * 50);

    // Boom sonico (§2.2 del design): superamento di Mach 1 → onda d'urto.
    const bool nowSupersonic = speed >= kMachOne;
    if (nowSupersonic && !supersonic) {
        sonicRipple = 1.0f;
        shake = std::max(shake, 0.5f);
        spawnBurst(playerPos, 40, 0.08f);
        // Scoppio dei vetri: scintille dai tetti degli edifici vicini alla traiettoria.
        for (auto& b : buildings) {
            if (b.damage >= 1.0f) continue;
            const float dx = std::abs(playerPos.x - b.pos.x);
            const float dz = std::abs(b.pos.z - playerPos.z);
            if (dx < b.size.x + 60.0f && dz < 220.0f && playerPos.y < b.size.y + 40.0f) {
                spawnBurst(Vec3(b.pos.x, b.size.y + 1.0f, b.pos.z), 8, 0.14f);
            }
        }
    }
    supersonic = nowSupersonic;
    sonicRipple = std::max(0.0f, sonicRipple - dts * 0.8f);   // decade in ~1.2 s

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
            addComboAction(50);                // anello nella combo (§3 del doc)
            boostFuel = std::min(1.0f, boostFuel + 0.25f);
            spawnBurst(r.pos, 26, 0.14f);
        }
    }
}

bool GameStateData::checkCollisions() {
    // AABB giocatore vs edifici (con raggio); ignora gli edifici distrutti.
    for (const auto& b : buildings) {
        if (b.damage >= 1.0f) continue;
        float dx = std::abs(playerPos.x - b.pos.x) - (b.size.x * (1.0f - b.damage * 0.5f) + kPlayerR);
        float dzz = std::abs(playerPos.z - b.pos.z) - (b.size.z * (1.0f - b.damage * 0.5f) + kPlayerR);
        float dy = playerPos.y - (b.pos.y + b.size.y);
        if (dx < 0 && dzz < 0 && dy < 0) return true;
    }
    return false;
}

// ---------------------------------------------------------------------- //
//  Raggi oculari (laser)
// ---------------------------------------------------------------------- //

void GameStateData::updateLaser(double dt) {
    const float dts = (float)dt;
    laserTimer += dts;

    // Fuoco ammesso solo se non surriscaldato.
    const bool firing = laserActive && !laserOverheat;

    // Termica.
    if (firing) {
        laserHeat += kLaserHeatUp * dts;
        if (laserHeat >= kLaserHeatCap) {
            laserHeat = 1.0f;
            laserOverheat = true;
        }
    } else {
        laserHeat -= kLaserCoolDn * dts;
        if (laserHeat <= 0.0f) {
            laserHeat = 0.0f;
            laserOverheat = false;   // completamente raffreddato: di nuovo operativo
        }
    }

    // Scie residue: decadimento.
    for (auto& s : laserSegs) s.life -= dts;
    laserSegs.erase(std::remove_if(laserSegs.begin(), laserSegs.end(),
        [](const LaserSegment& s) { return s.life <= 0; }), laserSegs.end());

    if (!firing) {
        laserHit = false;
        return;
    }

    // Origine: gli occhi (coerenti con il modello 3D; a terra l'origine è ai piedi).
    const float eyeH = (state == GameState::Walking) ? kEyeHeightWalk : 0.75f;
    const Vec3 eye = playerPos + playerQuat.up() * eyeH
                   + playerQuat.forward() * 0.50f;
    const Vec3 dir = playerQuat.forward();

    // Raycast AABB: slab test sull'intero intervallo del raggio.
    float bestT = kLaserRange;
    int bestIdx = -1;
    for (int i = 0; i < (int)buildings.size(); ++i) {
        const Building& b = buildings[i];
        if (b.damage >= 1.0f) continue;
        const float tol = kLaserWidth;
        float tmin = 0.0f, tmax = bestT;
        bool miss = false;
        const float* o = &eye.x;
        const float* d = &dir.x;
        const float* c = &b.pos.x;
        const float* h = &b.size.x;
        for (int a = 0; a < 3; ++a) {
            const float lo = c[a] - h[a] - tol;
            const float hi = c[a] + h[a] + tol;
            if (std::abs(d[a]) < 1e-6f) {
                if (o[a] < lo || o[a] > hi) { miss = true; break; }
            } else {
                float t1 = (lo - o[a]) / d[a];
                float t2 = (hi - o[a]) / d[a];
                if (t1 > t2) std::swap(t1, t2);
                tmin = std::max(tmin, t1);
                tmax = std::min(tmax, t2);
                if (tmin > tmax) { miss = true; break; }
            }
        }
        if (!miss) { bestT = tmin; bestIdx = i; }
        if (bestT <= 0.0f) { bestIdx = -1; break; }
    }

    laserHit = bestIdx >= 0;
    laserEnd = eye + dir * bestT;

    // Danno all'edificio colpito.
    if (bestIdx >= 0) {
        Building& b = buildings[bestIdx];
        b.damage += kLaserDPS * dts;
        // Poi, la città non ripara: il danno è permanente finché il chunk non
        // viene riciclato, ed è questo che rende il laser "reale".
        if (b.damage >= 1.0f) {
            b.damage = 1.0f;
            score += 25;
            spawnBurst(laserEnd, 55, 0.02f);   // esplosione arancio
            spawnDebris(Vec3(b.pos.x, b.size.y * 0.7f, b.pos.z), 26);  // detriti dal collasso
            shake = std::max(shake, 0.35f);
        } else if (frames % 3 == 0) {
            spawnBurst(laserEnd, 2, 0.02f);    // scintille d'impatto
        } else if (frames % 4 == 0) {
            spawnBurst(laserEnd, 1, 0.02f);
        }
    }

    // Danno ai nemici lungo il raggio (line-sphere, GAMEPLAY_PHYSICS_AAA §2):
    // l'abilità "laser power" moltiplica il danno (+25% per livello).
    {
        const float dmg = kEnemyLaserDPS * dts * (1.0f + profile.skills.laserPower * 0.25f);
        for (auto& e : enemies) {
            const Vec3 toE = e.pos - eye;
            const float proj = Vec3::dot(toE, dir);
            if (proj < 0.0f || proj > kLaserRange) continue;
            const Vec3 closest = eye + dir * proj;
            if ((e.pos - closest).length() <= e.radius + kLaserWidth) {
                e.health -= dmg;
                e.aggression = 1.0f;
                if (e.aiState == 0 || e.aiState == 1) e.aiState = 2;
                if (frames % 2 == 0) spawnBurst(e.pos, 2, 0.02f);
            }
        }
    }

    // Scia del raggio corrente (per il glow residuo).
    if ((int)laserSegs.size() < MAX_LASER_SEGS) {
        laserSegs.push_back({eye, laserEnd, kLaserWidth, 0.05f});
    }
}

// ---------------------------------------------------------------------- //
//  Gameplay AAA: fluidodinamica, nemici, proiettili, combo (§1-§3 del doc)

void GameStateData::updateFluid(double dt) {
    const float dts = (float)dt;
    const float t = (float)time;

    // Vento procedurale: somma di sinusoidi multi-scala (proxy stabile e
    // deterministico del Perlin 3D del piano) — base + raffiche rapide.
    const Vec3 p = playerPos;
    const float bx = sinf(p.x * 0.0011f + t * 0.10f) * cosf(p.z * 0.0009f - t * 0.07f);
    const float bz = cosf(p.x * 0.0008f - t * 0.08f) * sinf(p.z * 0.0012f + t * 0.11f);
    const float gx = sinf(p.x * 0.013f + t * 1.7f) * cosf(p.y * 0.010f + t * 1.1f);
    const float gz = cosf(p.z * 0.014f + t * 1.9f) * sinf(p.y * 0.011f - t * 0.9f);
    const float by = sinf(p.y * 0.0016f + t * 0.05f);
    const Vec3 wind((bx + 0.4f * gx) * kWindBase, by * kWindBase * 0.25f,
                    (bz + 0.4f * gz) * kWindBase);
    fluid.windVelocity = wind;

    // Turbolenza: scia di vortice dietro gli edifici vicini + effetto suolo.
    float turb = std::exp(-std::max(0.0f, p.y) / 30.0f) * 0.35f;
    for (const auto& b : buildings) {
        if (b.damage >= 1.0f) continue;
        if (p.y > b.size.y + 25.0f) continue;      // sopra la scia del vortice
        const float dx = p.x - b.pos.x;
        const float dz = p.z - (b.pos.z + 40.0f);  // scia a valle della traiettoria
        const float dist = std::sqrt(dx * dx + dz * dz);
        if (dist < 90.0f && dist > 5.0f)
            turb += (1.0f - dist / 90.0f) * 0.55f;
    }
    fluid.turbulenceLevel = clampf(turb, 0.0f, 1.0f);

    // Il vento perturba dolcemente l'assetto, la turbolenza scuote la camera:
    // Superman "lotta" contro l'aria (AAA feel, §1 del doc).
    pitch += wind.y * 0.020f * dts;
    yaw   += wind.x * 0.012f * dts;
    if (state == GameState::Flying)
        shake = std::max(shake, fluid.turbulenceLevel * 0.28f);
}

void GameStateData::spawnEnemyWave() {
    if ((int)enemies.size() >= MAX_ENEMIES) return;
    // Il radar del giocatore (abilità "detection") restringe il raggio in cui
    // i nemici lo vedono: spawnano oltre quel raggio per dare tempo di reagire.
    const float detMul = 1.0f - profile.skills.detection * 0.10f;
    for (int k = 0; k < kEnemyWaveSize && (int)enemies.size() < MAX_ENEMIES; ++k) {
        Enemy e;
        e.type = rnd(0.0f, 1.0f) < 0.25f ? EnemyType::Scout : EnemyType::Drone;
        e.pos = playerPos + playerQuat.forward() * rnd(380.0f, 560.0f)
              + playerQuat.right() * rnd(-180.0f, 180.0f)
              + Vec3(0, rnd(20.0f, 90.0f), 0);
        if (e.pos.y < 25.0f) e.pos.y = 25.0f;
        e.maxHealth = e.health = e.type == EnemyType::Scout ? kEnemyHPScout : kEnemyHPDrone;
        e.intelligence = e.type == EnemyType::Scout ? 0.9f : 0.6f;
        e.fireCooldown = e.type == EnemyType::Scout ? 2.6f : 2.0f;
        e.detectionRange = 320.0f * detMul;
        e.attackRange = e.type == EnemyType::Scout ? 200.0f : 150.0f;
        e.fireTimer = rnd(0.8f, 1.8f);
        e.phase = rnd(0.0f, TAU);
        e.aiState = 1;                            // arrivano già in caccia
        enemies.push_back(e);
    }
}

void GameStateData::updateEnemies(double dt) {
    const float dts = (float)dt;

    // Ondate periodiche solo durante il volo.
    if (state == GameState::Flying) {
        enemySpawnTimer -= dts;
        if (enemySpawnTimer <= 0.0f) {
            enemySpawnTimer = kEnemySpawnEvery;
            spawnEnemyWave();
        }
    }

    for (auto& e : enemies) {
        e.stateTimer += dts;
        const Vec3 toPlayer = playerPos - e.pos;
        const float dist = toPlayer.length();

        // --- transizioni della macchina a stati AI ---
        if (e.aiState == 0 && dist < e.detectionRange) e.aiState = 1;
        if (e.aiState != 0 && dist > e.detectionRange * 1.5f) e.aiState = 0;
        if (e.aiState == 1 && dist < e.attackRange) e.aiState = 2;
        if (e.aiState == 2 && dist > e.attackRange * 1.25f) e.aiState = 1;
        if (e.health < e.maxHealth * 0.3f && e.aiState != 3) e.aiState = 3;
        if (e.aiState == 3 && e.health > e.maxHealth * 0.7f) e.aiState = 1;

        // --- comportamenti per stato ---
        if (e.aiState == 0) {              // pattugliamento: cerchi larghi
            const float ang = e.stateTimer * 0.5f + e.phase;
            e.targetPos = e.pos + Vec3(sinf(ang) * 60.0f, cosf(ang * 0.7f) * 12.0f,
                                       cosf(ang) * 60.0f);
        } else if (e.aiState == 1 || e.aiState == 2) {
            // Caccia/attacco: predizione della traiettoria del giocatore.
            const float tInt = std::min(dist / 300.0f, 1.2f);
            e.targetPos = playerPos + playerQuat.forward() * (speed * tInt * 0.8f);
            if (e.type == EnemyType::Scout && dist < 70.0f) {
                // Scout evasivo: mantiene le distanze scappando con deriva laterale.
                e.targetPos = e.pos - toPlayer.normalized() * 120.0f
                            + Vec3(sinf(time * 3.0f + e.phase) * 40.0f, 15.0f, 0);
            } else if (e.aiState == 2 && dist > e.attackRange * 0.6f) {
                e.targetPos = e.pos + toPlayer.normalized() * 80.0f;   // avvicinati
            } else if (e.aiState == 2) {
                // A distanza d'attacco: strafing laterale (più difficile da colpire).
                const Vec3 side = Vec3::cross(Vec3(0, 1, 0), toPlayer.normalized());
                e.targetPos = e.pos + side * (sinf(time * 2.0f + e.phase) * 60.0f);
            }
            e.aggression = std::min(1.0f, e.aggression + dts * 0.2f);
        } else {                            // ritirata: via dal giocatore e cura
            e.targetPos = e.pos - toPlayer.normalized() * 250.0f;
            e.health = std::min(e.maxHealth, e.health + dts * 0.08f);
        }

        // --- movimento: steering smorzato verso il target ---
        const float cruise = e.type == EnemyType::Scout ? kEnemySpeedScout : kEnemySpeedDrone;
        const Vec3 desired = (e.targetPos - e.pos).normalized()
                           * (cruise * (0.55f + 0.45f * e.intelligence));
        e.vel = e.vel * 0.92f + desired * 0.08f;
        e.pos = e.pos + e.vel * dts;
        if (e.pos.y < 12.0f) e.pos.y = 12.0f;          // mai sotto i tetti bassi
        e.yaw = std::atan2(-e.vel.x, -e.vel.z);

        // --- fuoco: solo in volo, in attacco e a distanza utile ---
        if (state == GameState::Flying && e.aiState == 2 && dist < e.attackRange) {
            e.fireTimer -= dts;
            if (e.fireTimer <= 0.0f) {
                e.fireTimer = e.fireCooldown / std::max(0.3f, e.intelligence);
                if ((int)projectiles.size() < MAX_PROJECTILES) {
                    Projectile pr;
                    pr.pos = e.pos;
                    // Mira anticipata: spara dove sarà Superman, non dov'è.
                    const float tFly = dist / kEnemyBulletSpeed;
                    const Vec3 aim = playerPos + playerQuat.forward() * (speed * tFly * 0.85f);
                    pr.vel = (aim - e.pos).normalized() * kEnemyBulletSpeed;
                    pr.life = pr.maxLife = kEnemyBulletLife;
                    pr.damage = kEnemyDamage;
                    projectiles.push_back(pr);
                }
            }
        }

        // Troppo indietro o troppo avanti: si perde di vista (despawn silenzioso).
        if (e.pos.z > playerPos.z + 450.0f || e.pos.z < playerPos.z - 900.0f)
            e.health = -100.0f;
    }

    // Rimozione: chi è stato ucciso esplode e paga la combo; il resto sparisce.
    for (auto it = enemies.begin(); it != enemies.end();) {
        if (it->health > 0.0f) { ++it; continue; }
        if (it->health > -99.0f) {
            spawnBurst(it->pos, 30, 0.02f);
            profile.enemiesDefeated++;
            addComboAction(1000);              // kill bonus (§3 del doc)
            shake = std::max(shake, 0.2f);
        }
        it = enemies.erase(it);
    }
}

void GameStateData::updateProjectiles(double dt) {
    const float dts = (float)dt;
    for (auto& pr : projectiles) {
        pr.pos = pr.pos + pr.vel * dts;
        pr.life -= dts;
        // Collisione sfera-giocatore: i proiettili nemici fanno davvero male.
        if (state == GameState::Flying && pr.life > 0.0f &&
            (pr.pos - playerPos).length() < pr.radius + kPlayerR) {
            pr.life = 0;
            damagePlayer(pr.damage);
            spawnBurst(pr.pos, 8, 0.02f);
        }
    }
    projectiles.erase(std::remove_if(projectiles.begin(), projectiles.end(),
        [](const Projectile& pr) { return pr.life <= 0.0f; }),
        projectiles.end());
}

void GameStateData::damagePlayer(float amount) {
    if (hitTimer > 0.0f) return;               // breve invulnerabilità tra i colpi
    const float mul = 1.0f - profile.skills.durability * 0.12f;
    health -= amount * mul;
    hitTimer = 0.35f;
    shake = std::max(shake, 0.4f);
    if (health <= 0.0f) {
        health = 0.0f;
        state = GameState::Crashed;
        crashTimer = 0;
        spawnBurst(playerPos, 70, 0.05f);
    }
}

void GameStateData::addComboAction(int baseScore) {
    combo.addAction();
    const int gained = (int)(baseScore * combo.multiplier);
    score += gained;
    profile.totalScore += gained;
    profile.comboBest = std::max(profile.comboBest, combo.combo);
}

bool GameStateData::upgradeSkill(int skill) {
    if (profile.skillPoints <= 0 || skill < 0 || skill > 4) return false;
    const float before = profile.skills.level(skill);
    profile.skills.upgrade(skill);
    if (profile.skills.level(skill) == before) return false;   // già al massimo
    profile.skillPoints--;
    return true;
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
    if (state == GameState::Walking || state == GameState::Menu) {
        // Camera terza persona più vicina e in basso (menu = vista bassa sulla città).
        const float d = state == GameState::Menu ? 30.0f : 9.0f;
        const float h = state == GameState::Menu ? 14.0f : 3.2f;
        return playerPos - q.forward() * d + Vec3(0, h, 0);
    }
    return playerPos - q.forward() * kCamDist + Vec3(0, kCamHeight, 0);
}

// Smoothing camera condiviso (un solo giocatore → static va bene).
static float gCamYaw = 0, gCamPitch = 0;

Quat GameStateData::camQuat() const {
    // Camera smorzata: segue yaw/pitch con un ritardo morbido.
    gCamYaw += (yaw - gCamYaw) * 0.18f;
    gCamPitch += (pitch - gCamPitch) * 0.18f;
    return Quat::fromAxisAngle({0, 1, 0}, gCamYaw)
         * Quat::fromAxisAngle({1, 0, 0}, gCamPitch);
}

void GameStateData::camReset() const {
    // Riallinea subito la camera all'orientamento corrente (usato nel reset).
    gCamYaw = yaw;
    gCamPitch = pitch;
}

// ---------------------------------------------------------------------- //
//  Reset, menu e modalità a piedi
// ---------------------------------------------------------------------- //

void GameStateData::reset(int best) {
    state = GameState::Menu;              // il menu è il primo stato del gioco
    time = 0; score = 0; ringsPassed = 0;
    bestScore = best;
    speed = 0;
    boostFuel = 1.0f;
    shake = 0; crashTimer = 0;
    playerPos = Vec3(0, kMinAlt, 0);      // in strada, al centro del corridoio
    pitch = yaw = roll = 0;
    vy = 0; onGround = true; landing = false;
    playerQuat = Quat();
    inputPitch = inputYaw = inputRoll = 0;
    inputBoost = false;
    laserActive = laserOverheat = laserHit = false;
    laserHeat = 0; laserTimer = 0;
    laserEnd = Vec3();
    laserSegs.clear();
    // I nemici esistono solo in volo: la carriera (profile) sopravvive al reset.
    enemies.clear();
    projectiles.clear();
    enemySpawnTimer = 3.0f;
    health = 1.0f;
    hitTimer = 0;
    combo = ComboState();
    buildings.clear();
    rings.clear();
    particles.clear();
    npcs.clear();
    debris.clear();
    chunks.clear();
    nextSpawnZ = -400.0f;
    frames = 0;
    camReset();

    // Prime 4 chunk di città intorno al punto di spawn.
    for (int i = 0; i < 4; ++i) spawnChunk();
    spawnNpcs();
}

void GameStateData::startGame() {
    // "AVVIA PARTITA": rigenera il mondo e mette Superman in strada.
    reset(bestScore);
    state = GameState::Walking;
    playerPos = Vec3(0, kMinAlt, -30);
    yaw = 0; pitch = 0; roll = 0;
    playerQuat = Quat();
    camReset();
}

void GameStateData::jump() {
    if (state != GameState::Walking) return;
    if (onGround) { vy = kJumpV; onGround = false; }
    else if (!landing && vy > -30.0f) {            // doppio salto → decollo
        state = GameState::Flying;
        vy = 0; speed = kBaseSpeed * 0.45f;
        pitch = 0.25f;
        spawnBurst(playerPos, 20, 0.08f);
    }
}

void GameStateData::toggleFly() {
    if (state == GameState::Walking) {
        state = GameState::Flying;
        vy = 0; speed = kBaseSpeed * 0.45f;
        spawnBurst(playerPos, 24, 0.08f);
    } else if (state == GameState::Flying) {
        state = GameState::Walking;                // atterraggio: cade con gravità
        landing = true;
    }
}

// Quota della superficie su cui si può stare in piedi (strada, tetti) —
// la più alta sotto `maxY`.
float GameStateData::supportHeightAt(float x, float z, float maxY) const {
    float h = 0.0f;   // strada
    for (const auto& b : buildings) {
        if (b.damage >= 1.0f) continue;
        const float m = 0.6f;                     // mezza larghezza corpo ~ 1.2 m
        if (std::abs(x - b.pos.x) < b.size.x + m &&
            std::abs(z - b.pos.z) < b.size.z + m) {
            const float top = b.pos.y + b.size.y;
            if (top <= maxY + 0.5f && top > h) h = top;
        }
    }
    return h;
}

void GameStateData::updateWalking(double dt) {
    const float dts = (float)std::min(dt, 0.05);

    // Yaw dal joystick; il pitch lo usa la camera per guardare su/giù.
    yaw   -= inputYaw * kWalkTurn * dts;
    pitch  = clampf(pitch * (1.0f - 3.0f * dts), -0.4f, 0.4f);
    roll  = 0;
    playerQuat = Quat::fromAxisAngle({0, 1, 0}, yaw);

    // Movimento relativo alla visuale (strafe = input pitch invertito).
    const Vec3 fwd = Vec3(playerQuat.forward().x, 0, playerQuat.forward().z).normalized();
    const Vec3 strafe = playerQuat.right();
    const float vMove = -inputPitch * kWalkSpeed;  // su = avanti
    Vec3 vel = fwd * vMove + strafe * (0.0f);

    // Corsa con boost (veloce anche a piedi); fase animazione dal movimento reale.
    const float vNow = inputBoost ? kRunSpeed : kWalkSpeed;
    if (inputBoost) vel = fwd * (kRunSpeed);
    playerPos = playerPos + vel * dts;
    animPhase += (vNow * dts) / 1.1f;   // un ciclo ogni ~1.1 m percorsi (da videogioco)

    // Gravità e salto.
    vy -= kGravityWalk * dts;
    playerPos.y += vy * dts;

    const float ground = supportHeightAt(playerPos.x, playerPos.z, playerPos.y + 2.0f);
    if (playerPos.y <= ground) {
        playerPos.y = ground;
        vy = 0;
        if (!onGround) spawnBurst(playerPos, 6, 0.08f);   // piccola polvere all'atterraggio
        onGround = true;
        landing = false;
    } else {
        onGround = false;
    }

    // Spawn mondo man mano che si esplora.
    while (playerPos.z - 800.0f < nextSpawnZ) spawnChunk();

    // NPC freschi man mano che avanzi.
    if ((int)npcs.size() < npcLimit / 2) spawnNpcs();

    // Muri: semplice pushback orizzontale se finisci dentro un edificio.
    for (const auto& b : buildings) {
        if (b.damage >= 1.0f) continue;
        const float m = 1.0f;
        const float top = b.pos.y + b.size.y;
        if (playerPos.y < top - 1.0f &&
            std::abs(playerPos.x - b.pos.x) < b.size.x + m &&
            std::abs(playerPos.z - b.pos.z) < b.size.z + m) {
            // Spingi fuori lungo l'asse di minor penetrazione.
            const float px = (b.size.x + m) - std::abs(playerPos.x - b.pos.x);
            const float pz = (b.size.z + m) - std::abs(playerPos.z - b.pos.z);
            if (px < pz) {
                playerPos.x += (playerPos.x > b.pos.x ? px : -px);
            } else {
                playerPos.z += (playerPos.z > b.pos.z ? pz : -pz);
            }
        }
    }

    if (state == GameState::Walking) updateLaser(dts);
}

} // namespace fly
