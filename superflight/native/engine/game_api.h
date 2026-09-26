#pragma once
// game_api.h — API C stabile per il bridge Swift (nessuna esposizione C++).

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FlyVec3 { float x, y, z; } FlyVec3;

// Ciclo di vita
void  fly_create(void);                 // crea il gioco
void  fly_destroy(void);
void  fly_reset(int32_t best_score);    // (ri)parte: Stato Flying
void  fly_update(double dt, int32_t screen_w, int32_t screen_h);

// Input (-1..1)
void  fly_set_stick(float pitch, float yaw, float roll);
void  fly_set_boost(int32_t on);

// Lettura stato
int32_t fly_state(void);                // 0=Menu 1=Flying 2=Crashed
int32_t fly_score(void);
int32_t fly_best(void);
int32_t fly_rings(void);
float   fly_speed(void);
float   fly_boost(void);                // 0..1
float   fly_altitude(void);
float   fly_shake(void);
double  fly_time(void);

// Posizioni per il renderer
FlyVec3 fly_player_pos(void);
FlyVec3 fly_player_quat(void);          // (x,y,z) del quaternione; w = sqrt(1-|v|^2)
FlyVec3 fly_cam_pos(void);
FlyVec3 fly_cam_quat(void);

// Contenuto mondo (per il renderer Swift/Metal)
int32_t fly_building_count(void);
void    fly_building(int32_t i, FlyVec3* pos, FlyVec3* size, float* hue);
int32_t fly_ring_count(void);
void    fly_ring(int32_t i, FlyVec3* pos, FlyVec3* quat, float* radius,
                 int32_t* passed);
int32_t fly_particle_count(void);
void    fly_particle(int32_t i, FlyVec3* pos, float* size, float* life01,
                     float* hue);

#ifdef __cplusplus
}
#endif
