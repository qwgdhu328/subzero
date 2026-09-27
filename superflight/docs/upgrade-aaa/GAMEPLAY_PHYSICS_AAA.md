# 🎮 SuperFlight Gameplay & Physics Upgrade — AAA Production Quality

**Goal**: Trasformare il gameplay da "fun indie flight" a **"AAA action game come Spider-Man/Astro's Playroom"**.

---

## 📊 Current State vs. AAA Target

| Aspetto | Attuale | Target AAA | Gap |
|---------|---------|-----------|-----|
| **Physics engine** | Drag drag semplice | Full fluid dynamics + turbulence | ⭐⭐⭐⭐ |
| **Enemy AI** | Nessuno | Dynamic boss fights + drone swarms | ⭐⭐⭐⭐⭐ |
| **Progression** | Leaderboard | Skill tree + carriera + unlock | ⭐⭐⭐⭐ |
| **Mechanics depth** | Volo + boost | Dash, barrel roll, takeoff/landing, ground combat | ⭐⭐⭐⭐ |
| **Feedback loops** | Score lineare | Combo system + multipliers + skill mastery | ⭐⭐⭐ |
| **World events** | Static city | Weather, traffic, day/night, random encounters | ⭐⭐⭐⭐ |
| **Difficulty curve** | Nessuna | Easy/Normal/Hard/Ultra avec dynamic scaling | ⭐⭐⭐ |
| **Audio design** | Silence | Full 3D spatial audio + music + SFX | ⭐⭐⭐⭐⭐ |
| **Narrative** | Nessuna | Story modes + character development | ⭐⭐⭐ |
| **Polishing** | Raw | Juice (screen shake, slow-mo, particle effects) | ⭐⭐⭐⭐ |

---

## 🎯 5 Pilastri AAA (Gameplay Focus)

### 1️⃣ **ADVANCED PHYSICS ENGINE** (⭐⭐⭐⭐⭐)

#### Upgrade: Turbulence + Wind + Pressure Modeling

```cpp
// Sostituisci semplice drag con sistema fisico completo:

struct FluidDynamics {
    Vec3 windVelocity;      // vento della mappa + raffiche
    float turbulenceLevel;  // 0..1 (meteo dinamico)
    float pressureAltitude; // altitudine equivalente per pressione
};

// Vento procedurale (Perlin noise pattern)
float windNoise(float x, float y, float z, float time) {
    // 3D Perlin per vento naturale, non lineare
    // Intensità max 180 km/h (ritenuto realista per supereroe volante)
    float baseWind = perlin3D(x * 0.001, y * 0.0005, z * 0.001 + time * 0.5);
    float gustWind = perlin3D(x * 0.01, y * 0.01, z * 0.01 + time * 2.0) * 0.4;
    return (baseWind + gustWind) * 25.0f;  // m/s max
}

// Turbulenza (zona instabile dietro edifici e near ground)
float turbulenceAt(Vec3 pos, const std::vector<Building>& buildings) {
    float turb = 0.0f;
    
    // Turbolenza dietro edifici (vortex wake)
    for (const auto& b : buildings) {
        float dx = pos.x - b.pos.x;
        float dz = pos.z - b.pos.z;
        float dist = std::sqrt(dx*dx + dz*dz);
        
        // Wake turbulenza, decade con distanza
        if (dist < 100.0f && dist > 5.0f) {
            turb += (1.0f - dist / 100.0f) * 0.6f;
        }
    }
    
    // Ground effect (vicino al suolo è più turbolento)
    turb += exp(-pos.y / 30.0f) * 0.4f;
    
    return clampf(turb, 0.0f, 1.0f);
}

// Effetto del vento sulla velocità + orientamento
void applyWindForces(GameStateData& state, double dt) {
    Vec3 wind = Vec3(
        windNoise(state.playerPos.x, state.playerPos.y, state.playerPos.z, state.time),
        windNoise(state.playerPos.x + 100, state.playerPos.y, state.playerPos.z, state.time) * 0.3f,
        windNoise(state.playerPos.x, state.playerPos.y + 100, state.playerPos.z, state.time)
    );
    
    // Wind component relativo al movimento
    Vec3 relativeWind = wind - state.playerQuat.forward() * state.speed;
    
    // Lift/drag angolare (il vento spinge il Superman se non allineato)
    float windForce = relativeWind.length();
    if (windForce > 0.1f) {
        Vec3 windDir = relativeWind.normalized();
        // Pitch correction se vento viene dal basso
        state.inputPitch += windDir.y * 0.3f * windForce / 100.0f;
        // Yaw se vento laterale
        state.inputYaw += windDir.x * 0.2f * windForce / 100.0f;
    }
    
    // Turbolenza = slight random jitter in camera
    float turb = turbulenceAt(state.playerPos, state.buildings);
    state.shake += turb * 0.1f;
}
```

