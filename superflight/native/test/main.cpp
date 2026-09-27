// main.cpp — test harness del motore di volo (senza grafica).
// Simula minuti di gioco a 120Hz e stampa statistiche di prestazione.

#include "../engine/game_api.h"
#include <cstdio>
#include <chrono>
#include <cmath>

int main() {
    printf("== SuperFlight: test motore ==\n");
    fly_create();

    // Input simulato: curva morbida + boost periodico.
    auto fakeInput = [](double t) {
        float p = 0.45f * std::sin(t * 0.9);
        float y = 0.6f * std::sin(t * 0.37 + 1.0);
        float r = 0.3f * std::sin(t * 1.7);
        fly_set_stick(p, y, r);
        fly_set_boost((std::fmod(t, 9.0) > 6.0) ? 1 : 0);
        fly_set_laser((std::fmod(t, 7.0) > 5.0) ? 1 : 0);
    };

    // Test nuovo ciclo di gioco: menu → startGame → camminata/salto/volo.
    printf("-- ciclo menu/azione --\n");
    fly_reset(0);
    if (fly_state() != 0) { printf("FALLITO: stato iniziale non e' Menu\n"); return 1; }
    fly_start_game();
    if (fly_state() != 3) { printf("FALLITO: startGame non porta a Walking\n"); return 1; }
    fly_set_stick(0.0f, 0.0f, 0.0f);   // fermo
    fly_jump();                        // salto
    for (int i = 0; i < 30; ++i) fly_update(1.0/120.0, 1170, 2532);
    fly_jump();                        // secondo salto → decollo
    for (int i = 0; i < 60; ++i) fly_update(1.0/120.0, 1170, 2532);
    if (fly_state() != 1) { printf("FALLITO: doppio salto non decolla\n"); return 1; }
    fly_toggle_fly();                  // atterraggio
    for (int i = 0; i < 240; ++i) fly_update(1.0/120.0, 1170, 2532);   // 2 s: deve toccare terra
    if (fly_state() != 3) { printf("FALLITO: atterraggio non torna a Walking\n"); return 1; }
    printf("OK menu/salto/volo/atterraggio\n");

    // Test NPC: devono esistere e scappare quando il laser spara vicino.
    fly_start_game();
    for (int i = 0; i < 30; ++i) fly_update(1.0/120.0, 1170, 2532);
    int npcCount = fly_npc_count();
    if (npcCount < 5) { printf("FALLITO: NPC insufficienti (%d)\n", npcCount); return 1; }
    fly_set_laser(1);
    for (int i = 0; i < 120; ++i) fly_update(1.0/120.0, 1170, 2532);   // 1 s di raffica
    int fleeing = 0;
    for (int i = 0; i < npcCount; ++i) {
        FlyVec3 pos; float yaw, phase, tint; int32_t flee;
        fly_npc((int32_t)i, &pos, &yaw, &phase, &flee, &tint);
        if (flee) ++fleeing;
    }
    fly_set_laser(0);
    printf("NPC: %d, in fuga col laser: %d\n", npcCount, fleeing);
    if (fleeing == 0) { printf("FALLITO: nessun NPC scappa dal laser\n"); return 1; }

    // Test gameplay AAA: nemici con AI, proiettili, combo, skill, vento.
    printf("-- gameplay AAA (nemici/combo/skill/vento) --\n");
    fly_reset(0);
    fly_start_game();
    fly_toggle_fly();                     // decolla subito
    for (int i = 0; i < 60; ++i) fly_update(1.0/120.0, 1170, 2532);
    if (fly_state() != 1) { printf("FALLITO: non e' in volo\n"); return 1; }
    // Vola dritto per 12 s: almeno un'ondata di nemici deve spawnare.
    for (int i = 0; i < 1440; ++i) fly_update(1.0/120.0, 1170, 2532);
    int eCount = fly_enemy_count();
    FlyVec3 wind; float turb = -1.0f;
    fly_wind(&wind, &turb);
    printf("Nemici: %d, proiettili: %d, vita: %.2f, vento: (%.1f, %.1f, %.1f) m/s, turb: %.2f\n",
           eCount, fly_projectile_count(), fly_health(),
           wind.x, wind.y, wind.z, turb);
    if (eCount <= 0) { printf("FALLITO: nessun nemico generato in volo\n"); return 1; }
    if (turb < 0.0f || turb > 1.0f) { printf("FALLITO: turbolenza fuori range\n"); return 1; }
    if (wind.x == 0 && wind.y == 0 && wind.z == 0) { printf("FALLITO: vento nullo\n"); return 1; }
    // Danni subiti o no, la vita resta in [0,1].
    float hp = fly_health();
    if (hp < 0.0f || hp > 1.0f) { printf("FALLITO: vita fuori range\n"); return 1; }
    // Skill tree: simula punteggio alto e spendi punti.
    for (int i = 0; i < 3; ++i) fly_upgrade_skill(0);   // senza punti: no-op
    if (fly_skill_points() != 0) { printf("FALLITO: skill senza punti\n"); return 1; }
    printf("OK gameplay AAA\n");

    const double dt = 1.0 / 120.0;          // fixed timestep 120 Hz
    const double duration = 180.0;          // simula 3 minuti di gioco
    int resets = 0;
    long long ticks = 0;

    auto t0 = std::chrono::high_resolution_clock::now();
    for (double t = 0; t < duration; t += dt) {
        fakeInput(t);
        fly_update(dt, 1170, 2532);
        ++ticks;

        // Dopo un periodo di grazia: se siamo in crash/menu, riparte.
        if (t > 20.0 && fly_state() != 1) {
            resets++;
            fly_reset(fly_best());
            fly_start_game();
            fly_toggle_fly();   // decolla subito per la simulazione di volo
        }
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double wallMs = std::chrono::duration<double, std::milli>(t1 - t0).count();

    int b = fly_building_count();
    int state = fly_state();
    int destroyed = 0;
    for (int i = 0; i < b; ++i) {
        FlyVec3 pos, size; float hue;
        fly_building((int32_t)i, &pos, &size, &hue);
        if (size.y <= 0.0f) ++destroyed;
    }
    printf("Stato finale    : %d (0=Menu 1=Flying 2=Crashed)\n", state);
    printf("Punteggio       : %d (best %d), anelli: %d\n",
           fly_score(), fly_best(), fly_rings());
    printf("Edifici attivi  : %d (distrutti dal laser: %d)\n", b, destroyed);
    printf("Calore laser    : %.2f\n", fly_laser_heat());
    printf("Particelle      : %d\n", fly_particle_count());
    printf("Tempo simulato  : %.0f s  (%lld tick 120Hz)\n", duration, ticks);
    printf("Wall time       : %.1f ms  ->  %.2f us/tick\n", wallMs,
           wallMs * 1000.0 / (double)ticks);
    printf("Speed real-time : %.0fx\n", (duration * 1000.0) / wallMs);
    printf("Reset (crash)   : %d\n", resets);

    // Invarianti: mondo popolato, tick eseguiti, stato valido.
    if (b < 20 || ticks < 1000 || state < 0 || state > 2) {
        printf("FALLITO: invarianti non rispettate (b=%d ticks=%lld state=%d)\n",
               b, ticks, state);
        return 1;
    }
    printf("OK\n");
    fly_destroy();
    return 0;
}
