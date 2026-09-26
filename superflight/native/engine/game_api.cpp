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

int32_t fly_state(void)    { return g ? (int32_t)g->state : 0; }
int32_t fly_score(void)    { return g ? g->score : 0; }
int32_t fly_best(void)     { return g ? g->bestScore : 0; }
int32_t fly_rings(void)    { return g ? g->ringsPassed : 0; }
float   fly_speed(void)    { return g ? g->speed : 0; }
float   fly_boost(void)    { return g ? g->boostFuel : 0; }
float   fly_altitude(void) { return g ? g->altitude : 0; }
float   fly_shake(void)    { return g ? g->shake : 0; }
double  fly_time(void)     { return g ? g->time : 0; }

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
