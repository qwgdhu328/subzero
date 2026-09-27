// game_api.cpp — ponte C ↔ C++ per Swift.

#include "game_api.h"
#include "game.h"

using namespace fly;

static GameStateData* g = nullptr;

static inline float qx(const Quat& q) { return q.x; }
static inline float qy(const Quat& q) { return q.y; }
static inline float qz(const Quat& q) { return q.z; }

static FlyVec3 v3(const Vec3& v) { return {v.x, v.y, v.z}; }

// ---------------------------------------------------------------- //

void fly_create(void) {
    delete g;
    g = new GameStateData();
    g->reset(0);
}

void fly_destroy(void) {
    delete g;
    g = nullptr;
}

void fly_reset(int32_t best) {
    if (g) g->reset(best);
}

void fly_update(double dt, int32_t w, int32_t h) {
    if (g) g->update(dt, w, h);
}

void fly_set_stick(float pitch, float yaw, float roll) {
    if (!g) return;
    g->inputPitch = pitch;
    g->inputYaw = yaw;
    g->inputRoll = roll;
}

void fly_set_boost(int32_t on) {
    if (g) g->inputBoost = on != 0;
}

void fly_set_laser(int32_t on) {
    if (g) g->laserActive = on != 0;
}

void fly_jump(void)        { if (g) g->jump(); }
void fly_toggle_fly(void)  { if (g) g->toggleFly(); }
void fly_start_game(void)  { if (g) g->startGame(); }

void fly_set_limits(int32_t max_npcs, int32_t max_particles) {
    if (g) g->setLimits(max_npcs, max_particles);
}

int32_t fly_state(void)    { return g ? (int32_t)g->state : 0; }
int32_t fly_score(void)    { return g ? g->score : 0; }
int32_t fly_best(void)     { return g ? g->bestScore : 0; }
int32_t fly_rings(void)    { return g ? g->ringsPassed : 0; }
float   fly_speed(void)    { return g ? g->speed : 0; }
float   fly_boost(void)    { return g ? g->boostFuel : 0; }
float   fly_altitude(void) { return g ? g->altitude : 0; }
float   fly_shake(void)    { return g ? g->shake : 0; }
double  fly_time(void)     { return g ? g->time : 0; }
float   fly_laser_heat(void)   { return g ? g->laserHeat : 0; }
int32_t fly_laser_active(void) { return g && g->laserActive && !g->laserOverheat ? 1 : 0; }
int32_t fly_laser_hit(void)    { return g && g->laserHit ? 1 : 0; }
int32_t fly_on_ground(void)    { return g && g->state == GameState::Walking && g->onGround ? 1 : 0; }
float   fly_anim_phase(void)   { return g ? g->animPhase : 0; }
float   fly_sonic_ripple(void) { return g ? g->sonicRipple : 0; }
int32_t fly_supersonic(void)   { return g && g->supersonic ? 1 : 0; }

FlyVec3 fly_player_pos(void) { return g ? v3(g->playerPos) : FlyVec3{0, 60, 0}; }

FlyVec3 fly_player_quat(void) {
    if (!g) return {0, 0, 0};
    // Ritorna (x,y,z); w si ricava come sqrt(1-|v|^2).
    float w2 = 1.0f - (g->playerQuat.x * g->playerQuat.x +
                       g->playerQuat.y * g->playerQuat.y +
                       g->playerQuat.z * g->playerQuat.z);
    (void)qx(g->playerQuat); (void)qy(g->playerQuat); (void)qz(g->playerQuat);
    (void)w2;
    return {g->playerQuat.x, g->playerQuat.y, g->playerQuat.z};
}

FlyVec3 fly_cam_pos(void)  { return g ? v3(g->camPos()) : FlyVec3{0, 70, 10}; }
FlyVec3 fly_cam_quat(void) {
    if (!g) return {0, 0, 0};
    const Quat q = g->camQuat();
    return {q.x, q.y, q.z};
}

int32_t fly_building_count(void) { return g ? (int32_t)g->buildings.size() : 0; }

void fly_building(int32_t i, FlyVec3* pos, FlyVec3* size, float* hue) {
    if (!g || i < 0 || i >= (int32_t)g->buildings.size() || !pos || !size) return;
    const Building& b = g->buildings[i];
    *pos = v3(b.pos);
    *size = v3(b.size);
    if (hue) *hue = b.hue;
}

int32_t fly_ring_count(void) { return g ? (int32_t)g->rings.size() : 0; }

void fly_ring(int32_t i, FlyVec3* pos, FlyVec3* quat, float* radius,
              int32_t* passed) {
    if (!g || i < 0 || i >= (int32_t)g->rings.size() || !pos) return;
    const Ring& r = g->rings[i];
    *pos = v3(r.pos);
    if (quat) *quat = {r.orient.x, r.orient.y, r.orient.z};
    if (radius) *radius = r.radius;
    if (passed) *passed = r.passed ? 1 : 0;
}

