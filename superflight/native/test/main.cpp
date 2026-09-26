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
    };

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
        }
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double wallMs = std::chrono::duration<double, std::milli>(t1 - t0).count();

    int b = fly_building_count();
    int state = fly_state();
    printf("Stato finale    : %d (0=Menu 1=Flying 2=Crashed)\n", state);
    printf("Punteggio       : %d (best %d), anelli: %d\n",
           fly_score(), fly_best(), fly_rings());
    printf("Edifici attivi  : %d\n", b);
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
