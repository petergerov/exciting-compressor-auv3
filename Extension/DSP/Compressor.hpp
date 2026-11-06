#pragma once

#include <algorithm>
#include <cmath>

namespace ec {

/// Feed-forward, log-domain compressor gain computer with a smooth
/// branching attack/release detector (Giannoulis, Massberg & Reiss, JAES 2012).
/// Operates on a linked detector level and returns gain reduction in dB (<= 0).
class Compressor {
public:
    /// Input level at which auto makeup restores unity gain. A typical
    /// tracked vocal sits around here, so the excite path comes back
    /// roughly level-matched with the natural path before its blend fader.
    static constexpr float kMakeupReferenceDB = -18.0f;

    void setSampleRate(double sampleRate) noexcept {
        sampleRate_ = sampleRate;
        updateTimeConstants();
    }

    void setThreshold(float dB) noexcept { thresholdDB_ = dB; }
    void setRatio(float ratio) noexcept { ratio_ = std::max(ratio, 1.0f); }
    void setKnee(float dB) noexcept { kneeDB_ = std::max(dB, 0.0f); }

    void setAttack(float ms) noexcept {
        attackMs_ = ms;
        updateTimeConstants();
    }

    void setRelease(float ms) noexcept {
        releaseMs_ = ms;
        updateTimeConstants();
    }

    void reset() noexcept { smoothedGainDB_ = 0.0f; }

    /// Static compression curve: output level (dB) for an input level (dB).
    float staticCurveDB(float inputDB) const noexcept {
        const float overshoot = inputDB - thresholdDB_;
        const float slope = 1.0f / ratio_ - 1.0f;

        if (2.0f * overshoot < -kneeDB_) {
            return inputDB;
        }
        if (kneeDB_ > 0.0f && 2.0f * std::fabs(overshoot) <= kneeDB_) {
            const float t = overshoot + kneeDB_ * 0.5f;
            return inputDB + slope * t * t / (2.0f * kneeDB_);
        }
        return thresholdDB_ + overshoot / ratio_;
    }

    /// Gain that brings a signal at `kMakeupReferenceDB` back to unity.
    float autoMakeupDB() const noexcept {
        return kMakeupReferenceDB - staticCurveDB(kMakeupReferenceDB);
    }

    /// Advance the detector by one sample. Returns smoothed gain change in dB.
    float process(float detectorLevel) noexcept {
        const float inputDB = 20.0f * std::log10(std::max(detectorLevel, 1.0e-6f));
        const float targetGainDB = staticCurveDB(inputDB) - inputDB;

        const float coeff = targetGainDB < smoothedGainDB_ ? attackCoeff_ : releaseCoeff_;
        smoothedGainDB_ = coeff * smoothedGainDB_ + (1.0f - coeff) * targetGainDB;
        return smoothedGainDB_;
    }

private:
    static float timeConstantCoeff(float ms, double sampleRate) noexcept {
        const double seconds = std::max(ms, 0.01f) * 0.001;
        return static_cast<float>(std::exp(-1.0 / (seconds * sampleRate)));
    }

    void updateTimeConstants() noexcept {
        attackCoeff_ = timeConstantCoeff(attackMs_, sampleRate_);
        releaseCoeff_ = timeConstantCoeff(releaseMs_, sampleRate_);
    }

    double sampleRate_ = 48000.0;
    float thresholdDB_ = -35.0f;
    float ratio_ = 20.0f;
    float kneeDB_ = 6.0f;
    float attackMs_ = 2.0f;
    float releaseMs_ = 150.0f;
    float attackCoeff_ = 0.0f;
    float releaseCoeff_ = 0.0f;
    float smoothedGainDB_ = 0.0f;
};

} // namespace ec
