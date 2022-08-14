// Copyright (c) 2022 Lightricks. All rights reserved.
// Created by Roni Shahino.

/// Textures used by fragment functions of VHS renderers.
enum TextureIndex {
  /// Source Texture
  SourceTexture,
  /// Blurred Texture
  BlurredTexture,
  /// Coarse Gaussian Texture for sharpen effect
  CoarseGaussianTextureSharpen,
  /// Coarse Gaussian Texture for vhs effect
  CoarseGaussianTextureVHS,
};

enum BufferIndex {
  /// Transformation between quad on which the vhs applied and standard square.
  QuadToStandardSquare,
  /// Intensity of sharpen effect.
  SharpenIntensity,
  /// Parameters of vhs.
  VHSParams,
};

struct VHSParameters {
  /// Original intensity.
  float originalIntensity;
  /// Blur intensity
  float blurIntensity;
  /// Intensity of HighPass filter.
  float highPassIntensity;
  /// \c dispersionDistance parameter for Chromatic Aberration.
  simd_float3 dispersionDistance;
};
