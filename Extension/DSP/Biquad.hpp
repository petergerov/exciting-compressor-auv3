#pragma once

#include <algorithm>
#include <cmath>
#include <numbers>

namespace ec {

enum class EQShape : int {
    bell = 0,
    highShelf = 1,
};

struct BiquadCoefficients {
    double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
};

/// RBJ Audio EQ Cookbook boost/cut filters.
inline BiquadCoefficients makeEQCoefficients(EQShape shape, double frequency, double gainDB,
                                             double q, double sampleRate) {
    frequency = std::clamp(frequency, 10.0, 0.45 * sampleRate);
    q = std::max(q, 0.05);

    const double A = std::pow(10.0, gainDB / 40.0);
    const double w0 = 2.0 * std::numbers::pi * frequency / sampleRate;
    const double cosW = std::cos(w0);
    const double alpha = std::sin(w0) / (2.0 * q);

    double b0, b1, b2, a0, a1, a2;
    switch (shape) {
        case EQShape::highShelf: {
            const double twoSqrtAAlpha = 2.0 * std::sqrt(A) * alpha;
            b0 = A * ((A + 1.0) + (A - 1.0) * cosW + twoSqrtAAlpha);
            b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW);
            b2 = A * ((A + 1.0) + (A - 1.0) * cosW - twoSqrtAAlpha);
            a0 = (A + 1.0) - (A - 1.0) * cosW + twoSqrtAAlpha;
            a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW);
            a2 = (A + 1.0) - (A - 1.0) * cosW - twoSqrtAAlpha;
            break;
        }
        case EQShape::bell:
        default: {
            b0 = 1.0 + alpha * A;
            b1 = -2.0 * cosW;
            b2 = 1.0 - alpha * A;
            a0 = 1.0 + alpha / A;
            a1 = -2.0 * cosW;
            a2 = 1.0 - alpha / A;
            break;
        }
    }

    return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}

/// RBJ Audio EQ Cookbook 2nd-order low-pass (`highPass == false`) or high-pass.
/// Q = 1/√2 gives a Butterworth response.
inline BiquadCoefficients makePassCoefficients(bool highPass, double frequency, double sampleRate,
                                               double q = 0.70710678118654752) {
    frequency = std::clamp(frequency, 10.0, 0.45 * sampleRate);
    const double w0 = 2.0 * std::numbers::pi * frequency / sampleRate;
    const double cosW = std::cos(w0);
    const double alpha = std::sin(w0) / (2.0 * q);
    const double a0 = 1.0 + alpha;

    const double b1 = highPass ? -(1.0 + cosW) : (1.0 - cosW);
    const double b0 = highPass ? (1.0 + cosW) / 2.0 : (1.0 - cosW) / 2.0;
    return {b0 / a0, b1 / a0, b0 / a0, (-2.0 * cosW) / a0, (1.0 - alpha) / a0};
}

/// Transposed direct form II biquad with double-precision state.
class Biquad {
public:
    void setCoefficients(const BiquadCoefficients& c) noexcept { coeffs_ = c; }
    void reset() noexcept { z1_ = z2_ = 0.0; }

    float process(float input) noexcept {
        const double x = input;
        const double y = coeffs_.b0 * x + z1_;
        z1_ = coeffs_.b1 * x - coeffs_.a1 * y + z2_;
        z2_ = coeffs_.b2 * x - coeffs_.a2 * y;
        return static_cast<float>(y);
    }

private:
    BiquadCoefficients coeffs_{};
    double z1_ = 0.0, z2_ = 0.0;
};

} // namespace ec
