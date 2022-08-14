// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorUtilities.h"

NS_ASSUME_NONNULL_BEGIN

namespace lit_dominant_color {

static int percentileForMatrix(const cv::Mat1b &mat, float percentileValue, int totalSize,
                               const std::vector<int> &repetitions);

std::vector<ScoredColor> filterDominantColors(
    const std::vector<ScoredColor> &scoredLUVDominantColorList, float initialMinLUVDistance,
    float minLUVDistanceIncreaseRate) {
  std::vector<ScoredColor> filteredDominantColor;
  for (int i = 0; i < (int)scoredLUVDominantColorList.size(); i++) {
    bool foundSimilarColor = false;
    for (auto &dominantColor : filteredDominantColor) {
      auto euclideanDist = cv::norm(cv::Vec3i(scoredLUVDominantColorList[i].color) -
                                    cv::Vec3i(dominantColor.color), cv::NormTypes::NORM_L2);
      if (euclideanDist  <= initialMinLUVDistance + i * minLUVDistanceIncreaseRate ) {
        foundSimilarColor = true;
        break;
      }
    }
    if (!foundSimilarColor) {
      filteredDominantColor.push_back(scoredLUVDominantColorList[i]);
    }
  }
  return filteredDominantColor;
}

cv::Vec3b representativeOfSlice(const cv::Mat3b &sliceMat, int sliceSize,
    LITDominantColorRepresentativePercentileParams representativePercentileParams,
    const std::vector<int> &repetitions) {
  cv::Mat1b clusterColorsOneChannel = sliceMat.reshape(1, sliceMat.rows * sliceMat.cols);

  if (!repetitions.empty()) {
    LTParameterAssert(clusterColorsOneChannel.rows <= (int)repetitions.size(),
                      @"Expect matrix elements number smaller than or equal to repetitions size. "
                      "got %d mat elements, and %lu repetition size", clusterColorsOneChannel.rows,
                      repetitions.size());
  }

  auto H = percentileForMatrix(clusterColorsOneChannel.col(0),
                               representativePercentileParams.huePercentileRepresentative,
                               sliceSize, repetitions);
  auto S = percentileForMatrix(clusterColorsOneChannel.col(1),
                               representativePercentileParams.saturationPercentileRepresentative,
                               sliceSize, repetitions);
  auto V = percentileForMatrix(clusterColorsOneChannel.col(2),
                               representativePercentileParams.valuePercentileRepresentative,
                               sliceSize, repetitions);
  return cv::Vec3b(H, S, V);
}

static int percentileForMatrix(const cv::Mat1b &mat,  float percentileValue, int totalSize,
                               const std::vector<int> &repetitions) {
  /// This function calculates the \c percentileValue -th percentile of the 1 dimensional matrix
  /// \c mat.
  LTParameterAssert(mat.cols == 1, @"expect matrix with 1 column. got %d columns", mat.cols);

  cv::Mat1f cdf = cv::Mat1f::zeros(256, 1);

  for (int i = 0; i < totalSize; i++) {
    if (!repetitions.empty()) {
      cdf(mat(i,0)) += repetitions[i];
    } else {
      cdf(mat(i,0)) += 1;
    }
  }

  int percentile = -1;
  for (int i = 1; i < 256; i++){
    cdf(i) += cdf(i - 1);
    if (cdf(i) / totalSize >= percentileValue) {
      percentile = i;
      break;
    }
  }

  return percentile;
}

void performRGBToLUVConversionOnce() {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cv::Mat3b mat(cv::Vec3b(0, 0, 0));
    cv::cvtColor(mat, mat, cv::COLOR_RGB2Luv);
  });
}

} //namespace lit_dominant_color_utiles

NS_ASSUME_NONNULL_END