**Visual feedback**: Superman "lotta" contro il vento → sensazione di peso fisico → **AAA feel**.

---

### 2️⃣ **DYNAMIC ENEMY AI + BOSS FIGHTS** (⭐⭐⭐⭐⭐)

#### Implementazione: Droni nemici + Boss stagionali

```cpp
// Strutture nemici

enum class EnemyType : int32_t {
    Drone = 0,        // nemico base: vola e spara
    Scout = 1,        // veloce, evasivo
    Turret = 2,       // stazionario ma accurato
    Boss = 3,         // boss fight 1v1
    Swarm = 4,        // sciame coordinato
};

struct Enemy {
    EnemyType type;
    Vec3 pos, vel;
    float health;
    float maxHealth;
    Quat orient;
    
    // AI state
    int aiState;       // 0=patrol, 1=chase, 2=attack, 3=retreat
    float stateTimer;
    Vec3 targetPos;    // Superman position (predicted)
    float detectionRange;
    float attackRange;
    
    // Weapon
    float fireTimer;
    float fireCooldown;
    
    // Behavior
    float aggression;  // 0..1 (aumenta con danno subito)
    float intelligence; // AI quality: Scout=0.9, Drone=0.6, Turret=0.3
};

struct Projectile {
    Vec3 pos, vel;
    float life;
    float maxLife;
    float radius;       // hitbox
    int ownerType;      // 0=Superman, 1=Enemy
    float damage;
};

// AI Behavior: Steering + Prediction
Vec3 computeAITarget(const Enemy& e, const GameStateData& state) {
    Vec3 toPlayer = state.playerPos - e.pos;
    float dist = toPlayer.length();
    
    // Prediction: anticipa il movimento del Superman
    float timeToIntercept = dist / (state.speed + 5.0f);
    Vec3 predictedPos = state.playerPos + state.playerQuat.forward() * state.speed * timeToIntercept * 0.8f;
    
    // Leading shot: spara dove sarà Superman, non dove è
    if (e.type == EnemyType::Drone) {
        return predictedPos;
    } else if (e.type == EnemyType::Scout) {
        // Scout evita il laser: se Superman è in attack range, scappa
        if (dist < 80.0f) {
            return e.pos - toPlayer.normalized() * 150.0f;  // scappa
        }
        return predictedPos + Vec3(sin(state.time * 3.0f) * 50.0f, 0, 0);  // elusive
    } else if (e.type == EnemyType::Boss) {
        // Boss: complex pattern attack
        float phase = fmod(state.time, 10.0f);
        if (phase < 3.0f) {
            return predictedPos;  // attack
        } else if (phase < 6.0f) {
            return state.playerPos + Vec3(0, 200.0f, 0);  // alto e sopra
        } else {
            return e.pos + Vec3(sin(state.time) * 100.0f, cos(state.time) * 50.0f, 0);  // spiral
        }
    }
    
    return predictedPos;
}

// Enemy update
void updateEnemies(std::vector<Enemy>& enemies, const GameStateData& state, double dt) {
    const float dts = (float)dt;
    
    for (auto& e : enemies) {
        // --- AI STATE MACHINE ---
        Vec3 toPlayer = state.playerPos - e.pos;
        float distToPlayer = toPlayer.length();
        
        // Transition logic
        if (distToPlayer < e.detectionRange && e.aiState == 0) {
            e.aiState = 1;  // patrol → chase
        }
        if (distToPlayer > e.detectionRange * 1.5f && e.aiState != 0) {
            e.aiState = 0;  // chase → patrol
        }
        
        // --- STATE BEHAVIORS ---
        switch (e.aiState) {
            case 0: {  // PATROL
                // Fly in random pattern
                e.stateTimer += dts;
                float angle = e.stateTimer * 0.5f + (e.pos.x + e.pos.z) * 0.001f;
                e.targetPos = Vec3(sin(angle) * 200.0f, 100.0f + cos(angle * 0.3f) * 50.0f, 0);
                break;
            }
            case 1: {  // CHASE
                e.targetPos = computeAITarget(e, state);
                e.aggression = std::min(1.0f, e.aggression + dts * 0.2f);
                break;
            }
            case 2: {  // ATTACK
                e.targetPos = computeAITarget(e, state);
                e.fireTimer -= dts;
                if (e.fireTimer <= 0.0f) {
                    // Spawn projectile
                    fireProjectile(e, state);
                    e.fireTimer = e.fireCooldown / e.intelligence;  // smart enemies shoot faster
                }
                break;
            }
            case 3: {  // RETREAT
                e.targetPos = e.pos - toPlayer.normalized() * 300.0f;
                e.health = std::min(e.maxHealth, e.health + dts * 20.0f);  // heal while retreating
                if (e.health > e.maxHealth * 0.7f) {
                    e.aiState = 1;  // go back to chase
                }
                break;
            }
        }
        
        // --- MOVEMENT ---
        Vec3 desiredDir = (e.targetPos - e.pos).normalized();
        e.vel = e.vel * 0.9f + desiredDir * 60.0f * e.intelligence * 0.1f;  // steering
        e.pos += e.vel * dts;
        
        // --- DAMAGE TAKEN BEHAVIOR ---
        if (e.health < e.maxHealth * 0.3f && e.aiState != 3) {
            e.aiState = 3;  // retreat when low health
        }
        
        // --- DESPAWN ---
        if (e.pos.z > state.playerPos.z + 500.0f || e.health <= 0.0f) {
            // Mark for removal + spawn explosion particles
            if (e.health <= 0.0f) {
                spawnDebris(e.pos, 15);
                spawnBurst(e.pos, 30, 0.0f);  // orange burst
            }
            e.health = -1.0f;  // flag for removal
        }
    }
    
    // Remove dead enemies
    enemies.erase(std::remove_if(enemies.begin(), enemies.end(),
                                 [](const Enemy& e) { return e.health < 0.0f; }),
                  enemies.end());
}

// Collision: Superman laser hit enemy
bool laserHitEnemy(const Vec3& laserStart, const Vec3& laserEnd, Enemy& e) {
    // Line-sphere intersection
    Vec3 rayDir = (laserEnd - laserStart).normalized();
    Vec3 toEnemy = e.pos - laserStart;
    float proj = Vec3::dot(toEnemy, rayDir);
    if (proj < 0 || proj > (laserEnd - laserStart).length()) return false;
    
    Vec3 closest = laserStart + rayDir * proj;
    float dist = (e.pos - closest).length();
    
    if (dist < e.radius + 2.0f) {
        e.health -= 0.35f;  // laser damage per frame
        e.aggression = 1.0f;  // super aggressive now
        if (e.aiState == 0 || e.aiState == 1) e.aiState = 2;  // attack mode
        return true;
    }
    return false;
}
```

