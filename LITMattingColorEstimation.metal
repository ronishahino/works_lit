// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITMattingColorEstimation.metal.h"

#import <metal_stdlib>

using namespace metal;

constexpr sampler normalizedNearestSampler(coord::normalized, address::clamp_to_zero,
                                           filter::nearest);

kernel void nearestNeighborResize(
    texture2d<half, access::sample> inputTexture [[texture(TextureIndex::ResizeSource)]],
    texture2d<half, access::write> outputTexture [[texture(TextureIndex::ResizeDestination)]],
    uint2 gridIndex [[thread_position_in_grid]]) {
  uint2 gridSize = uint2(outputTexture.get_width(), outputTexture.get_height());
  if (any(gridIndex >= gridSize)) {
    return;
  }

  if(is_null_texture(inputTexture)) {
    outputTexture.write(half4(0), gridIndex);
  } else {
    auto pixelPosition = (float2(gridIndex) + 0.5) / float2(gridSize);
    half4 value = inputTexture.sample(normalizedNearestSampler, pixelPosition);
    outputTexture.write(value, gridIndex);
  }
}

constexpr sampler nearestSampler(coord::pixel, address::clamp_to_edge, filter::nearest);

kernel void foregroundAndBackgroundUpdateStep(
    texture2d<half, access::read> image [[texture(TextureIndex::Image)]],
    texture2d<half, access::sample> alpha [[texture(TextureIndex::Alpha)]],
    texture2d<half, access::sample> inForeground [[texture(TextureIndex::InputForeground)]],
    texture2d<half, access::sample> inBackground [[texture(TextureIndex::InputBackground)]],
    texture2d<half, access::write> outForeground [[texture(TextureIndex::OutputForeground)]],
    texture2d<half, access::write> outBackground [[texture(TextureIndex::OutputBackground)]],
    uint2 gridIndex [[thread_position_in_grid]]) {
  const uint2 size = uint2(image.get_width(), image.get_height());
  if (any(gridIndex >= size)) {
    return;
  }

  float a = alpha.read(gridIndex).r;
  float a00 = a * a;
  float a01 = a * (1 - a);
  float a11 = (1 - a) * (1 - a);

  float3 imageVal = float3(image.read(gridIndex).rgb);
  float3 b0 = a * imageVal;
  float3 b1 = (1 - a) * imageVal;

  constexpr float4 neighborX = float4(-1, 1, 0, 0);
  constexpr float4 neighborY = float4(0, 0, -1, 1);
  constexpr float kRegularization = 1e-05;

  for (int i = 0; i < 4; i++) {
    float2 neighborPosition = float2(float(gridIndex[0]) + neighborX[i],
                                     float(gridIndex[1]) + neighborY[i]);

    float neighborAlpha = alpha.sample(nearestSampler, neighborPosition).r;
    float3 neighborForeground = float3(inForeground.sample(nearestSampler, neighborPosition).rgb);
    float3 neighborBackground = float3(inBackground.sample(nearestSampler, neighborPosition).rgb);
    float da = kRegularization + abs(a - neighborAlpha);
    a00 += da;
    a11 += da;
    b0 += da * neighborForeground;
    b1 += da * neighborBackground;
  }

  float det = a00 * a11 - a01 * a01;

  if (!is_null_texture(outForeground)) {
    float3 f = (a11 * b0 - a01 * b1) * 1.0 / det;
    f = saturate(f);
    outForeground.write(half4(half3(f), 1), gridIndex);
  }
  if (!is_null_texture(outBackground)) {
    float3 b = (a00 * b1 - a01 * b0) * 1.0 / det;
    b = saturate(b);
    outBackground.write(half4(half3(b), 1), gridIndex);
  }
}
