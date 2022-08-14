// Copyright (c) 2022 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITVHSProcessor.metal.h"

#import "LITChromaticAberrationUtils.metal.h"
#import "LITHomogeneousCoordinates.metal.h"
#import "LITMetalUtils.metal.h"
#import "LITPassthroughVertex.metal.h"

/// Sampler that uses linear filter.
constexpr sampler linearSampler(filter::linear, address::mirrored_repeat);

/// Struct stores parameters needed for \c LITVHSOperation.
struct LITVHSParameters {
  /// The Source texture.
  texture2d<half> sourceTexture;
  /// Blurred \c sourceTexture.
  texture2d<half> blurredTexture;
  /// Coarse gaussian texture of \c blurredTexture with gaussian radius match to sharpen effect.
  texture2d<half> coarseGaussianTextureSharpen;
  /// Coarse gaussian texture of \c blurredTexture with gaussian radius match to vhs effect.
  texture2d<half> coarseGaussianTextureVHS;
  /// Intensity of required sharpen.
  float sharpenIntensity;
  /// VHS parameters
  VHSParameters vhsParameters;
};

/// Performs sharpen effect for a pixel position.
static half3 LITSharpen(half3 color, half3 coarseGaussian, float highPassIntensity) {
  const half kSharpenHighPassFactor = 1.8;
  return color + (color - coarseGaussian) * kSharpenHighPassFactor * highPassIntensity;
}

/// Performs vhs effect for a pixel position.
static half3 LITVHS(half3 color, half3 coarseGaussian,  half3 blur, float blurIntensity,
                    float highPassIntensity) {
  auto blurredColor = color * (1 - blurIntensity) + blur * blurIntensity;

  // add high-pass frequencies
  const half kVHSHighPassFactor = 3.6;
  return blurredColor + (blurredColor - coarseGaussian) * kVHSHighPassFactor * highPassIntensity;

}

/// Performs sharpen and vhs effects for a pixel position.
static half4 LITVHSOperation(float2 position, LITVHSParameters parameters) {
  auto source = parameters.sourceTexture.sample(linearSampler, position);

  half3 sharpen(0.);
  if (parameters.sharpenIntensity != 0) {
    auto coarseGaussianSharpen =
        parameters.coarseGaussianTextureSharpen.sample(linearSampler, position).rgb;
    sharpen = LITSharpen(source.rgb, coarseGaussianSharpen, parameters.sharpenIntensity);
  }

  half3 vhs(0.);
  if(parameters.vhsParameters.originalIntensity != 0) {
    auto blur = parameters.blurredTexture.sample(linearSampler, position).rgb;
    auto coarseGaussianVHS = parameters.coarseGaussianTextureVHS.sample(linearSampler,
                                                                        position).rgb;
    vhs = LITVHS(source.rgb, coarseGaussianVHS, blur,
                 parameters.vhsParameters.blurIntensity,
                 parameters.vhsParameters.highPassIntensity);
  }

  auto totalIntensities = parameters.sharpenIntensity + parameters.vhsParameters.originalIntensity;
  return half4(sharpen * (parameters.sharpenIntensity /  totalIntensities)
               + vhs * (parameters.vhsParameters.originalIntensity /  totalIntensities),
               source.a);
}

fragment half4 vhsFragmentShader(LITPassthroughVertexOut vin [[stage_in]],
    texture2d<half> sourceTexture [[texture(TextureIndex::SourceTexture)]],
    texture2d<half> blurredTexture [[texture(TextureIndex::BlurredTexture)]],
    texture2d<half> coarseGaussianTextureSharpen
                                 [[texture(TextureIndex::CoarseGaussianTextureSharpen)]],
    texture2d<half> coarseGaussianTextureVHS [[texture(TextureIndex::CoarseGaussianTextureVHS)]],
    constant float3x3 &quadToStandardSquare [[buffer(BufferIndex::QuadToStandardSquare)]],
    constant float &sharpenIntensity [[buffer(BufferIndex::SharpenIntensity)]],
    constant VHSParameters &vhsParams [[buffer(BufferIndex::VHSParams)]]) {
  float3 homogeneousCoordinate(vin.texCoord, 1.f);
  if (!belongsToQuad(homogeneousCoordinate, quadToStandardSquare)) {
    return sourceTexture.sample(linearSampler, vin.texCoord);
  }

  LITVHSParameters parameters {
    .sourceTexture = sourceTexture,
    .blurredTexture = blurredTexture,
    .coarseGaussianTextureSharpen = coarseGaussianTextureSharpen,
    .coarseGaussianTextureVHS = coarseGaussianTextureVHS,
    .sharpenIntensity = sharpenIntensity,
    .vhsParameters = vhsParams
  };

  if (vhsParams.originalIntensity == 0) {
    return LITVHSOperation(vin.texCoord, parameters);
  }

  lit_chromatic_aberration::Descriptor<half, LITVHSParameters> descriptor = {
    .operation = LITVHSOperation,
    .parameters = parameters
  };

  return lit_chromatic_aberration::sample(vin.texCoord, vhsParams.dispersionDistance, descriptor);
}
