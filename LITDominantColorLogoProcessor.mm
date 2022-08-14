// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorLogoProcessor.h"

#import "LITDominantColorUtilities.h"

using namespace lit_dominant_color;

NS_ASSUME_NONNULL_BEGIN

LITDominantColorsLogoConfiguration LITDominantColorsLogoConfigurationDefault(void) {
  return {
    .numOfBinsInHField = 17,
    .numOfBinsInSField = 8,
    .numOfBinsInVField = 2,
    .numOfGrayBins = 4,
    .minBinSizePercent = 1.0,
    .initialMinLUVDistance = 31,
    .minLUVDistanceIncreaseRate = 1,
    .representativePercentileParams = LITDominantColorRepresentativePercentileParamsMake(0.5, 0.6,
                                                                                         0.6)
  };
}

/// Structure stores data on image background.
struct LITBackgroundParams {
  /// Number of non-background pixels in the image.
  int numberOfForegroundPixels;
  /// The background color min range in RGB color space.
  cv::Scalar backgroundColorMinRange;
  /// The background color max range in RGB color space.
  cv::Scalar backgroundColorMaxRange;

  LITBackgroundParams(int numberOfForegroundPixelsValue, cv::Scalar backgroundColorMinRangeValue,
                      cv::Scalar backgroundColorMaxRangeValue) {
    numberOfForegroundPixels = numberOfForegroundPixelsValue;
    backgroundColorMinRange = backgroundColorMinRangeValue;
    backgroundColorMaxRange = backgroundColorMaxRangeValue;
  }
};

@interface LITDominantColorLogoProcessor ()

/// Configuration parameters.
@property (nonatomic, readonly) LITDominantColorsLogoConfiguration configuration;

@end

@implementation LITDominantColorLogoProcessor

- (instancetype)initWithConfiguration:(LITDominantColorsLogoConfiguration)configuration {
   if (self = [super init]) {
     [self validateConfiguration:configuration];
     _configuration = configuration;

     performRGBToLUVConversionOnce();
   }
  return self;
}

- (void)validateConfiguration:(LITDominantColorsLogoConfiguration)configuration {
  LTParameterAssert(configuration.numOfBinsInHField <= 180 && configuration.numOfBinsInHField >= 1,
                    @"numOfBinsInHField must be in range of [1, 180]");
  LTParameterAssert(configuration.numOfBinsInSField <= 256 && configuration.numOfBinsInSField >= 1,
                    @"numOfBinsInSField must be in range of [1, 256]");
  LTParameterAssert(configuration.numOfBinsInVField <= 256 && configuration.numOfBinsInVField >= 1,
                    @"numOfBinsInVField must be in range of [1, 256]");
  LTParameterAssert(configuration.numOfGrayBins <= 256 && configuration.numOfGrayBins >= 1,
                    @"numOfGrayBins must be in range of [1, 256]");

  LTParameterAssert(configuration.minBinSizePercent <= 100 && configuration.minBinSizePercent >= 0,
                    @"minBinSizePercent must be in range [0, 100]");
  LTParameterAssert(configuration.initialMinLUVDistance > 0,
                    @"initialMinLUVDistance must be positive");
  LTParameterAssert(configuration.minLUVDistanceIncreaseRate > 0, @"minLUVDistanceIncreaseRate must"
                    " be positive");
}

#pragma mark -
#pragma mark Processing
#pragma mark -

