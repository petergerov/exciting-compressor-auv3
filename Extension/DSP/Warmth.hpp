#pragma once

// "Warmth": low-order harmonics generated from the body of the voice, to make
// it sound rounder.
//
//   x ─▶ band 90–500 Hz ─▶ 2·b² / env ─▶ high-pass 90 Hz ─▶ low-pass 2 kHz ─▶ harmonics
//
// Squaring produces the octave (2nd harmonic) of every partial, plus sum and
// difference tones between partials. For a voiced sound those all fall on the
// voice's own harmonic series, including the fundamental, which is what reads
// as round and full rather than distorted. There is no 3rd harmonic or above
// from the squarer itself.
//
// Dividing by a peak envelope makes the output scale linearly with level, so
// the knob sets a fixed harmonic-to-signal ratio: a sine of amplitude A in the
// band comes out as a 2nd harmonic of amplitude ≈ A. Because the envelope
// attacks instantly (env ≥ |b|), |b² / env| ≤ |b|: an onset after silence
// cannot produce a spike.
//
// The generated content stays below ~2 kHz, far from Nyquist, so it needs no
// oversampling and adds no latency against the natural path.
//
// Real-time safe: no allocation, locks or system calls.

#include <algorithm>
#include <cmath>

#include "Biquad.hpp"

namespace ec {

class WarmthGenerator {
public:
    static constexpr double kBandLowHz = 90.0;
    static constexpr double kBandHighHz = 500.0;
    static constexpr double kOutputLowHz = 90.0;
    static constexpr double kOutputHighHz = 2000.0;
    static constexpr double kEnvelopeReleaseMs = 100.0;

    void prepare(double sampleRate) noexcept {
        bandHigh_.setCoefficients(makePassCoefficients(true, kBandLowHz, sampleRate));
        bandLow_.setCoefficients(makePassCoefficients(false, kBandHighHz, sampleRate));
        outHigh_.setCoefficients(makePassCoefficients(true, kOutputLowHz, sampleRate));
        outLow_.setCoefficients(makePassCoefficients(false, kOutputHighHz, sampleRate));
        release_ = static_cast<float>(std::exp(-1.0 / (kEnvelopeReleaseMs * 0.001 * sampleRate)));
        reset();
    }

    void reset() noexcept {
        bandHigh_.reset();
        bandLow_.reset();
        outHigh_.reset();
        outLow_.reset();
        envelope_ = 0.0f;
    }

    /// The harmonics alone, at roughly the level of the band they came from.
    float process(float input) noexcept {
        const float band = bandLow_.process(bandHigh_.process(input));
        const float level = std::fabs(band);

        envelope_ = std::max(level, envelope_ * release_);
        // Below −180 dBFS: silence. Also keeps the envelope out of denormals.
        if (envelope_ < 1.0e-9f) envelope_ = 0.0f;

        // The squarer's DC (and the slow envelope motion) is removed by the
        // output high-pass.
        const float squared = envelope_ > 0.0f ? 2.0f * band * band / envelope_ : 0.0f;
        return outLow_.process(outHigh_.process(squared));
    }

private:
    Biquad bandHigh_, bandLow_, outHigh_, outLow_;
    float envelope_ = 0.0f;
    float release_ = 0.999f;
};

} // namespace ec
