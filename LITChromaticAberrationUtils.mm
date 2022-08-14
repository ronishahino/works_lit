// Copyright (c) 2022 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITChromaticAberrationUtils.h"

NS_ASSUME_NONNULL_BEGIN

static float LITRand(float x) {
  return simd::fract(sin(x) * 39567.8731);
}

simd_float3 LITDispersionDistance(float intensity, float vibration, float normalizedTime) {
  auto amplitude = pow(intensity, 1.5) * 0.1;
  auto speed = pow(vibration, 4) * 0.1;
  simd_float3 dispersionDistance = simd_make_float3(LITRand(speed * normalizedTime),
                                                    LITRand(speed * normalizedTime + 1),
                                                    LITRand(speed * normalizedTime + 2));
  dispersionDistance.x = amplitude * pow(dispersionDistance.x, 10);
  dispersionDistance.y = amplitude * pow(dispersionDistance.y, 10);
  dispersionDistance.z = amplitude * pow(dispersionDistance.z, 10);
  return dispersionDistance;
}

NS_ASSUME_NONNULL_END