- (NSArray<LITDominantColor*> *)dominantColorsInImage:(id<MTLTexture>)texture
                                 maxWorkingResolution:(int)maxWorkingResolution {
  auto kValidPixelFormat = {MTLPixelFormatRGBA8Unorm, MTLPixelFormatBGRA8Unorm};
  [LITImageValidator validateTexture:texture forPixelFormats:kValidPixelFormat];

  __block cv::Mat3b preprocessedImage;
  [mtb(texture) mtb_mappedForReading:^(const cv::Mat &image) {
    preprocessedImage = [self resizedThreeChannelsImage:image
                                   maxWorkingResolution:maxWorkingResolution];
  }];

  auto hsv = [self hsvImage:preprocessedImage withPixelFormat:texture.pixelFormat];

  auto backgroundParams = [self backgroundParamsFromImage:preprocessedImage];
  if (backgroundParams.numberOfForegroundPixels == 0) {
    return [NSArray array];
  }

  std::vector<ScoredColor> dominantColors;
  [self extractDominantColorFromHSVImage:hsv
                     numForegroundPixels:backgroundParams.numberOfForegroundPixels
                  populateDominantColors:&dominantColors];

  [self convertDominantColorFromHSVToLUV:&dominantColors];
  [self removeBackgroundColorFromLUVDominantColors:&dominantColors
                              withBackgroundParams:backgroundParams];
  [self sortDominantColorsByScore:&dominantColors];
  auto filteredDominantColors = filterDominantColors(dominantColors,
                                                     self.configuration.initialMinLUVDistance,
                                                     self.configuration.minLUVDistanceIncreaseRate);

  auto litDominantColors = [self dominantColorToLITDominantColor:filteredDominantColors];

  return litDominantColors;
}

- (cv::Mat3b)resizedThreeChannelsImage:(const cv::Mat4b &)image
                  maxWorkingResolution:(int)maxWorkingResolution {
   cv::Mat4b resizedImage;
  auto longSide = std::max(image.cols, image.rows);
  if (longSide > maxWorkingResolution) {
    auto scale = (double)maxWorkingResolution / longSide;
    cv::Size size(image.cols * scale, image.rows * scale);
    cv::resize(image, resizedImage, size);
  } else {
    resizedImage = image;
  }

  cv::Mat3b resized3ChannelsImage(resizedImage.rows, resizedImage.cols);
  resizedImage.forEach([&](cv::Vec4b &pixel, const int position[]) {
    float alpha = pixel(3) / 255.0;
    resized3ChannelsImage(position[0], position[1])(0) =  pixel(0) * alpha + 255 * (1 - alpha);
    resized3ChannelsImage(position[0], position[1])(1) =  pixel(1) * alpha + 255 * (1 - alpha);
    resized3ChannelsImage(position[0], position[1])(2) =  pixel(2) * alpha + 255 * (1 - alpha);
  });
  return resized3ChannelsImage;
}

- (cv::Mat3b)hsvImage:(const cv::Mat3b &)image withPixelFormat:(MTLPixelFormat)pixelFormat {
  cv::Mat3b HSV(image.rows, image.cols);
  if (pixelFormat == MTLPixelFormatBGRA8Unorm) {
     cv::cvtColor(image, HSV, cv::COLOR_BGR2HSV);
  } else {
    cv::cvtColor(image, HSV, cv::COLOR_RGB2HSV);
  }
  return HSV;
}

- (void)convertDominantColorFromHSVToLUV:(std::vector<ScoredColor> *)scoredDominantColors {
  for (auto &scoredColor : *scoredDominantColors) {
    cv::Mat3b mat(scoredColor.color);
    cv::cvtColor(mat, mat, cv::COLOR_HSV2RGB);
    cv::cvtColor(mat, mat, cv::COLOR_RGB2Luv);
    scoredColor.color = mat(0,0);
  }
}

