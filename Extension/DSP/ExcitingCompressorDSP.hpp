#pragma once

// The Motown "Exciting Compressor" (Lawrence Horn, 1963, as described by Bob Dennis):
//
//   input ──┬──────────────────────────────── × natural level ──┐
//           │                                                   ├─(+)── × output ──▶
//           └─▶ heavy compressor ─┬▶ big presence EQ ──(+)─ × excite ──┘
//                                 └▶ warmth harmonics ─┘ × warmth
//
// The natural path carries the vocal's real dynamics at full level; the
// excite path is squashed flat, brightened hard, and tucked underneath "just
// enough to add excitement and presence".
//
// Real-time safe: no allocation, locks or system calls inside process().

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>

#include "Biquad.hpp"
#include "Compressor.hpp"
#include "Warmth.hpp"
#include "../Support/ECParameterAddress.h"

namespace ec {

inline constexpr float kSilenceDB = -60.0f;

inline float dbToGain(float dB) noexcept { return std::pow(10.0f, dB * 0.05f); }

/// Fader law: the bottom of the range is a true mute.
inline float faderGain(float dB) noexcept { return dB <= kSilenceDB ? 0.0f : dbToGain(dB); }

/// One-pole smoother for de-zippering parameter changes.
class Smoothed {
public:
    void configure(double sampleRate, double timeMs) noexcept {
        coeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (timeMs * 0.001 * sampleRate)));
    }
    void setTarget(float target) noexcept { target_ = target; }
    void snap() noexcept { current_ = target_; }
    float current() const noexcept { return current_; }

    float next() noexcept {
        current_ += (target_ - current_) * coeff_;
        return current_;
    }

    /// Advance `frames` steps at once (control-rate smoothing).
    void advance(int frames) noexcept {
        const float k = 1.0f - std::pow(1.0f - coeff_, static_cast<float>(frames));
        current_ += (target_ - current_) * k;
    }

    bool isSettled() const noexcept {
        return std::fabs(target_ - current_) <= 1.0e-4f * (1.0f + std::fabs(target_));
    }

private:
    float coeff_ = 1.0f;
    float current_ = 0.0f;
    float target_ = 0.0f;
};

/// Peak |sample| per side, held until a reader takes it. The render thread only
/// ever raises the held value (lock-free CAS max), so a transient between two
/// reads can't slip past; the reader swaps it back to zero. Meant for a single
/// reader — the editor's meter loop.
class PeakMeter {
public:
    static_assert(std::atomic<float>::is_always_lock_free);

    /// Render thread.
    void accumulate(float left, float right) noexcept {
        raise(left_, left);
        raise(right_, right);
    }

    /// Any thread: the peaks since the previous take, then start over.
    void take(float& left, float& right) noexcept {
        left = left_.exchange(0.0f, std::memory_order_relaxed);
        right = right_.exchange(0.0f, std::memory_order_relaxed);
    }

    void reset() noexcept {
        left_.store(0.0f, std::memory_order_relaxed);
        right_.store(0.0f, std::memory_order_relaxed);
    }

private:
    static void raise(std::atomic<float>& slot, float value) noexcept {
        // NaN compares false and is dropped.
        float held = slot.load(std::memory_order_relaxed);
        while (value > held &&
               !slot.compare_exchange_weak(held, value, std::memory_order_relaxed)) {
        }
    }

    std::atomic<float> left_{0.0f};
    std::atomic<float> right_{0.0f};
};

class ExcitingCompressorDSP {
public:
    using ChannelPeaks = std::array<float, 8>;

    static constexpr int kMaxChannels = 8;
    static_assert(std::tuple_size_v<ChannelPeaks> == kMaxChannels);
    static constexpr int kControlBlockSize = 32;
    static constexpr float kKneeDB = 6.0f;

    ExcitingCompressorDSP() {
        setParameter(ECParameterAddressNaturalLevel, 0.0f);
        setParameter(ECParameterAddressExciteLevel, -12.0f);
        setParameter(ECParameterAddressThreshold, -35.0f);
        setParameter(ECParameterAddressRatio, 20.0f);
        setParameter(ECParameterAddressAttack, 2.0f);
        setParameter(ECParameterAddressRelease, 150.0f);
        setParameter(ECParameterAddressEqFrequency, 6500.0f);
        setParameter(ECParameterAddressEqGain, 15.0f);
        setParameter(ECParameterAddressEqQ, 0.7f);
        setParameter(ECParameterAddressEqShape, 0.0f);
        setParameter(ECParameterAddressOutputLevel, 0.0f);
        setParameter(ECParameterAddressExciteListen, 0.0f);
        setParameter(ECParameterAddressWarmth, 0.0f);
        setParameter(ECParameterAddressWarmthListen, 0.0f);
        compressor_.setKnee(kKneeDB);
    }

    // MARK: Lifecycle (call off the render thread)

