#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

// Single source of truth for parameter addresses. Plain C so it can be shared by
// the C++ DSP kernel and Swift (imported via the bridging header as
// `ECParameterAddress`, whose raw value is an `AUParameterAddress`).
typedef CF_ENUM(uint64_t, ECParameterAddress) {
    // Natural path (the "uncompressed console channel")
    ECParameterAddressNaturalLevel = 0,

    // Excite path (the "exciting compressor" channel)
    ECParameterAddressExciteLevel  = 1,
    ECParameterAddressThreshold    = 2,
    ECParameterAddressRatio        = 3,
    ECParameterAddressAttack       = 4,
    ECParameterAddressRelease      = 5,
    ECParameterAddressEqFrequency  = 6,
    ECParameterAddressEqGain       = 7,
    ECParameterAddressEqQ          = 8,
    ECParameterAddressEqShape      = 9,

    // Master
    ECParameterAddressOutputLevel  = 10,
    ECParameterAddressExciteListen = 11,

    // Excite path, added after 1.0. Addresses are never renumbered: hosts
    // store automation and state by address.
    ECParameterAddressWarmth       = 12,
    ECParameterAddressWarmthListen = 13,
};

#define EC_PARAMETER_COUNT 14