- (void)removeBackgroundColorFromLUVDominantColors:(std::vector<ScoredColor> *)scoredDominantColor
                              withBackgroundParams:(LITBackgroundParams)backgroundParams {
  auto minBackgroundValue = cv::Vec3f(backgroundParams.backgroundColorMinRange(0),
                                      backgroundParams.backgroundColorMinRange(1),
                                      backgroundParams.backgroundColorMinRange(2));
  auto maxBackgroundValue = cv::Vec3f(backgroundParams.backgroundColorMaxRange(0),
                                      backgroundParams.backgroundColorMaxRange(1),
                                      backgroundParams.backgroundColorMaxRange(2));
  auto backgroundMidPoint = cv::Vec3b((minBackgroundValue + maxBackgroundValue) / 2);
  cv::Mat3b luvBackgroundColor(1, 1, backgroundMidPoint);
  cv::cvtColor(luvBackgroundColor, luvBackgroundColor, cv::COLOR_RGB2Luv);

  static const float kBackgroundColorLUVDistance = 30;
  auto isCloseToBackground = [&luvBackgroundColor](const ScoredColor &item){
    auto euclideanDist = cv::norm(cv::Vec3i(luvBackgroundColor(0)) - cv::Vec3i(item.color),
                                  cv::NormTypes::NORM_L2);
    return euclideanDist <= kBackgroundColorLUVDistance;
  };
  auto it = std::remove_if(scoredDominantColor->begin(), scoredDominantColor->end(),
                           isCloseToBackground);
  scoredDominantColor->erase(it, scoredDominantColor->end());
}

- (void)sortDominantColorsByScore:(std::vector<ScoredColor> *)scoredDominantColor {
  auto compare = [](const ScoredColor &a, const ScoredColor &b) {
   return a.score >  b.score;
  };
  std::sort(scoredDominantColor->begin(), scoredDominantColor->end(), compare);
}

- (NSArray<LITDominantColor *> *)dominantColorToLITDominantColor:
    (const std::vector<ScoredColor> &)dominantColorList {
  auto size = dominantColorList.size();
  auto litDominantColors = [NSMutableArray<LITDominantColor *> arrayWithCapacity:size];
  for (auto &dominantColor : dominantColorList) {
    auto rgb = [self vectorLUVToRGB:dominantColor.color];
    auto uiColor = [UIColor colorWithRed:rgb(0) / 255.0 green:rgb(1) / 255.0 blue:rgb(2) / 255.0
                                   alpha:1];
    auto litDominantColor = [[LITDominantColor alloc] initWithColor:uiColor
                                                              score:dominantColor.score];
    [litDominantColors addObject:litDominantColor];
  }
  return litDominantColors;
}

- (cv::Vec3b)vectorLUVToRGB:(cv::Vec3b)vecLUV {
  cv::Mat3b matLUV(vecLUV);
  cv::Mat3b matRGB;
  cv::cvtColor(matLUV, matRGB, cv::COLOR_Luv2RGB);
  return matRGB(0,0);
}

#pragma mark -
#pragma mark Background Detection
#pragma mark -

- (LITBackgroundParams)backgroundParamsFromImage:(const cv::Mat3b &)image {
  auto [minBackgroundValue, maxBackgroundValue] =
      [self backgroundColorRangeByCornersWithImage:image];
  auto backgroundPixels = [self numberOfPixelsInImage:image withRangeMin:minBackgroundValue
                                             rangeMax:maxBackgroundValue];
  LITBackgroundParams backgroundParams(image.cols * image.rows - backgroundPixels,
                                       minBackgroundValue, maxBackgroundValue);
  auto backgroundPercent = (float)backgroundPixels / (image.cols * image.rows);

  static const float kMinBackgroundPercent = 0.15;
  if (backgroundPercent < kMinBackgroundPercent) {
    static const int kBlackAndWhiteBackgroundRange = 26;
    auto blackAndWhiteBackgroundRange = cv::Scalar(kBlackAndWhiteBackgroundRange,
                                                   kBlackAndWhiteBackgroundRange,
                                                   kBlackAndWhiteBackgroundRange, 0);

    cv::Scalar white(255 , 255, 255, 255);
    auto whiteBackgroundPixels = [self numberOfPixelsInImage:image
                                                withRangeMin:white - blackAndWhiteBackgroundRange
                                                    rangeMax:white];
    LITBackgroundParams whiteBackgroundParams(image.cols * image.rows - whiteBackgroundPixels,
                                              white - blackAndWhiteBackgroundRange, white);

    cv::Scalar black(0 , 0, 0, 255);
    auto blackBackgroundPixels = [self numberOfPixelsInImage:image withRangeMin:black
                                                    rangeMax:black + blackAndWhiteBackgroundRange];
    LITBackgroundParams blackBackgroundParams(image.cols * image.rows - blackBackgroundPixels,
                                              black, black + blackAndWhiteBackgroundRange);

    auto compare = [](const LITBackgroundParams &a, const LITBackgroundParams &b) {
      return a.numberOfForegroundPixels < b.numberOfForegroundPixels;
    };
    backgroundParams = std::min(backgroundParams, whiteBackgroundParams, compare);
    backgroundParams = std::min(backgroundParams, blackBackgroundParams, compare);
  }
  return backgroundParams;
}

