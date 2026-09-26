#pragma once
// math.h — piccola libreria math 3D (vettori, quaternioni, matrici)
// Dipendenza-zero: nessun framework, compilabile ovunque (C++17).

#include <cmath>

namespace fly {

constexpr float PI = 3.14159265358979f;
constexpr float TAU = 2.0f * PI;

inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline float lerpf(float a, float b, float t) { return a + (b - a) * t; }
inline float smoothstepf(float a, float b, float t) {
    t = clampf((t - a) / (b - a), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f);
}

struct Vec3 {
    float x = 0, y = 0, z = 0;

    Vec3() = default;
    Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}

    Vec3 operator+(const Vec3& o) const { return {x + o.x, y + o.y, z + o.z}; }
    Vec3 operator-(const Vec3& o) const { return {x - o.x, y - o.y, z - o.z}; }
    Vec3 operator*(float s) const { return {x * s, y * s, z * s}; }
    Vec3 operator/(float s) const { return {x / s, y / s, z / s}; }
    Vec3 operator-() const { return {-x, -y, -z}; }

    Vec3& operator+=(const Vec3& o) { x += o.x; y += o.y; z += o.z; return *this; }
    Vec3& operator-=(const Vec3& o) { x -= o.x; y -= o.y; z -= o.z; return *this; }
    Vec3& operator*=(float s) { x *= s; y *= s; z *= s; return *this; }

    float length() const { return std::sqrt(x * x + y * y + z * z); }
    float lengthSq() const { return x * x + y * y + z * z; }

    Vec3 normalized() const {
        float len = length();
        return len > 1e-8f ? *this / len : Vec3(0, 0, 1);
    }

    static float dot(const Vec3& a, const Vec3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
    static Vec3 cross(const Vec3& a, const Vec3& b) {
        return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
    }
    static Vec3 lerp(const Vec3& a, const Vec3& b, float t) {
        return {lerpf(a.x, b.x, t), lerpf(a.y, b.y, t), lerpf(a.z, b.z, t)};
    }
};

// Quaternione (x, y, z, w) per rotazioni senza gimbal lock.
struct Quat {
    float x = 0, y = 0, z = 0, w = 1;

    Quat() = default;
    Quat(float x_, float y_, float z_, float w_) : x(x_), y(y_), z(z_), w(w_) {}

    static Quat fromAxisAngle(const Vec3& axis, float angleRad) {
        Vec3 a = axis.normalized();
        float s = std::sin(angleRad * 0.5f);
        return {a.x * s, a.y * s, a.z * s, std::cos(angleRad * 0.5f)};
    }

    Quat operator*(const Quat& o) const {
        return {
            w * o.x + x * o.w + y * o.z - z * o.y,
            w * o.y - x * o.z + y * o.w + z * o.x,
            w * o.z + x * o.y - y * o.x + z * o.w,
            w * o.w - x * o.x - y * o.y - z * o.z,
        };
    }

    Quat normalized() const {
        float len = std::sqrt(x * x + y * y + z * z + w * w);
        if (len < 1e-10f) return {};
        return {x / len, y / len, z / len, w / len};
    }

    static Quat slerp(const Quat& a, const Quat& b, float t) {
        float dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
        Quat bb = b;
        if (dot < 0.0f) { bb = {-b.x, -b.y, -b.z, -b.w}; dot = -dot; }
        if (dot > 0.9995f) {
            return Quat(lerpf(a.x, bb.x, t), lerpf(a.y, bb.y, t),
                        lerpf(a.z, bb.z, t), lerpf(a.w, bb.w, t)).normalized();
        }
        float theta0 = std::acos(dot);
        float theta = theta0 * t;
        float s0 = std::cos(theta) - dot * std::sin(theta) / std::sin(theta0);
        float s1 = std::sin(theta) / std::sin(theta0);
        return Quat(a.x * s0 + bb.x * s1, a.y * s0 + bb.y * s1,
                    a.z * s0 + bb.z * s1, a.w * s0 + bb.w * s1).normalized();
    }

    Vec3 rotate(const Vec3& v) const {
        // v' = q * (v,0) * q^-1 (formula ottimizzata)
        Vec3 q(x, y, z);
        Vec3 t = Vec3::cross(q, v) * 2.0f;
        return v + t * w + Vec3::cross(q, t);
    }

    Vec3 forward() const { return rotate({0, 0, -1}); }
    Vec3 up() const { return rotate({0, 1, 0}); }
    Vec3 right() const { return rotate({1, 0, 0}); }
};

// Matrice 4x4 column-major (compatible Metal/GL).
struct Mat4 {
    float m[16] = {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    };

    static Mat4 perspective(float fovYRad, float aspect, float zNear, float zFar) {
        float f = 1.0f / std::tan(fovYRad * 0.5f);
        float nd = 1.0f / (zNear - zFar);
        Mat4 r;
        r.m[0] = f / aspect;
        r.m[5] = f;
        r.m[10] = zFar * nd;
        r.m[11] = -1.0f;
        r.m[14] = zNear * zFar * nd;
        r.m[1] = r.m[2] = r.m[3] = r.m[4] = 0;
        r.m[6] = r.m[7] = r.m[8] = r.m[9] = 0;
        r.m[12] = r.m[13] = r.m[15] = 0;
        return r;
    }

    // Vista dal quaternione q e posizione pos.
    static Mat4 lookFrom(const Vec3& pos, const Quat& q) {
        // Le colonne sono gli assi della camera.
        Vec3 right = q.right();
        Vec3 up = q.up();
        Vec3 fwd = q.forward(); // -Z

        Mat4 r;
        r.m[0] = right.x;  r.m[4] = right.y;  r.m[8] = right.z;
        r.m[1] = up.x;     r.m[5] = up.y;     r.m[9] = up.z;
        r.m[2] = -fwd.x;   r.m[6] = -fwd.y;   r.m[10] = -fwd.z;
        r.m[12] = -Vec3::dot(right, pos);
        r.m[13] = -Vec3::dot(up, pos);
        r.m[14] = Vec3::dot(fwd, pos);
        r.m[3] = r.m[7] = r.m[15] = 0;
        r.m[15] = 1;
        return r;
    }

    static Mat4 translate(const Vec3& t) {
        Mat4 r;
        r.m[12] = t.x; r.m[13] = t.y; r.m[14] = t.z;
        return r;
    }

    static Mat4 scale(const Vec3& s) {
        Mat4 r;
        r.m[0] = s.x; r.m[5] = s.y; r.m[10] = s.z;
        return r;
    }

    static Mat4 rotateY(float a) {
        Mat4 r;
        float c = std::cos(a), s = std::sin(a);
        r.m[0] = c; r.m[2] = -s;
        r.m[8] = s; r.m[10] = c;
        return r;
    }

    static Mat4 mul(const Mat4& a, const Mat4& b) {
        Mat4 r;
        for (int col = 0; col < 4; ++col)
            for (int row = 0; row < 4; ++row) {
                float s = 0;
                for (int k = 0; k < 4; ++k)
                    s += a.m[k * 4 + row] * b.m[col * 4 + k];
                r.m[col * 4 + row] = s;
            }
        return r;
    }
};

} // namespace fly
