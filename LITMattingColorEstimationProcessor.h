// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

NS_ASSUME_NONNULL_BEGIN

/// Structure that stores configuration parameters for LITMattingColorEstimationProcessor.
typedef struct {
  /// Number of iterations performed on small scale pyramid levels.
  int numberOfIterationsForSmallScales;

  /// Number of iterations performed on large scale pyramid levels.
  int numberOfIterationsForLargeScales;

  /// Threshold that determines the maximum size at which \c numberOfIterationsForSmallPyramidLevels
  /// should be used.
  int smallScalesThreshold;
} LITMattingColorEstimationProcessorConfiguration;

LT_C_DECLS_BEGIN

/// Creates default configuration.
LITMattingColorEstimationProcessorConfiguration
    LITMattingColorEstimationProcessorConfigurationDefault(void);

LT_C_DECLS_END

/// Processor estimating the colors of background and foreground objects given a combined image and
/// alpha.
/// This processor can be used to blend a new foreground onto the background, or replace the
/// background while keeping the foreground etc.
///
/// The algorithm is implemented here:
///https://github.com/pymatting/pymatting/blob/master/pymatting/foreground/estimate_foreground_ml.py
@interface LITMattingColorEstimationProcessor : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Initializes a new processor that runs on \c device.
- (instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;

/// Encodes the operation to compute foreground and background images.
/// @note Either \c destinationForeground or \c destinationBackground may be null if only the other
/// is required.
///
/// @param sourceTexture the input image. Must have 4 channels of type uchar.
///
/// @param alpha the input alpha matte that defines the foreground object in the image.
/// Must have 1 channel of type uchar and the same size as \c inputImage.
///
/// @param destinationForeground output foreground image. Must have 4 channels of type uchar and the
/// same size as \c inputImage.
///
/// @param destinationBackground output background image. Must have 4 channels of type uchar and the
/// same size as \c inputImage.
///
/// @param configuration configuration parameters.
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)sourceTexture alpha:(id<MTLTexture>)alpha
        destinationForeground:(nullable id<MTLTexture>)destinationForeground
        destinationBackground:(nullable id<MTLTexture>)destinationBackground
                configuration:(LITMattingColorEstimationProcessorConfiguration)configuration;

/// Encodes the operation to compute foreground and background images with default configuration.
/// @note Either \c destinationForeground or \c destinationBackground may be null if only the other
/// is required.
///
/// @param sourceTexture the input image. Must have 4 channels of type uchar.
///
/// @param alpha the input alpha matte that defines the foreground object in the image.
/// Must have 1 channel of type uchar and the same size as \c inputImage.
///
/// @param destinationForeground output foreground image. Must have 4 channels of type uchar and the
/// same size as \c inputImage.
///
/// @param destinationBackground output background image. Must have 4 channels of type uchar and the
/// same size as \c inputImage.
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)sourceTexture alpha:(id<MTLTexture>)alpha
        destinationForeground:(nullable id<MTLTexture>)destinationForeground
        destinationBackground:(nullable id<MTLTexture>)destinationBackground;
@end

NS_ASSUME_NONNULL_END
