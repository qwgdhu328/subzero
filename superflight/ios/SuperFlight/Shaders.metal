// Shaders.metal — rendering: città, finestre realistiche, glow (anelli/laser/particelle).

#include <metal_stdlib>
using namespace metal;

struct FlyUniforms {
    float4x4 viewProj;
    float3 cameraPos;
    float time;
    float3 pad;
};

struct InstanceData {
    float4x4 model;
    float4 color;
};

struct VertexOut {
    float4 pos [[position]];
    float3 world;
    float3 normal;
    float4 color;
    float3 local;
    float3 scale;   // dimensione mondo del box per questa istanza
};

// Cubo unitario centrato: 36 vertici (posizione, normale)
constant float3 cubeVerts[36] = {
    float3(-1,-1,-1), float3(1,-1,-1), float3(1,1,-1),
    float3(-1,-1,-1), float3(1,1,-1),  float3(-1,1,-1),
    float3(1,-1,1),  float3(-1,-1,1), float3(-1,1,1),
    float3(1,-1,1),  float3(-1,1,1),  float3(1,1,1),
    float3(-1,-1,1), float3(-1,-1,-1), float3(-1,1,-1),
    float3(-1,-1,1), float3(-1,1,-1), float3(-1,1,1),
    float3(1,-1,1),  float3(1,-1,-1), float3(1,1,-1),
    float3(1,-1,1),  float3(1,1,-1),  float3(1,1,1),
    float3(-1,1,1),  float3(-1,1,-1), float3(1,1,-1),
    float3(-1,1,1),  float3(1,1,-1), float3(1,1,1),
    float3(-1,-1,-1), float3(-1,-1,1), float3(1,-1,1),
    float3(-1,-1,-1), float3(1,-1,1),  float3(1,-1,-1),
};
constant float3 cubeNormals[6] = {
    float3(0,0,-1), float3(0,0,1), float3(-1,0,0),
    float3(1,0,0), float3(0,1,0), float3(0,-1,0)
};

// Estrae la dimensione mondo del box dalla matrice modello
// (le colonne sono gli assi scalati: |col| = metà-dimensione * 2).
static inline float3 boxScale(float4x4 m) {
    return float3(length(m.columns[0].xyz),
                  length(m.columns[1].xyz),
                  length(m.columns[2].xyz));
}

vertex VertexOut vertexMain(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            constant FlyUniforms &u [[buffer(1)]],
                            const device InstanceData* instances [[buffer(2)]],
                            constant int32_t &count [[buffer(3)]])
{
    VertexOut out;
    uint vi = vid % 36;
    uint face = vi / 6;
    float3 lp = cubeVerts[vi];
    float3 n = cubeNormals[face];

    float4 world = instances[iid].model * float4(lp, 1.0);
    out.pos = u.viewProj * world;
    out.world = world.xyz;
    out.normal = normalize((instances[iid].model * float4(n, 0.0)).xyz);
    out.color = instances[iid].color;
    out.local = lp;
    out.scale = boxScale(instances[iid].model);
    return out;
}

// ------------------------------------------------------------ //
//  Città: facciate realistiche con finestre proporzionate
// ------------------------------------------------------------ //

