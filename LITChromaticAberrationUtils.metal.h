// Copyright (c) 2022 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import <metal_stdlib>

using namespace metal;

namespace lit_chromatic_aberration {

/// Struct stores parameters for operating Chromatic Aberration for texture on the fly.
template <typename T, typename SamplingParameters>
struct Descriptor {
  typedef vec<T, 4> (*SamplingOperation)(float2, SamplingParameters);

  /// Operation calculates pixels in texture that uses as input to Chromatic Aberration.
  SamplingOperation operation;
  /// Parameters used in \c operation
  SamplingParameters parameters;
};

/// Operates Chromatic Aberration with \c dispersionDistance for \c coord.
/// \c descriptor defines the calculations of the source texture on the fly.
template <typename T, typename SamplingParameters>
vec<T, 4> sample(float2 coord, simd_float3 dispersionDistance,
                 Descriptor<T, SamplingParameters> descriptor) {
  auto shiftR = float2(dispersionDistance.z, -dispersionDistance.x);
  auto shiftG = float2(dispersionDistance.y, -dispersionDistance.z);
  auto shiftB = float2(dispersionDistance.x, -dispersionDistance.y);
  return {
    descriptor.operation(coord + shiftR, descriptor.parameters).r,
    descriptor.operation(coord + shiftG, descriptor.parameters).g,
    descriptor.operation(coord + shiftB, descriptor.parameters).b,
    1
  };
}

} // namespace lit_chromatic_aberration