**Gameplay result**: 
- Easy: Droni lenti, prevedibili
- Normal: Droni intelligenti, sciami coordinati
- Hard: Boss fights, tactical patterns
- Ultra: Onslaught mode, 20+ nemici simultanei

---

### 3️⃣ **PROGRESSION SYSTEM + SKILL TREE** (⭐⭐⭐⭐)

#### Career Mode con Unlock + Cosmetics

```cpp
struct PlayerProfile {
    int totalScore;
    int totalDistance;     // km percorsi
    int enemiesDefeated;
    int comboBest;         // combo record
    
    // Skill tree (5 branches)
    struct Skills {
        float speedMax;         // 0..5: aggiunta +20% per livello
        float maneuverability;  // 0..5: turn rate boost
        float durability;       // 0..5: health vs enemies
        float laserPower;       // 0..5: damage boost
        float detection;        // 0..5: vedi nemici da lontano
    } skills;
    
    int skillPoints;        // da distribuire
    
    // Cosmetics
    bool capeMaterial[10];  // unlock con progress
    bool bodyColor[15];
    bool trailEffect[8];
    bool wingMesh[5];
    
    // Career events
    bool defeatedBoss[3];   // boss encounters
    int currentChallenge;   // seasonal challenge active
};

// Skill upgrade
void upgradeSkill(PlayerProfile& profile, const char* skillName, int points) {
    if (profile.skillPoints < points) return;
    
    if (strcmp(skillName, "speedMax") == 0) {
        profile.skills.speedMax = std::min(5.0f, profile.skills.speedMax + 1.0f);
        // Side effect: max boost speed aumenta del 20%
    } else if (strcmp(skillName, "maneuverability") == 0) {
        profile.skills.maneuverability = std::min(5.0f, profile.skills.maneuverability + 1.0f);
        // Side effect: kTurnRate *= 1.2
    }
    // ... altri skill
    
    profile.skillPoints -= points;
}

// Combo system
struct ComboState {
    int combo;          // contatore combo
    float comboTimer;   // decay timer
    float multiplier;   // 1.0 + combo * 0.05 (max 2.0x at 20 combo)
};

void updateCombo(ComboState& combo, float score, float dt) {
    combo.comboTimer -= dt;
    if (combo.comboTimer <= 0.0f) {
        combo.combo = 0;
        combo.multiplier = 1.0f;
    }
}

void addComboAction(ComboState& combo, float actionScore) {
    combo.combo++;
    combo.comboTimer = 3.0f;  // 3 sec to continue combo
    combo.multiplier = 1.0f + combo.combo * 0.05f;
    combo.multiplier = std::min(2.0f, combo.multiplier);
}

// Score formula (AAA-style)
int calculateScore(const ComboState& combo, float distanceKm, int enemiesKilled, int ringsPassed) {
    int baseScore = 0;
    baseScore += ringsPassed * 500;           // ring bonus
    baseScore += enemiesKilled * 1000;        // kill bonus
    baseScore += (int)(distanceKm * 10);      // distance (minor)
    
    // Apply combo multiplier + difficulty modifier
    int finalScore = (int)(baseScore * combo.multiplier);
    
    return finalScore;
}
```

