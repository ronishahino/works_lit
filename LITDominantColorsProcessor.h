// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColor.h"
#import "LITDominantColorRepresentativePercentileParams.h"

NS_ASSUME_NONNULL_BEGIN

/// Structure that stores configuration parameters for LITDominantColorProcessor.
typedef struct {
  /// Numbers of bins to split the histogram in hue fields when performing DBScan.
  /// This value controls the amount of different shades a cluster can contain.
  /// Too large value can allow a greater range of colors to cluster together and thus lose the
  /// colors diversity. while too small value causes small clusters that don't contain enough
  /// shades of the dominant color, and may look like noise.
  /// This parameter gets values in range [1, 180].
  /// @note that hue field range is [0, 180], namely bin width in hue field will be
  /// 180 \ \c numOfBinsInHField.
  unsigned int numOfBinsInHField;

  /// Numbers of bins to split the histogram in saturation fields when performing DBScan.
  /// This value controls the amount of different saturations a cluster can contain.
  /// The explanation of the previous value(\c numOfBinsInHField) is also relevant for this value
  /// except that this value controls the saturation range not the shades range.
  /// This parameter gets values in range [1, 256].
  unsigned int numOfBinsInSField;

  /// Minimun euclidean distance in LUV space between any two dominant colors.
  float luvMinDistance;

  /// Pixel with saturation smaller than this value are ignored.
  /// This parameter gets values in range [0, 1].
  float minimalSaturation;

  /// Pixel with value (the V channel of HSV) smaller than this value are ignored.
  /// This parameter gets values in range [0, 1].
  float minimalValue;

  /// Maximum bins to extract dominant colors from. This value must be smaller than
  /// \c numOfBinsInHField * \c numOfBinsInSField.
  unsigned int maxBinsToIterate;

  /// Parameters define how to extract a representative from a bin.
  LITDominantColorRepresentativePercentileParams representativePercentileParams;

  /// Bins priority determined by total size of pixels in the bin. This value is designed to
  /// prioritize saturated values, by raising their priority in percents according to saturation
  /// intensity of the bin factored by \c saturatedPriorityFactor.
  /// The higher the \c saturatedPriorityFactor, the higher the priority tends to saturated values.
  float saturatedPriorityFactor;

  /// Maximum dominant colors taken from the same bin.
  int maxDominantColorsPerBin;
} LITDominantColorsConfiguration;

#ifdef __cplusplus
extern "C" {
#endif

/// Creates default configuration.
LITDominantColorsConfiguration LITDominantColorsConfigurationDefault(void);

#ifdef __cplusplus
} // extern "C"
#endif

/// Class for finding dominant color in the given image.
///
/// Algorithm steps:
///
/// 1. Image preprocessing -> reduce resolution + bilateral filter + convert to HSV color space.
/// 2. Divide the color range of H and S channels into bins. (the V channel isn't divided, namely
///    each bin contain the whole V channel range).
/// 3. Sort the bins by number of image pixels in the bin.
/// 4. For each bin:
///    4.1. Perform DBScan to detect pixel clusters.
///    4.2. Choose a representative for each cluster.
///    4.3. Calculate scores for representative as the percent of colors in the image that are
///         close in LUV color space to the representative.
///    4.4. Sort representatives by score.
///    4.5. Add representative as a dominant color only if it's not close to another dominant color
///         that already exist.
///
/// @note input texture must have a pixel format of \c MTLPixelFormatRGBA8Unorm or
/// \c MTLPixelFormatBGRA8Unorm.
@interface LITDominantColorsProcessor : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Initializes the processor with device and configuration
///
/// @param device device to create the required GPU processors.
///
/// @param dominantColorsConfiguration configuration parameters.
///
/// @note initialization is a heavy operation relatively
/// to \c findDominanColorsInImage:commandQueue:. it is recommended to create one instance of
/// \c LITDominantColorsProcessor during the whole application life time for better run time
/// performance.
- (instancetype)initWithDevice:(id<MTLDevice>)device
                 configuration:(LITDominantColorsConfiguration)dominantColorsConfiguration
  NS_DESIGNATED_INITIALIZER;

/// Finds dominant colors in image.
///
/// @param texture input image. Must have 4 channels of type uchar.
///
/// @param maxWorkingResolution maximum resolution of image to process. Larger images are resized so
/// that their largest dimension equals this value.
///
/// @param bilateralFilterRangeSigma range sigma passed to \c LITBilateralFilterProcessor in
/// preprocessing step.
///
/// @param commandQueue command queue on which to perform the preprocessing calculation.
///
/// @param error output error if an error occurs.
///
- (nullable NSArray<LITDominantColor*> *)findDominantColorsInImage:(id<MTLTexture>)texture
    maxWorkingResolution:(unsigned int)maxWorkingResolution
    bilateralFilterRangeSigma:(float)bilateralFilterRangeSigma
    commandQueue:(id<MTLCommandQueue>)commandQueue error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