// Hash senza artefatti di banda (valore puro, no sin-trick).
static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fragment float4 fragmentMain(VertexOut in [[stage_in]],
                             constant FlyUniforms &u [[buffer(1)]])
{
    float3 n = normalize(in.normal);
    float3 s = max(in.scale, float3(0.001));

    // Piano della facciata: dimensioni reali (metri) → griglia in metri.
    float2 fs;                       // (larghezza facciata, altezza facciata) in metri
    float2 uv;                       // coordinate in metri sulla facciata
    float2 faceId = float2(0);       // per variare i pattern tra facce diverse
    if (abs(n.y) > 0.5) {            // tetto / base
        fs = s.xz;
        uv = in.local.xz;
    } else if (abs(n.x) > 0.5) {     // facciata laterale (Z = profondità)
        fs = s.zy;
        uv = in.local.zy;
        faceId = float2(in.normal.x > 0 ? 1 : 2, 0);
    } else {                         // facciata frontale (X = larghezza)
        fs = s.xy;
        uv = in.local.xy;
        faceId = float2(in.normal.z > 0 ? 3 : 4, 0);
    }

    // Finestre: pannello 4 m largo, 3.5 m alto (piano + solaio), vetro 2.4x1.8 m.
    float2 cell  = float2(4.0, 3.5);
    float2 glass = float2(2.4, 1.8);
    float2 floorUV = uv + fs * 0.5;                       // 0..fs dal bordo
    float2 cellIJ  = floor(floorUV / cell);
    float2 inCell  = fract(floorUV / cell);               // 0..1 dentro il pannello

    // Margine per mantenere il vetro proporzionato anche sull'ultima colonna.
    float2 glassUV = inCell * cell / glass;
    bool inGlass = all(glassUV < 1.0);

    // Soffitto/pavimento del pannello: banda scura (solaio).
    float slab = inCell.y > 0.86 ? 1.0 : 0.0;

    // Vetrate accese: per-building deterministico (derivato dalla posizione mondo
    // via faceId + cella), ~38% accese con luminosità variabile.
    float seed = hash12(cellIJ + faceId * 17.17 + floor(in.world.xz * 0.01) * 7.7);
    float lit  = step(0.62, seed);
    float bright = 0.55 + 0.45 * hash12(cellIJ * 1.7 + faceId + 4.2);

    // Tipi di facciata: vetro continuo (torri moderne) vs finestre punteggiate.
    float style = hash12(floor(in.world.xz * 0.013) + floor(in.world.y * 0.013));
    float curtain = step(0.72, style);                    // 28% torri "curtain wall"

    float3 base = in.color.rgb;
    float3 col;

    if (abs(n.y) > 0.5) {
        // Tetto: ghiaia scura + Unità di condizionamento come dettaglio.
        col = base * 0.35;
        float ac = step(0.8, hash12(floor(uv * 0.5)));
        col += float3(0.10) * ac;
    } else {
        float3 wall = base * (0.30 + 0.12 * max(0.0, dot(n, normalize(float3(0.35, 0.5, 0.6)))));
        float3 glassCol = float3(0.06, 0.10, 0.16);       // vetro spento (riflesso cielo)
        float3 litCol = mix(float3(1.0, 0.85, 0.55), float3(0.75, 0.9, 1.0),
                            hash12(cellIJ.yx + faceId + 9.1));  // caldo o freddo
        float3 pane = mix(glassCol, litCol * bright * 1.7, lit);

        if (curtain > 0.5) {
            // Curtain wall: tutta la facciata vetro, bleu con riflesso cielo.
            float3 cw = mix(float3(0.10, 0.16, 0.24), float3(0.35, 0.5, 0.68),
                            0.5 + 0.5 * in.local.y);
            pane = mix(cw, litCol * bright * 1.6, lit * 0.85);
            col = pane;
        } else {
            // Cemento + pannelli vetro; solaio scuro tra i piani.
            col = mix(wall, pane, inGlass ? 1.0 : 0.0);
            col = mix(col, wall * 0.45, slab);
        }

        // Danni da laser: annerimento crescente con il danno.
        col *= 1.0 - in.color.a * 0.75;                    // color.a veicola il danno
        col = mix(col, float3(0.12, 0.08, 0.06), in.color.a * 0.6);
    }

    // Illuminazione: sole basso (tramonto) + ombreggiatura direzionale.
    float sun = max(0.0, dot(n, normalize(float3(0.45, 0.55, 0.35))));
    col *= 0.62 + 0.55 * sun;
    // Vetro spende riflesso verso il cielo.
    float skyRefl = pow(1.0 - abs(n.y), 3.0) * 0.12;
    col += float3(0.45, 0.6, 0.9) * skyRefl;

    // Nebbia atmosferica in lontananza.
    float dist = length(u.cameraPos - in.world);
    float fog = 1.0 - exp(-dist * 0.0011);
    float3 fogCol = float3(0.55, 0.65, 0.85);
    col = mix(col, fogCol, clamp(fog, 0.0, 0.85));
    return float4(col, 1.0);
}

// ------------------------------------------------------------ //
//  Glow additivo: anelli, laser, particelle, boost
// ------------------------------------------------------------ //

fragment float4 glowFragment(VertexOut in [[stage_in]],
                             constant FlyUniforms &u [[buffer(1)]])
{
    float edge = 1.0 - abs(in.local.y);
    float a = in.color.a * (0.35 + 0.65 * edge);
    float3 col = in.color.rgb * (1.5 + edge);
    float dist = length(u.cameraPos - in.world);
    float fog = 1.0 - exp(-dist * 0.0011);
    col = mix(col, float3(0.55, 0.65, 0.85), clamp(fog, 0.0, 0.85) * (1.0 - a));
    return float4(col * a, a);
}