    void prepare(double sampleRate, int channelCount) noexcept {
        sampleRate_ = sampleRate;
        channelCount_ = std::clamp(channelCount, 1, kMaxChannels);

        compressor_.setSampleRate(sampleRate);
        for (Smoothed* s : {&naturalGain_, &exciteGain_, &outputGain_, &listenMix_, &warmthGain_,
                            &warmthListenMix_}) {
            s->configure(sampleRate, 20.0);
        }
        for (auto& warmth : warmth_) warmth.prepare(sampleRate);
        makeupDB_.configure(sampleRate, 50.0);
        eqLogFrequency_.configure(sampleRate, 30.0);
        eqGainDB_.configure(sampleRate, 30.0);
        eqQ_.configure(sampleRate, 30.0);

        reset();
    }

    void reset() noexcept {
        compressor_.reset();
        for (auto& filter : eq_) filter.reset();
        for (auto& warmth : warmth_) warmth.reset();

        pullParameters();
        for (Smoothed* s : {&naturalGain_, &exciteGain_, &outputGain_, &listenMix_, &warmthGain_,
                            &warmthListenMix_, &makeupDB_,
                            &eqLogFrequency_, &eqGainDB_, &eqQ_}) {
            s->snap();
        }
        updateEQCoefficients();
        gainReductionMeter_.store(0.0f, std::memory_order_relaxed);
        inputMeter_.reset();
        outputMeter_.reset();
    }

    // MARK: Parameters (thread-safe)

    void setParameter(uint64_t address, float value) noexcept {
        if (address < EC_PARAMETER_COUNT) {
            parameters_[address].store(value, std::memory_order_relaxed);
        }
    }

    float parameter(uint64_t address) const noexcept {
        return address < EC_PARAMETER_COUNT ? parameters_[address].load(std::memory_order_relaxed)
                                            : 0.0f;
    }

    void setBypassed(bool bypassed) noexcept { bypassed_.store(bypassed, std::memory_order_relaxed); }
    bool isBypassed() const noexcept { return bypassed_.load(std::memory_order_relaxed); }

    /// Most recent gain reduction on the excite path, as a positive dB amount.
    float gainReduction() const noexcept {
        return gainReductionMeter_.load(std::memory_order_relaxed);
    }

    /// Input peak (pre-everything) since the last call, linear, then cleared.
    void takeInputPeak(float& left, float& right) noexcept { inputMeter_.take(left, right); }

    /// Output peak (post output trim) since the last call, linear, then cleared.
    void takeOutputPeak(float& left, float& right) noexcept { outputMeter_.take(left, right); }

    // MARK: Rendering

    /// Non-interleaved processing. `inputs` and `outputs` may alias (in-place).
    void process(const float* const* inputs, float* const* outputs, int channelCount,
                 int frameCount) noexcept {
        channelCount = std::clamp(channelCount, 0, kMaxChannels);

        ChannelPeaks inPeak{};
        ChannelPeaks outPeak{};

        if (isBypassed()) {
            for (int ch = 0; ch < channelCount; ++ch) {
                for (int i = 0; i < frameCount; ++i) {
                    inPeak[ch] = std::max(inPeak[ch], std::fabs(inputs[ch][i]));
                }
                if (outputs[ch] != inputs[ch]) {
                    std::memcpy(outputs[ch], inputs[ch], sizeof(float) * frameCount);
                }
            }
            gainReductionMeter_.store(0.0f, std::memory_order_relaxed);
            publishPeaks(inputMeter_, inPeak, channelCount);
            publishPeaks(outputMeter_, inPeak, channelCount);
            return;
        }

        pullParameters();

        float maxReductionDB = 0.0f;

        for (int start = 0; start < frameCount; start += kControlBlockSize) {
            const int frames = std::min(kControlBlockSize, frameCount - start);
            advanceEQSmoothing(frames);

            for (int i = start; i < start + frames; ++i) {
                // Linked detector so the stereo image doesn't wander.
                float detector = 0.0f;
                for (int ch = 0; ch < channelCount; ++ch) {
                    const float level = std::fabs(inputs[ch][i]);
                    inPeak[ch] = std::max(inPeak[ch], level);
                    detector = std::max(detector, level);
                }

                const float reductionDB = compressor_.process(detector);
                maxReductionDB = std::min(maxReductionDB, reductionDB);
                const float compGain = dbToGain(reductionDB + makeupDB_.next());

                const float natural = naturalGain_.next();
                const float excite = exciteGain_.next();
                const float output = outputGain_.next();
                const float listen = listenMix_.next();
                const float warmth = warmthGain_.next();
                const float warmthListen = warmthListenMix_.next();

                for (int ch = 0; ch < channelCount; ++ch) {
                    const float x = inputs[ch][i];
                    const float compressed = x * compGain;
                    // The generator always runs so its filters stay warm and
                    // turning the knob up never starts from stale state.
                    const float harmonics = warmth_[ch].process(compressed) * warmth;
                    const float excited = eq_[ch].process(compressed) + harmonics;

                    const float mix = x * natural + excited * excite;
                    // "Excite listen" solos the excite path pre-fader for setup.
                    float monitored = mix + (excited - mix) * listen;
                    // "Warmth listen" solos only what the Warmth knob adds, also
                    // pre-fader. It takes precedence if both are on.
                    monitored += (harmonics - monitored) * warmthListen;
                    const float y = monitored * output;
                    outPeak[ch] = std::max(outPeak[ch], std::fabs(y));
                    outputs[ch][i] = y;
                }
            }
        }

        gainReductionMeter_.store(-maxReductionDB, std::memory_order_relaxed);
        publishPeaks(inputMeter_, inPeak, channelCount);
        publishPeaks(outputMeter_, outPeak, channelCount);
    }

private:
    /// Channel 0 is left; anything above folds into right. Mono shows on both.
    static void publishPeaks(PeakMeter& meter, const ChannelPeaks& peaks, int channelCount) noexcept {
        if (channelCount <= 0) return;
        float right = channelCount == 1 ? peaks[0] : 0.0f;
        for (int ch = 1; ch < channelCount; ++ch) right = std::max(right, peaks[ch]);
        meter.accumulate(peaks[0], right);
    }

