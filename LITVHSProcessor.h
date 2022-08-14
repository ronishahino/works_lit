// Copyright (c) 2022 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITQuad.h"

NS_ASSUME_NONNULL_BEGIN

/// Class for generating VHS and Sharpen effect, with the following steps:
///
/// Sharpen:
/// 1. Create high-pass mask for input texture.
/// 2. Merge input texture and high-pass mask.
///
/// VHS:
/// 1. Blur input texture (by downsampling). (Blurring is done by downsampling).
/// 2. Create high-pass mask for the blurred texture.
/// 3. Merge blurred texture and high-pass mask.
/// 4. Add tiny Chromatic Aberration.
@interface LITVHSProcessor : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Initializes with \c device and \c pixelFormat as the format of the output textures.
- (instancetype)initWithDevice:(id<MTLDevice>)device pixelFormat:(MTLPixelFormat)pixelFormat;

/// Encodes a VHS effect into the fragment of \c outputTexture defined by \c quad.
/// @param commandBuffer command buffer to store the encoded command.
/// @param inputTexture texture on which the effect should be applied.
/// @param outputTexture texture to store the effect results.
/// @param quad quad on which the vhs should be applied, represented in non-normalized texture
/// coordinates. Coordinates outside this quad are copied
/// without changes.
/// @param sharpenIntensity sharpen effect intensity, must be in <tt>[0, 1]</tt> range.
/// @param vhsIntensity vhs effect intensity, must be in <tt>[0, 1]</tt> range.
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                 inputTexture:(id<MTLTexture>)inputTexture
                outputTexture:(id<MTLTexture>)outputTexture
                         quad:(LITQuad)quad
             sharpenIntensity:(CGFloat)sharpenIntensity
                 vhsIntensity:(CGFloat)vhsIntensity;

/// Encodes a VHS effect on the entire texture.
/// @param commandBuffer command buffer to store the encoded command.
/// @param inputTexture texture on which the effect should be applied.
/// @param outputTexture texture to store the effect results.
/// @param sharpenIntensity sharpen effect intensity, must be in <tt>[0, 1]</tt> range.
/// @param vhsIntensity vhs effect intensity, must be in <tt>[0, 1]</tt> range.
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                 inputTexture:(id<MTLTexture>)inputTexture
                outputTexture:(id<MTLTexture>)outputTexture
             sharpenIntensity:(CGFloat)sharpenIntensity
                 vhsIntensity:(CGFloat)vhsIntensity;
@end

NS_ASSUME_NONNULL_END
