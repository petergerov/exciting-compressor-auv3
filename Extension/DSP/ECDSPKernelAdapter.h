#pragma once

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Linear peak |sample| per side. Mono input reports the same value on both.
typedef struct ECStereoPeak {
    float left;
    float right;
} ECStereoPeak;

/// Objective-C facade over the C++ `ec::ExcitingCompressorDSP` kernel.
/// Owns the busses and hands out a render block that touches only C++ state.
@interface ECDSPKernelAdapter : NSObject

@property (nonatomic, readonly) AUAudioUnitBus *inputBus;
@property (nonatomic, readonly) AUAudioUnitBus *outputBus;

/// Current excite-path gain reduction, positive dB. Safe to poll from any thread.
@property (nonatomic, readonly) float gainReductionDB;

/// Highest input / output peak since the previous call, then cleared. Safe to
/// call from any thread; meant for a single reader (the editor's meter loop).
- (ECStereoPeak)takeInputPeak NS_SWIFT_NAME(takeInputPeak());
- (ECStereoPeak)takeOutputPeak NS_SWIFT_NAME(takeOutputPeak());

@property (nonatomic, getter=isBypassed) BOOL bypassed;

- (void)setValue:(AUValue)value forAddress:(AUParameterAddress)address
    NS_SWIFT_NAME(setValue(_:forAddress:));
- (AUValue)valueForAddress:(AUParameterAddress)address
    NS_SWIFT_NAME(value(forAddress:));

- (BOOL)allocateRenderResourcesWithMaximumFrames:(AUAudioFrameCount)maximumFrames
                                           error:(NSError **)error
    NS_SWIFT_NAME(allocateRenderResources(maximumFrames:));
- (void)deallocateRenderResources;

- (AUInternalRenderBlock)internalRenderBlock;

@end

NS_ASSUME_NONNULL_END