- (std::pair<cv::Scalar, cv::Scalar>)backgroundColorRangeByCornersWithImage:
    (const cv::Mat3b &)image {
  auto cols = image.cols;
  auto rows = image.rows;

  static const int kCornerSize = 5;
  auto topLeftCorner = image(cv::Rect(0, 0, kCornerSize, kCornerSize));
  auto topRightCorner = image(cv::Rect(0, rows - kCornerSize, kCornerSize, kCornerSize));
  auto bottomRightCorner = image(cv::Rect(cols - kCornerSize, rows - kCornerSize, kCornerSize,
                                          kCornerSize));
  auto bottomLeftCorner = image(cv::Rect(cols - kCornerSize, 0, kCornerSize, kCornerSize));

  cv::Mat4b corners(4, 1);
  corners(0, 0) = cv::mean(topLeftCorner);
  corners(1, 0) = cv::mean(topRightCorner);
  corners(2, 0) = cv::mean(bottomRightCorner);
  corners(3, 0) = cv::mean(bottomLeftCorner);

  cv::Mat1b cornerByChannel = corners.reshape(1);
  cv::sort(cornerByChannel, cornerByChannel, cv::SORT_EVERY_COLUMN);
  cv::Mat4b sortedCorners = cornerByChannel.reshape(4);
  cv::Scalar backgroundMedian = cv::mean(sortedCorners.rowRange(1, 3));
  cv::Vec4b backgroundRange = sortedCorners(3,0) - sortedCorners(0,0);
  static const int kBackgroundMinRange = 10;
  static const int kBackgroundMaxRange = 20;
  cv::max(backgroundRange, kBackgroundMinRange, backgroundRange);
  cv::min(backgroundRange, kBackgroundMaxRange, backgroundRange);

  auto backgroundRangeScalar = cv::Scalar(backgroundRange(0), backgroundRange(0),
                                          backgroundRange(0));
  auto maxBackgroundValue = backgroundMedian + backgroundRangeScalar;
  auto minBackgroundValue = backgroundMedian - backgroundRangeScalar;

  return {
    [self clampScalar:minBackgroundValue toMin:0 max:255],
    [self clampScalar:maxBackgroundValue toMin:0 max:255]
  };
}

- (cv::Scalar)clampScalar:(cv::Scalar)scalar toMin:(float)min max:(float)max {
  cv::threshold(scalar, scalar, 255, 255, cv::THRESH_TRUNC);
  cv::threshold(scalar, scalar, 0, 0, cv::ThresholdTypes::THRESH_TOZERO);
  return scalar;
}

- (int)numberOfPixelsInImage:(const cv::Mat3b &)image withRangeMin:(cv::Scalar)min
                    rangeMax:(cv::Scalar)max {
  cv::Mat1b inRangePixels;
  cv::inRange(image, min, max, inRangePixels);

  auto numOfPixelsInRange = cv::countNonZero(inRangePixels);
  return numOfPixelsInRange;
}