    void pullParameters() noexcept {
        naturalGain_.setTarget(faderGain(parameter(ECParameterAddressNaturalLevel)));
        exciteGain_.setTarget(faderGain(parameter(ECParameterAddressExciteLevel)));
        outputGain_.setTarget(dbToGain(parameter(ECParameterAddressOutputLevel)));
        listenMix_.setTarget(parameter(ECParameterAddressExciteListen) >= 0.5f ? 1.0f : 0.0f);
        // 0–100 % → harmonics from silent up to the level of the band they come from.
        warmthGain_.setTarget(std::clamp(parameter(ECParameterAddressWarmth), 0.0f, 100.0f) * 0.01f);
        warmthListenMix_.setTarget(parameter(ECParameterAddressWarmthListen) >= 0.5f ? 1.0f : 0.0f);

        compressor_.setThreshold(parameter(ECParameterAddressThreshold));
        compressor_.setRatio(parameter(ECParameterAddressRatio));

        const float attack = parameter(ECParameterAddressAttack);
        const float release = parameter(ECParameterAddressRelease);
        if (attack != cachedAttack_) {
            compressor_.setAttack(attack);
            cachedAttack_ = attack;
        }
        if (release != cachedRelease_) {
            compressor_.setRelease(release);
            cachedRelease_ = release;
        }
        makeupDB_.setTarget(compressor_.autoMakeupDB());

        eqLogFrequency_.setTarget(std::log(std::max(parameter(ECParameterAddressEqFrequency), 20.0f)));
        eqGainDB_.setTarget(parameter(ECParameterAddressEqGain));
        eqQ_.setTarget(parameter(ECParameterAddressEqQ));

        const auto shape = parameter(ECParameterAddressEqShape) >= 0.5f ? EQShape::highShelf
                                                                         : EQShape::bell;
        if (shape != eqShape_) {
            eqShape_ = shape;
            eqDirty_ = true;
        }
    }

    void advanceEQSmoothing(int frames) noexcept {
        const bool moving =
            !eqLogFrequency_.isSettled() || !eqGainDB_.isSettled() || !eqQ_.isSettled();
        if (!moving && !eqDirty_) return;

        if (moving) {
            eqLogFrequency_.advance(frames);
            eqGainDB_.advance(frames);
            eqQ_.advance(frames);
        }
        updateEQCoefficients();
    }

    void updateEQCoefficients() noexcept {
        const auto coeffs = makeEQCoefficients(eqShape_, std::exp(eqLogFrequency_.current()),
                                               eqGainDB_.current(), eqQ_.current(), sampleRate_);
        for (auto& filter : eq_) filter.setCoefficients(coeffs);
        eqDirty_ = false;
    }

    std::array<std::atomic<float>, EC_PARAMETER_COUNT> parameters_{};
    std::atomic<bool> bypassed_{false};
    std::atomic<float> gainReductionMeter_{0.0f};
    PeakMeter inputMeter_;
    PeakMeter outputMeter_;

    double sampleRate_ = 48000.0;
    int channelCount_ = 2;

    Compressor compressor_;
    std::array<Biquad, kMaxChannels> eq_{};
    std::array<WarmthGenerator, kMaxChannels> warmth_{};
    EQShape eqShape_ = EQShape::bell;
    bool eqDirty_ = true;
    float cachedAttack_ = -1.0f;
    float cachedRelease_ = -1.0f;

    Smoothed naturalGain_, exciteGain_, outputGain_, listenMix_, warmthGain_, warmthListenMix_;
    Smoothed makeupDB_;
    Smoothed eqLogFrequency_, eqGainDB_, eqQ_;
};

} // namespace ec