---

### 4️⃣ **REFINED CONTROLS + ADVANCED MECHANICS** (⭐⭐⭐⭐)

#### New Flight Mechanics

```cpp
// Takeoff + Landing system (like flight sims)

enum class FlightMode : int32_t {
    Grounded = 0,      // a terra, può camminare
    TakingOff = 1,     // accelerazione verticale
    Flying = 2,        // volo libero
    Landing = 3,       // descending to ground
    Crashed = 4,
};

struct FlightPhysics {
    FlightMode mode;
    float fuelTank;         // 0..100%
    float engineHeat;       // overheating risk
    float structuralIntegrity;  // 0..1 (danno accumulativo)
    
    // Advanced maneuvers
    bool barrelRollActive;
    float barrelRollTimer;
    float dashCooldown;
};

// TAKEOFF: Superman decolla verticalmente, poi transizione a volo libero
void performTakeoff(GameStateData& state, double dt) {
    if (state.mode != FlightMode::Grounded) return;
    if (state.speed > 10.0f) return;  // already moving
    
    state.mode = FlightMode::TakingOff;
    state.playerQuat = Quat::fromAxisAngle({0, 1, 0}, state.yaw);  // level out
    state.speed = 15.0f;  // initial vertical boost
    
    // Sound: Superman grunt + engine sound
    // Particle: ground dust cloud
    spawnBurst(state.playerPos, 50, 0.4f);
}

void updateTakeoff(GameStateData& state, double dt) {
    const float dts = (float)dt;
    
    state.playerPos.y += 40.0f * dts;  // vertical ascent 40 m/s
    state.speed = std::min(state.speed + 50.0f * dts, 100.0f);  // accelerate
    
    if (state.playerPos.y > 50.0f) {
        state.mode = FlightMode::Flying;  // transition to free flight
    }
}

// BARREL ROLL: Advanced maneuver for dodging
void performBarrelRoll(GameStateData& state) {
    if (state.flightPhysics.barrelRollTimer > 0.0f) return;  // cooldown
    
    state.flightPhysics.barrelRollActive = true;
    state.flightPhysics.barrelRollTimer = 1.2f;  // duration 1.2 sec
    state.flightPhysics.dashCooldown = 5.0f;     // 5 sec cooldown
    
    // Effect: Screen rotation + particle trail
    // Gameplay: invulnerable during barrel roll, dodge projectiles
}

void updateBarrelRoll(GameStateData& state, double dt) {
    if (!state.flightPhysics.barrelRollActive) return;
    
    const float dts = (float)dt;
    state.flightPhysics.barrelRollTimer -= dts;
    
    // Roll camera 360 degrees
    state.roll += TAU / 1.2f * dts;  // 360° rotation in 1.2 sec
    
    if (state.flightPhysics.barrelRollTimer <= 0.0f) {
        state.flightPhysics.barrelRollActive = false;
        state.roll = 0.0f;  // reset roll
    }
}

// DASH: Short speed burst for repositioning (separate from boost)
void performDash(GameStateData& state) {
    if (state.flightPhysics.dashCooldown > 0.0f) return;
    
    state.speed = std::min(state.speed + 200.0f, kBoostSpeed);
    state.flightPhysics.dashCooldown = 2.0f;
    
    // Effect: Blur trail, sound cue, screen shake
    state.shake = 0.3f;
}
```

