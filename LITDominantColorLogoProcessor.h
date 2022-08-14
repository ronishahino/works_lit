// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColor.h"
#import "LITDominantColorRepresentativePercentileParams.h"

NS_ASSUME_NONNULL_BEGIN

/// Structure that stores configuration parameters for LITDominantColorLogoProcessor.
typedef struct {

  /// Numbers of bins to split the hue fields, where a dominant color is extracted from each bin.
  /// This value controls the shades diversity of the dominant colors.
  /// Too large value will affect bins with small range of colors, and thus the dominant
  /// colors will have very similar color shades. while too small value causes big bins contain too
  /// large range of shades and may look like noise.
  /// This parameter gets values in range [1, 180].
  /// @note that hue field range is [0, 180], namely bin width in hue field will be
  /// 180 \ \c numOfBinsInHField.
  unsigned int numOfBinsInHField;

  /// Numbers of bins to split the saturation fields.
  /// This value controls the saturation diversity of the dominant colors.
  /// The explanation of the previous value(\c numOfBinsInHField) is also relevant for this value
  /// except that this value controls the saturation range not the shades range.
  /// This parameter gets values in range [1, 256].
  unsigned int numOfBinsInSField;

  /// Numbers of bins to split the value fields.
  /// This value controls the brightness diversity of the dominant colors.
  /// The explanation of the previous value(\c numOfBinsInHField) is also relevant for this value
  /// except that this value controls the brightness range not the shades range.
  /// This parameter gets values in range [1, 256].
  unsigned int numOfBinsInVField;

  /// Numbers of bins to split the gray range.
  /// The explanation of the previous value(\c numOfBinsInHField) is also relevant for this value
  /// except that this value controls only the gray range not the color range.
  /// This parameter gets values in range [1, 256].
  unsigned int numOfGrayBins;

  /// Bins with pixels size in percent smaller than this value are ignored. The pixels percent is
  /// measures according to the total foreground pixels in the image.
  /// This parameter gets values in range [0, 100].
  float minBinSizePercent;

  /// The initial threshold of euclidean distance in LUV space between any two dominant colors.
  /// This parameter must be positive.
  float initialMinLUVDistance;

  /// The increasing rate of LUV distance between any two dominant colors, as the dominance
  /// decreases.
  /// The greater the value, the greater the differences between the dominant colors as their
  /// dominance decreases. When \c minLUVDistanceIncreaseRate is zero, the LUV threshold is constant
  /// and equals \c initialMinLUVDistance.
  /// This parameter must be positive.
  float minLUVDistanceIncreaseRate;

  /// Parameters define how to extract a representative from a bin.
  LITDominantColorRepresentativePercentileParams representativePercentileParams;

} LITDominantColorsLogoConfiguration;

LT_C_DECLS_BEGIN

/// Creates default configuration.
LITDominantColorsLogoConfiguration LITDominantColorsLogoConfigurationDefault(void);

LT_C_DECLS_END

/// Class for finding dominant color, designed for logo images.
/// The background color is removed from the returned dominant color list.
///
/// Algorithm steps:
///
/// 1. Image preprocessing -> reduce resolution + remove alpha channel + convert to HSV color space.
/// 2. Detect foreground pixels in the image (the logo itself without the background).
/// 2. Divide the color range of H, S, V channels, and the gray range into bins.
/// 3. For each bin:
///    3.1. Declare a mask indicates the bin pixels, and perform erosion of this mask.
///    3.3. Extract representative only from the bin pixels that appears in the eroded mask.
///    3.3. Calculate scores for representative as the percent of pixels in the bin related to the
///         total foreground pixels in the image.
/// 4. Sort representatives by score.
/// 5. Add representative as a dominant color only if it's not close in LUV color space to another
///    dominant color that already exist.
///
/// @note input texture must have a pixel format of \c MTLPixelFormatRGBA8Unorm or
/// \c MTLPixelFormatBGRA8Unorm.
@interface LITDominantColorLogoProcessor : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Initializes the processor with \c configuration.
- (instancetype)initWithConfiguration:(LITDominantColorsLogoConfiguration)configuration;

/// Finds dominant colors in logo image.
///
/// @param texture input image.
///
/// @param maxWorkingResolution maximum resolution of image to process. Larger images are resized so
/// that their largest dimension equals this value.
/// @note This parameter has a direct effect on the runtime of this operation.
- (NSArray<LITDominantColor*> *)dominantColorsInImage:(id<MTLTexture>)texture
                                 maxWorkingResolution:(int)maxWorkingResolution;

@end

NS_ASSUME_NONNULL_END