#pragma mark -
#pragma mark Dominant Colors Extraction
#pragma mark -

- (void)extractDominantColorFromHSVImage:(const cv::Mat3b &)hsvImage
                     numForegroundPixels:(int)numForegroundPixels
                  populateDominantColors:(std::vector<ScoredColor> *)dominantColors {
  std::vector<std::vector<cv::Vec3b>> slices;
  [self splitPixelsToBinsWithImage:hsvImage populateSlicePerBin:&slices];

  for (auto &slice : slices) {
    float sliceScore = (float)slice.size() / numForegroundPixels;
    if (sliceScore * 100 < self.configuration.minBinSizePercent) {
      continue;
    }
    auto representative = representativeOfSlice(cv::Mat3b(slice), (int)slice.size(),
                                                self.configuration.representativePercentileParams);
    (*dominantColors).push_back(ScoredColor(representative, sliceScore));
  }
}

- (void)splitPixelsToBinsWithImage:(const cv::Mat3b &)hsvImage
               populateSlicePerBin:(std::vector<std::vector<cv::Vec3b>> *)slicePerBin {
  auto binIndexImage = [self binIndexImageWithHSVImage:hsvImage];

  cv::Mat1s erodedBinIndexImage, dilatedBinIndexImage;
  static const int kErosionKernelSize = 3;
  auto kernel = cv::getStructuringElement(cv::MorphShapes::MORPH_RECT,
                                          {kErosionKernelSize, kErosionKernelSize});
  cv::erode(binIndexImage, erodedBinIndexImage, kernel);
  cv::dilate(binIndexImage, dilatedBinIndexImage, kernel);

  auto numBins = self.configuration.numOfGrayBins + self.configuration.numOfBinsInHField *
      self.configuration.numOfBinsInSField * self.configuration.numOfBinsInVField;
  slicePerBin->resize(numBins);
  for (int i = 0; i < hsvImage.rows ; i++) {
    for (int j = 0; j < hsvImage.cols ; j++) {
      auto areaMinIndex = erodedBinIndexImage(i, j);
      auto areaMaxIndex = dilatedBinIndexImage(i, j);
      if (areaMinIndex == areaMaxIndex) {
        (*slicePerBin)[areaMinIndex].push_back(hsvImage(i, j));
      }
    }
  }
}

- (cv::Mat1s)binIndexImageWithHSVImage:(const cv::Mat3b &)hsvImage {
  int grayValueBinWidth =  std::ceil(256.0 / self.configuration.numOfGrayBins);
  int hueBinWidth = std::ceil(180.0 / self.configuration.numOfBinsInHField);
  int saturationBinWidth = std::ceil(256.0 / self.configuration.numOfBinsInSField);
  int valueBinWidth = std::ceil(256.0 / self.configuration.numOfBinsInVField);

  static const int kMaxGraySaturation = 25;
  cv::Mat1f binIndexImage(hsvImage.rows, hsvImage.cols);
  hsvImage.forEach([&](cv::Vec3b &pixel, const int position[]) {
    if (pixel(1) <= kMaxGraySaturation) {
      auto grayValueIndex = pixel(2) / grayValueBinWidth;
      binIndexImage(position[0], position[1]) = grayValueIndex;
    } else {
      auto hueIndex = pixel(0) / hueBinWidth;
      auto saturationIndex = pixel(1) / saturationBinWidth;
      auto valueIndex = pixel(2) / valueBinWidth;
      auto totalIndex = (hueIndex * (self.configuration.numOfBinsInSField *
                                     self.configuration.numOfBinsInVField) +
                         saturationIndex * (self.configuration.numOfBinsInVField) + valueIndex);
      totalIndex += self.configuration.numOfGrayBins;
      binIndexImage(position[0], position[1]) = totalIndex;
    }
  });

  return binIndexImage;
}

@end

NS_ASSUME_NONNULL_END