---

### 5️⃣ **DYNAMIC WORLD + NARRATIVE** (⭐⭐⭐⭐)

#### Living world + Story

```cpp
// World events (procedurali pero meaningful)

enum class WeatherType : int32_t {
    Clear = 0,
    Rainy = 1,
    Foggy = 2,
    Stormy = 3,        // strong wind, low visibility
    Volcanic = 4,      // ash clouds, hazardous particles
};

struct WorldState {
    WeatherType weather;
    float weatherIntensity;  // 0..1
    int hour;                // 0..23 (day/night cycle)
    float timeOfDay;         // 0..1 (for lighting)
    
    // Random events
    bool activeDrone;        // drone attack incoming
    bool droneBossEncounter; // boss fight available
    int trafficDensity;      // 0..10 (vehicles on roads)
};

// Weather effects on gameplay
void applyWeatherEffects(GameStateData& state, const WorldState& world, double dt) {
    if (world.weather == WeatherType::Rainy) {
        // Wind gusts more intense
        // Visibility reduced (camera FOV tighter)
        // Friction on surfaces (walking slower)
    } else if (world.weather == WeatherType::Stormy) {
        // Extreme wind forces
        // Dangerous updrafts (sudden altitude changes)
        // Enemy AI aggression increases
    } else if (world.weather == WeatherType::Foggy) {
        // Visibility: render distance reduced
        // Must rely on UI radar
        // Ring detection range reduced
    }
}

// Story/Narrative: Career progression reveals story
struct StoryChapter {
    int id;
    const char* title;
    const char* briefing;
    int requiredScore;     // unlock condition
    std::vector<Enemy> bossEncounters;
    int rewardXP;
};

StoryChapter chapters[] = {
    {0, "City Guardian", "Defend Metropolis from invasion", 0, {}, 1000},
    {1, "The Drone Swarm", "Face coordinated enemy attack", 10000, {}, 1500},
    {2, "Volcanic Crisis", "Navigate hazardous conditions", 50000, {}, 2000},
    {3, "Final Showdown", "Defeat the master AI", 200000, {}, 5000},
};
```

---

## 📅 Implementation Roadmap (12 Weeks)

| Week | Feature | Hours | Deliverable |
|------|---------|-------|-------------|
| **W1-2** | Advanced physics (wind, turbulence) | 24h | Wind simulation + turbulence wake system |
| **W3-5** | Enemy AI + projectiles | 40h | Drone AI, boss fight #1, projectile system |
| **W6-7** | Progression system | 20h | Skill tree, career mode, combo system |
| **W8-9** | Advanced mechanics (barrel roll, dash) | 20h | Movement refinements, maneuvers |
| **W10-12** | World systems + story | 25h | Weather, events, narrative, day/night |
| **Polish** | Balance + UI + audio | 30h | Game feel, SFX, music, balance |

**Total**: ~160 hours (4 weeks FT programmer)

---

## 🎮 Gameplay Features by Priority

### Tier 1: Core (Week 1-5)
- ✅ Wind + turbulence physics
- ✅ Basic drone enemies
- ✅ Laser hit detection
- ✅ Combo system
- ✅ Skill progression

