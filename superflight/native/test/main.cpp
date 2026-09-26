// main.cpp — test harness del motore di volo (senza grafica).
// Simula minuti di gioco a 60fps e stampa statistiche di prestazione.

#include "../engine/game_api.h"
#include <cstdio>
#include <chrono>
#include <cmath>

int main() {
    printf("== SuperFlight: test motore ==\n");
    fly_create();

    // Simula input: curva morbida + boost periodico.
    auto fakeInput = [](double t) {
        float p = 0.45f * std::sinf(t * 0.9f);
        float y = 0.6f * std::sinf(t * 0.37f + 1.0f);
        float r = 0.3f * std::sinf(t * 1.7f);
        fly_set_stick(p, y, r);
        fly_set_boost((std::fmod(t, 9.0) > 6.0) ? 1 : 0);
    };

    const double dt = 1.0 / 120.0;          // fixed timestep 120 Hz
    const double duration = 180.0;          // simula 3 minuti di gioco
    double crashes = 0;

    auto t0 = std::chrono::high_resolution_clock::now();
    for (double t = 0; t < duration; t += dt) {
        fakeInput(t);
        fly_update(dt, 1170, 2532);

        if (t > 30.0 && fly_state() == 2) {   // dopo il primo eventuale crash
            crashes++;
            fly_reset(fly_best());
        }
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double wallMs = std::chrono::duration<double, std::milli>(t1 - t0).count();

    int b = fly_building_count();
    printf("Stato finale    : %d (0=Menu 1=Flying 2=Crashed)\n", fly_state());
    printf("Punteggio       : %d (best %d), anelli: %d\n",
           fly_score(), fly_best(), fly_rings());
    printf("Edifici attivi  : %d\n", b);
    printf("Particelle      : %d\n", fly_particle_count());
    printf("Tempo simulato  : %.0f s  (%.0f tick 120Hz)\n", duration, duration / dt);
    printf("Wall time       : %.1f ms  →  %.2f µs/tick\n", wallMs,
           wallMs * 1000.0 / (duration / dt));
    printf("Speed real-time : %.0fx\n", (duration * 1000.0) / wallMs);
    printf("Crash & reset   : %.0f\n", crashes);

    // Sanità: dopo 3 minuti deve avere raggiunto velocità > 0 e mondo popolato.
    if (b < 50 || fly_speed() <= 0) {
        printf("FALLITO: mondo insufficiente\n");
        return 1;
    }
    printf("OK\n");
    fly_destroy();
    return 0;
}
