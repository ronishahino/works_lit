// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

NS_ASSUME_NONNULL_BEGIN

/// Object used internally by the dominant colors processor to preprocess the input image.
@interface LITDominantColorPreprocessor : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Initializes with \c device.
- (instancetype)initWithDevice:(id<MTLDevice>)device;

/// Encodes preprocessesing.
///
/// @param commandBuffer command buffer to encode operation on.
///
/// @param sourceTexture source texture to be preprocessed.
/// Must have 4 channels of type uchar.
///
/// @param destinationTexture destination texture to be filled once \c commandBuffer is committed.
/// Must have 4 channels of type uchar.
///
/// @param bilateralFilterRangeSigma range sigma passed to \c LITBilateralFilterProcessor in
/// preprocessing step.
///
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)sourceTexture
           destinationTexture:(id<MTLTexture>)destinationTexture
    bilateralFilterRangeSigma:(float)bilateralFilterRangeSigma;
@end

NS_ASSUME_NONNULL_END
