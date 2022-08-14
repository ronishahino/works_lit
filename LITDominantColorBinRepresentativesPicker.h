// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorHSBinIndex.h"
#import "LITDominantColorRepresentativePercentileParams.h"

NS_ASSUME_NONNULL_BEGIN

/// Structure that stores configuration parameters for LITDominantColorBinRepresentativesPicker.
struct LITDominantColorRepresentativesPickerConfiguration {
  /// DBScan radius parameter, which define two points as neighbors iff their distance is smaller
  /// than or equal to this value.
  /// This parameter must be positive.
  float dbScanRadius;

  /// DBScan min neighbors parameter.
  /// A point is a core point if it has more than \c dbScanMinNeighbors points within
  /// \c dbScanRadius around it — These are points that are at the interior of a cluster.
  /// A border point has fewer than \c dbScanMinNeighbors within \c dbScanRadius, but is in
  /// the neighborhood of a core point.
  /// A noise point is any point that is not a core point nor a border point.
  /// larger value assures a more robust cluster but may exclude some potentially shades.
  /// On the other hand, a smaller value extracts many clusters, but the resultant clusters may
  /// include noise as well.
  /// Default value is 30.
  unsigned int dbScanMinNeighbors;

  /// Multiply every point in histogram by this value when computing distance between points.
  /// This parameter streches HSV color space in each axis by the appropriate value in
  /// \c dbScanPointMultipliers.
  /// Larger value mean more stretched axis, so that the radius of neigbors will include less
  /// neighbors, and clusters will be with less diversity in this axis.
  float dbScanPointMultipliers[3];
};

/// Object used internally by the dominant colors processor to pick representative colors given a
/// bin in a histogram. It uses DBSCAN to cluster entries in the bin and pick representative from
/// each cluster.
@interface LITDominantColorBinRepresentativesPicker : NSObject

- (instancetype)init NS_UNAVAILABLE;
/// Initializes \c LITDominantColorBinRepresentativesPicker.
///
/// @param binHueWidth bin width in hue filed.
///
/// @param binSaturationWidth bin width in sasturation filed.
///
/// @param representativePercentileParams parameters define how to extract a representative from a
/// bin.
///
/// @param configuration configuration parameters.
///
- (instancetype)initWithBinHueWidth:(int)binHueWidth binSaturationWidth:(int)binSaturationWidth
     representativePercentileParams:
    (LITDominantColorRepresentativePercentileParams)representativePercentileParams
  representativePickerConfiguration:
    (LITDominantColorRepresentativesPickerConfiguration)representativePickerConfiguration
    NS_DESIGNATED_INITIALIZER;

/// Detect clusters in the bin and returns a list of representative colors of the cluster.
///
/// @param bin image bin to extract representatives from.
///
/// @param hsBinIndex the bin index.
///
/// @param histogram 3D histogram of the image.
///
- (std::vector<cv::Vec3b>)findRepresentativeColorsInBin:(const std::vector<cv::Vec3b> &)bin
                                              withIndex:(LITHSBinIndex)hsBinIndex
                                              histogram:(const cv::Mat1f &)histogram;
@end

NS_ASSUME_NONNULL_END
