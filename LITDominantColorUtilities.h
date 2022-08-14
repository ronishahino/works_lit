// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorRepresentativePercentileParams.h"

NS_ASSUME_NONNULL_BEGIN

namespace lit_dominant_color {

/// Structure stores dominant color value and score.
struct ScoredColor {
  /// Dominant color value.
  cv::Vec3b color;

  /// Dominant color score.
  float score;

  ScoredColor() {
  }

  ScoredColor(const cv::Vec3b &c, float s) {
    color = c;
    score = s;
  }
};

/// Filter \c scoredLUVDominantColorList by removing colors that are close in LUV color space to
/// another color that already exists in the list.
/// The luv distance threshold starts from \c initialMinLUVDistance, and increased in each element
/// in the list by \c minLUVDistanceIncreaseRate. So that in order to be selected as a dominant
/// color, the further elements in the list should be more unique in color, than the first elements
/// in the list.
/// The priority is for the color that appears earlier in the list.
std::vector<ScoredColor> filterDominantColors(
    const std::vector<ScoredColor> &scoredLUVDominantColorList, float initialMinLUVDistance,
    float minLUVDistanceIncreaseRate = 0);

/// Calculates representative from pixels slice \c sliceMat with \c representativePercentileParams.
/// \c repetitions indicates how many times each pixel value repeats in the data. So that element
/// \c i in \c sliceMat repeats \c repetitions[i] times. In case that \c repetitions is empty
/// each pixel appears 1 time.
/// \c sliceSize is and the total repetitions of all elements.
/// @note If \c repetitions is not empty, its size must be larger than or equal to number of
/// rows * cols in \c sliceMat. only the first \c mat.rows \c * \c mat.cols elements in
///  \c repetitions are considered. others are ignored.
cv::Vec3b representativeOfSlice(const cv::Mat3b &sliceMat, int sliceSize,
    LITDominantColorRepresentativePercentileParams representativePercentileParams,
    const std::vector<int> &repetitions = {});

/// Run a conversion from RGB to LUV with openCV for a single element matrix. Runs the conversion
/// for the first call in the lifetime of the application, does nothing for every subsequent call.
/// The first call to \c cv::cvtColor with \c COLOR_RGB2Luv is a heavy operation, so this function
/// is intended for use in the processor init to reduce the conversion time when calling to
/// the main processor function.
void performRGBToLUVConversionOnce();
} // lit_dominant_color_utiles

NS_ASSUME_NONNULL_END
