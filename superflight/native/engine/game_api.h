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
void  fly_set_laser(int32_t on);           // raffica di raggi oculari
void  fly_jump(void);                      // salto (a piedi)
void  fly_toggle_fly(void);                // decollo / atterraggio
void  fly_start_game(void);                // "AVVIA PARTITA" dal menu
void  fly_set_limits(int32_t max_npcs, int32_t max_particles);  // qualità grafica

// Lettura stato
int32_t fly_state(void);                // 0=Menu 1=Flying 2=Crashed 3=Walking
int32_t fly_score(void);
int32_t fly_best(void);
int32_t fly_rings(void);
float   fly_speed(void);
float   fly_boost(void);                // 0..1
float   fly_altitude(void);
float   fly_shake(void);
double  fly_time(void);
float   fly_laser_heat(void);              // 0..1 (1 = surriscaldato)
int32_t fly_laser_active(void);            // raffica in corso (1/0)
int32_t fly_laser_hit(void);               // il raggio colpisce qualcosa (1/0)
int32_t fly_on_ground(void);               // a piedi e a terra (per pose/animazioni)
float   fly_anim_phase(void);              // fase ciclo camminata/corsa (per il renderer)
float   fly_sonic_ripple(void);            // onda d'urto post-Mach 1 (0..1)
int32_t fly_supersonic(void);              // oltre Mach 1 (per FOV dinamico)

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

// Raggi oculari (per il renderer)
void    fly_laser(FlyVec3* eye, FlyVec3* end, int32_t* active, float* heat);
int32_t fly_laser_seg_count(void);
void    fly_laser_seg(int32_t i, FlyVec3* a, FlyVec3* b, float* width,
                      float* life01);

// Detriti fisici (per il renderer)
int32_t fly_debris_count(void);
void    fly_debris(int32_t i, FlyVec3* pos, FlyVec3* size, float* spin,
                   float* spinAxis);

// Pedoni NPC (per il renderer)
int32_t fly_npc_count(void);
void    fly_npc(int32_t i, FlyVec3* pos, float* yaw, float* phase,
                int32_t* flee, float* tint);

#ifdef __cplusplus
}
#endif