int32_t fly_particle_count(void) { return g ? (int32_t)g->particles.size() : 0; }

void fly_particle(int32_t i, FlyVec3* pos, float* size, float* life01,
                  float* hue) {
    if (!g || i < 0 || i >= (int32_t)g->particles.size() || !pos) return;
    const Particle& p = g->particles[i];
    *pos = v3(p.pos);
    if (size) *size = p.size;
    if (life01) *life01 = p.life / p.maxLife;
    if (hue) *hue = p.hue;
}

void fly_laser(FlyVec3* eye, FlyVec3* end, int32_t* active, float* heat) {
    if (!g) return;
    if (eye) *eye = v3(g->playerPos + g->playerQuat.up() * 0.75f
                     + g->playerQuat.forward() * 0.50f);
    if (end) *end = v3(g->laserEnd);
    if (active) *active = fly_laser_active();
    if (heat) *heat = g->laserHeat;
}

int32_t fly_debris_count(void) { return g ? (int32_t)g->debris.size() : 0; }

void fly_debris(int32_t i, FlyVec3* pos, FlyVec3* size, float* spin,
                float* spinAxis) {
    if (!g || i < 0 || i >= (int32_t)g->debris.size()) return;
    const Debris& d = g->debris[i];
    if (pos) *pos = v3(d.pos);
    if (size) *size = v3(d.size);
    if (spin) *spin = d.spin;
    if (spinAxis) *spinAxis = d.spinAxis;
}

int32_t fly_npc_count(void) { return g ? (int32_t)g->npcs.size() : 0; }

void fly_npc(int32_t i, FlyVec3* pos, float* yaw, float* phase,
             int32_t* flee, float* tint) {
    if (!g || i < 0 || i >= (int32_t)g->npcs.size()) return;
    const Npc& n = g->npcs[i];
    if (pos) *pos = v3(n.pos);
    if (yaw) *yaw = n.yaw;
    if (phase) *phase = n.phase;
    if (flee) *flee = n.flee;
    if (tint) *tint = n.bodyTint;
}

int32_t fly_laser_seg_count(void) {
    return g ? (int32_t)g->laserSegs.size() : 0;
}
// ---------------------------------------------------------------- //
// Gameplay AAA: nemici, proiettili, carriera, fluidodinamica

int32_t fly_enemy_count(void) { return g ? (int32_t)g->enemies.size() : 0; }

void fly_enemy(int32_t i, FlyVec3* pos, FlyVec3* vel, float* yaw,
               int32_t* type, int32_t* ai_state, float* hp01) {
    if (!g || i < 0 || i >= (int32_t)g->enemies.size()) return;
    const Enemy& e = g->enemies[i];
    if (pos) *pos = v3(e.pos);
    if (vel) *vel = v3(e.vel);
    if (yaw) *yaw = e.yaw;
    if (type) *type = (int32_t)e.type;
    if (ai_state) *ai_state = e.aiState;
    if (hp01) *hp01 = e.health / e.maxHealth;
}

int32_t fly_projectile_count(void) { return g ? (int32_t)g->projectiles.size() : 0; }

void fly_projectile(int32_t i, FlyVec3* pos, FlyVec3* vel) {
    if (!g || i < 0 || i >= (int32_t)g->projectiles.size()) return;
    const Projectile& pr = g->projectiles[i];
    if (pos) *pos = v3(pr.pos);
    if (vel) *vel = v3(pr.vel);
}

float   fly_health(void)              { return g ? g->health : 1.0f; }
int32_t fly_combo(void)               { return g ? g->combo.combo : 0; }
float   fly_combo_multiplier(void)    { return g ? g->combo.multiplier : 1.0f; }
int32_t fly_combo_best(void)          { return g ? g->profile.comboBest : 0; }
int32_t fly_enemy_defeated_total(void){ return g ? g->profile.enemiesDefeated : 0; }
int32_t fly_total_score(void)         { return g ? g->profile.totalScore : 0; }
int32_t fly_skill_points(void)        { return g ? g->profile.skillPoints : 0; }

float fly_skill_level(int32_t skill) {
    return g ? g->profile.skills.level((int)skill) : 0.0f;
}

int32_t fly_upgrade_skill(int32_t skill) {
    return (g && g->upgradeSkill((int)skill)) ? 1 : 0;
}

void fly_wind(FlyVec3* wind, float* turbulence) {
    if (!g) return;
    if (wind) *wind = v3(g->fluid.windVelocity);
    if (turbulence) *turbulence = g->fluid.turbulenceLevel;
}

