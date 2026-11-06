#import "ECDSPKernelAdapter.h"

#include <algorithm>
#include <array>

#include "ExcitingCompressorDSP.hpp"

namespace {

/// Owns the buffer the upstream node renders into when we pull input.
struct InputBuffer {
    AVAudioPCMBuffer *pcmBuffer = nil;
    const AudioBufferList *originalList = nullptr;
    AudioBufferList *mutableList = nullptr;

    void allocate(AVAudioFormat *format, AUAudioFrameCount maximumFrames) {
        pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:maximumFrames];
        originalList = pcmBuffer.audioBufferList;
        mutableList = pcmBuffer.mutableAudioBufferList;
    }

    void deallocate() {
        pcmBuffer = nil;
        originalList = nullptr;
        mutableList = nullptr;
    }

    /// Hosts may repoint mData during a pull; restore our own buffers first.
    AUAudioUnitStatus pull(AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp,
                           AUAudioFrameCount frameCount, AURenderPullInputBlock pullInput) {
        const UInt32 byteSize = frameCount * sizeof(float);
        for (UInt32 i = 0; i < mutableList->mNumberBuffers; ++i) {
            mutableList->mBuffers[i].mNumberChannels = originalList->mBuffers[i].mNumberChannels;
            mutableList->mBuffers[i].mData = originalList->mBuffers[i].mData;
            mutableList->mBuffers[i].mDataByteSize = byteSize;
        }
        return pullInput(flags, timestamp, frameCount, 0, mutableList);
    }
};

/// Splits the buffer at parameter-event boundaries for sample-accurate automation.
void renderWithEvents(ec::ExcitingCompressorDSP &dsp, const AudioTimeStamp *timestamp,
                      AUAudioFrameCount frameCount, const AURenderEvent *event,
                      const AudioBufferList *input, AudioBufferList *output) {
    constexpr int kMaxChannels = ec::ExcitingCompressorDSP::kMaxChannels;
    const int channelCount = static_cast<int>(
        std::min({input->mNumberBuffers, output->mNumberBuffers, static_cast<UInt32>(kMaxChannels)}));

    std::array<const float *, kMaxChannels> in{};
    std::array<float *, kMaxChannels> out{};

    AUEventSampleTime now = static_cast<AUEventSampleTime>(timestamp->mSampleTime);
    AUAudioFrameCount offset = 0;
    AUAudioFrameCount remaining = frameCount;

    auto renderSegment = [&](AUAudioFrameCount frames) {
        for (int ch = 0; ch < channelCount; ++ch) {
            in[ch] = static_cast<const float *>(input->mBuffers[ch].mData) + offset;
            out[ch] = static_cast<float *>(output->mBuffers[ch].mData) + offset;
        }
        dsp.process(in.data(), out.data(), channelCount, static_cast<int>(frames));
        offset += frames;
        remaining -= frames;
        now += frames;
    };

    while (remaining > 0) {
        if (event == nullptr) {
            renderSegment(remaining);
            break;
        }

        const AUEventSampleTime untilEvent = std::max<AUEventSampleTime>(0, event->head.eventSampleTime - now);
        const auto frames = static_cast<AUAudioFrameCount>(
            std::min<AUEventSampleTime>(untilEvent, remaining));
        if (frames > 0) renderSegment(frames);

        while (event != nullptr && event->head.eventSampleTime <= now) {
            switch (event->head.eventType) {
                case AURenderEventParameter:
                case AURenderEventParameterRamp:
                    // Ramps jump to their end value; the kernel's smoothers de-zipper.
                    dsp.setParameter(event->parameter.parameterAddress, event->parameter.value);
                    break;
                default:
                    break;
            }
            event = event->head.next;
        }
    }
}

} // namespace

@implementation ECDSPKernelAdapter {
    ec::ExcitingCompressorDSP _dsp;
    InputBuffer _input;
    AUAudioFrameCount _maximumFrames;
}

- (instancetype)init {
    if ((self = [super init])) {
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000.0 channels:2];
        _inputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:nil];
        _outputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:nil];
        _inputBus.maximumChannelCount = 2; // matches channelCapabilities [1,1, 2,2]
        _outputBus.maximumChannelCount = 2;
        _maximumFrames = 0;
    }
    return self;
}

- (float)gainReductionDB {
    return _dsp.gainReduction();
}

- (ECStereoPeak)takeInputPeak {
    ECStereoPeak peak{};
    _dsp.takeInputPeak(peak.left, peak.right);
    return peak;
}

- (ECStereoPeak)takeOutputPeak {
    ECStereoPeak peak{};
    _dsp.takeOutputPeak(peak.left, peak.right);
    return peak;
}

- (BOOL)isBypassed {
    return _dsp.isBypassed();
}

- (void)setBypassed:(BOOL)bypassed {
    _dsp.setBypassed(bypassed);
}

- (void)setValue:(AUValue)value forAddress:(AUParameterAddress)address {
    _dsp.setParameter(address, value);
}

- (AUValue)valueForAddress:(AUParameterAddress)address {
    return _dsp.parameter(address);
}

- (BOOL)allocateRenderResourcesWithMaximumFrames:(AUAudioFrameCount)maximumFrames error:(NSError **)error {
    AVAudioFormat *inputFormat = _inputBus.format;
    AVAudioFormat *outputFormat = _outputBus.format;

    if (inputFormat.channelCount != outputFormat.channelCount ||
        inputFormat.sampleRate != outputFormat.sampleRate) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:kAudioUnitErr_FormatNotSupported
                                     userInfo:@{NSLocalizedDescriptionKey : @"Input and output formats must match."}];
        }
        return NO;
    }

    _maximumFrames = maximumFrames;
    _input.allocate(inputFormat, maximumFrames);
    _dsp.prepare(outputFormat.sampleRate, static_cast<int>(outputFormat.channelCount));
    return YES;
}

- (void)deallocateRenderResources {
    _input.deallocate();
    _maximumFrames = 0;
}

- (AUInternalRenderBlock)internalRenderBlock {
    // Capture raw C++ pointers only: no Objective-C messaging on the render thread.
    ec::ExcitingCompressorDSP *dsp = &_dsp;
    InputBuffer *input = &_input;
    AUAudioFrameCount *maximumFrames = &_maximumFrames;

    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *timestamp,
                              AUAudioFrameCount frameCount, NSInteger outputBusNumber,
                              AudioBufferList *outputData, const AURenderEvent *realtimeEventListHead,
                              AURenderPullInputBlock pullInputBlock) {
        (void)outputBusNumber;

        if (frameCount > *maximumFrames) return kAudioUnitErr_TooManyFramesToProcess;
        if (pullInputBlock == nullptr || input->mutableList == nullptr) return kAudioUnitErr_NoConnection;

        AudioUnitRenderActionFlags pullFlags = 0;
        const AUAudioUnitStatus status = input->pull(&pullFlags, timestamp, frameCount, pullInputBlock);
        if (status != noErr) return status;

        AudioBufferList *inputList = input->mutableList;

        // Host passed null output buffers: render in place into our input buffers.
        if (outputData->mBuffers[0].mData == nullptr) {
            for (UInt32 i = 0; i < outputData->mNumberBuffers; ++i) {
                outputData->mBuffers[i].mData = inputList->mBuffers[i].mData;
            }
        }
        for (UInt32 i = 0; i < outputData->mNumberBuffers; ++i) {
            outputData->mBuffers[i].mDataByteSize = frameCount * sizeof(float);
        }

        renderWithEvents(*dsp, timestamp, frameCount, realtimeEventListHead, inputList, outputData);
        (void)actionFlags;
        return noErr;
    };
}

@end