### Tier 2: Polish (Week 6-9)
- ✅ Boss encounters
- ✅ Barrel roll + dash
- ✅ Advanced AI behavior
- ✅ Difficulty scaling
- ✅ Career progression

### Tier 3: Content (Week 10-12)
- ✅ Dynamic weather
- ✅ Story mode
- ✅ Cosmetic unlocks
- ✅ Seasonal challenges
- ✅ Leaderboards

---

## 🎯 Success Metrics

| Metric | Baseline | Target | Win Condition |
|--------|----------|--------|--------------|
| **Gameplay depth** | 2/10 | 9/10 | Skill-based, not just reflexes |
| **Replayability** | Low | High | 20+ hours content |
| **Enemy variety** | 0 types | 5+ types | Multiple tactical challenges |
| **Physics credibility** | Basic | Advanced | Superman feels "weighty" |
| **Story integration** | None | Engaging | Players care about narrative |
| **Session length** | 5 min avg | 30+ min | Deep engagement |

---

## 💰 Budget

| Item | Cost |
|------|------|
| Gameplay programmer (12 weeks) | $30k |
| Audio design (8 weeks) | $12k |
| Game design/balance (ongoing) | $8k |
| QA (6 weeks) | $5k |
| **Total** | **$55k** |

---

## 🚀 Go-Live Checklist

- [ ] All enemy types implemented + tested
- [ ] Boss encounters balanced
- [ ] Skill tree UI implemented
- [ ] Career progression saves/loads
- [ ] Story chapters playable
- [ ] Weather systems active
- [ ] Audio design complete
- [ ] All mechanics playtested
- [ ] Performance stable (120 FPS)
- [ ] Balance pass complete
- [ ] Content polished

---

## 📞 Code Hooks (Where to Add)

```
native/engine/game.cpp
├── Add FluidDynamics struct (10 linee)
├── Add Enemy struct + AI functions (150 linee)
├── Add Projectile system (80 linee)
├── Add PlayerProfile + progression (100 linee)
├── Add ComboState + score calculation (50 linee)
├── Add BarrelRoll + Dash (30 linee)
├── Add Weather + World state (70 linee)
└── Modify updateFlying() for new mechanics (100 linee)

native/engine/game_api.h
├── Export new accessors for UI (30 linee)
└── Add game state queries (20 linee)

ios/SuperFlight/GameViewController.swift
├── Listen to enemy spawns (20 linee)
├── Update UI for combo/progression (50 linee)
└── Map advanced controls (30 linee)

ios/SuperFlight/HUDView.swift
├── Add skill tree panel (200 linee)
├── Add combo display (50 linee)
├── Add minimap with enemies (100 linee)
└── Add career progress (80 linee)
```

---

## 🎬 Gameplay Loop (AAA-Style)

```
START GAME
    ↓
[MAIN MENU] → Career progress visible
    ↓
[SELECT CHALLENGE] → Current chapter, difficulty, story briefing
    ↓
[LOADING] → Tips, story narration voiceover
    ↓
[GAMEPLAY] 
  ├─ Takeoff from city
  ├─ Flight mission (encounter waves of enemies)
  ├─ Ring collection (combo multiplier)
  ├─ Boss encounter (climax)
  └─ Landing/Safe zone
    ↓
[RESULTS SCREEN]
  ├─ Score calculation (base + multipliers)
  ├─ Combo record displayed
  ├─ XP earned
  ├─ New skills unlocked
  └─ Next chapter preview
    ↓
[PROGRESSION]
  ├─ Spend skill points
  ├─ Unlock cosmetics
  ├─ Attempt harder difficulty
  └─ Leaderboard comparison
    ↓
[REPEAT or CUSTOMIZE]
```

---

## 🎁 Final AAA Experience

> **SuperFlight v3.0: Complete Gameplay Overhaul**
>
> - Physics that feel **weighty and responsive**
> - Enemy AI that **adapts and challenges**
> - Progression that **motivates continued play**
> - Mechanics that **reward skill mastery**
> - World that **feels alive and reactive**
> - Story that **gives context to action**
> - Audio that **immerses completely**
> - Polish that **makes every action feel satisfying**
>
> **Result**: Not "indie game with polish" — authentic **AAA action game**.

---

**Status**: Specification complete, ready for 12-week implementation sprint.
