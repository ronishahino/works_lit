// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorsProcessor.h"

#import <MetalToolbox/MTBCommandBuffer.h>
#import <MetalToolbox/MTBDevice.h>
#import <MetalToolbox/MTBTexture.h>

#import "LITDominantColorBinRepresentativesPicker.h"
#import "LITDominantColorHSBinIndex.h"
#import "LITDominantColorPreprocessor.h"
#import "LITDominantColorUtilities.h"

using namespace lit_dominant_color;

NS_ASSUME_NONNULL_BEGIN

LITDominantColorsConfiguration LITDominantColorsConfigurationDefault() {
  return {
    .numOfBinsInHField = 5,
    .numOfBinsInSField = 8,
    .luvMinDistance = 45.0,
    .minimalSaturation = 0.05,
    .minimalValue = 0.05,
    .maxBinsToIterate = 15,
    .representativePercentileParams = LITDominantColorRepresentativePercentileParamsMake(0.5, 0.85,
                                                                                         0.85),
    .saturatedPriorityFactor = 3.5,
    .maxDominantColorsPerBin = 2
  };
}

static const LITDominantColorRepresentativesPickerConfiguration
    kRepresentativePickerConfiguration = {
  .dbScanRadius = 0.0049,
  .dbScanMinNeighbors = 30,
  .dbScanPointMultipliers = {1.1, 0.5, 0.5}
};

@interface LITDominantColorsProcessor ()

/// Object finds representative colors in image bin.
@property (nonatomic, readonly) LITDominantColorBinRepresentativesPicker *binRepresentativePicker;

/// Object performs preprocessing for dominantColor.
@property (nonatomic, readonly) LITDominantColorPreprocessor *preprocessor;

/// LITDominantColorsProcessor configuration parameters.
@property (nonatomic, readonly) LITDominantColorsConfiguration configuration;

/// Bin width in hue field.
@property (nonatomic, readonly) int binWidthH;

/// Bin width in saturation field.
@property (nonatomic, readonly) int binWidthS;

@end

@implementation LITDominantColorsProcessor

- (instancetype)initWithDevice:(id<MTLDevice>)device
                 configuration:(LITDominantColorsConfiguration)dominantColorsConfiguration {
   if (self = [super init]) {
     [self validateConfiguration:dominantColorsConfiguration];
     _configuration = dominantColorsConfiguration;
     /// H filed range is [0, 180].
     _binWidthH = 180 / (int)self.configuration.numOfBinsInHField;
     _binWidthS = 256 / (int)self.configuration.numOfBinsInSField;

     _preprocessor = [[LITDominantColorPreprocessor alloc] initWithDevice:device];

     _binRepresentativePicker = [[LITDominantColorBinRepresentativesPicker alloc]
         initWithBinHueWidth:self.binWidthH binSaturationWidth:self.binWidthS
         representativePercentileParams:self.configuration.representativePercentileParams
         representativePickerConfiguration:kRepresentativePickerConfiguration];

     performRGBToLUVConversionOnce();
   }
  return self;
}

- (void)validateConfiguration:(LITDominantColorsConfiguration)configuration {
  LTParameterAssert(configuration.numOfBinsInHField * configuration.numOfBinsInSField >=
                    configuration.maxBinsToIterate, @"maxBinsToIterate must be smaller than"
                    " or equal to numOfBinsInHField * numOfBinsInSField");
  LTParameterAssert(configuration.numOfBinsInSField <= 256 && configuration.numOfBinsInSField >= 1,
                    @"numOfBinsInSField must be in range of [1, 256]");
  LTParameterAssert(configuration.numOfBinsInHField <= 256 && configuration.numOfBinsInHField >= 1,
                    @"numOfBinsInHField must be in range of [1, 256]");
  LTParameterAssert(configuration.minimalSaturation <= 1 &&
                    configuration.minimalSaturation >= 0 > 0,
                    @"SChannelThresh must be in range [0, 1]");
  LTParameterAssert(configuration.minimalValue <= 1 &&
                    configuration.minimalValue >= 0,
                    @"VChannelThresh must be in range [0, 1]");
}

#pragma mark -
#pragma mark Processing
#pragma mark -

- (nullable NSArray<LITDominantColor*> *)findDominantColorsInImage:(id<MTLTexture>)texture
    maxWorkingResolution:(unsigned int)maxWorkingResolution
    bilateralFilterRangeSigma:(float)bilateralFilterRangeSigma
    commandQueue:(id<MTLCommandQueue>)commandQueue error:(NSError **)error {
  [LITImageValidator validateImage:texture
                   forPixelFormats:{MTLPixelFormatRGBA8Unorm, MTLPixelFormatBGRA8Unorm}];

  // preprocessing consists of resolution reduction + bilateral filtering + conversion RGB to HSV
  // color space.
  auto HSVImage = [self preprocessedImage:texture maxWorkingResolution:maxWorkingResolution
                bilateralFilterRangeSigma:bilateralFilterRangeSigma
                             commandQueue:commandQueue error:error];
  if (!HSVImage) {
    return nil;
  }

  __block std::vector<ScoredColor> filteredDominantColors;
  [mtb(HSVImage) mtb_mappedForReading:^(const cv::Mat &HSVMat) {
    // HSVImage is a HSV 4 channels texture. so convert RGBA2RGB in order to remove the forth
    // channel.
    cv::Mat3b hsv;
    cv::cvtColor(HSVMat, hsv, cv::COLOR_RGBA2RGB);

    auto dominantColorsHSV = [self dominantColorValuesFromHSVImage:hsv];
    if(dominantColorsHSV.empty()) {
      return;
    }
    auto dominantColorsLUV = [self convertListFromHSVToLUV:dominantColorsHSV];
    auto luvImage = [self convertImageFromHSVToLUV:hsv];
    auto scoredDominantColor = [self sortedLUVColorsByScore:dominantColorsLUV inLUVImage:luvImage];
    filteredDominantColors = filterDominantColors(scoredDominantColor,
                                                  self.configuration.luvMinDistance);
  }];

  auto litDominantColors = [self dominantColorToLITDominantColor:filteredDominantColors];
  return litDominantColors;
}

- (nullable id<MTLTexture>)preprocessedImage:(id<MTLTexture>)texture
                        maxWorkingResolution:(unsigned int)maxWorkingResolution
                   bilateralFilterRangeSigma:(float)bilateralFilterRangeSigma
                                commandQueue:(id<MTLCommandQueue>)commandQueue
                                       error:(NSError **)error {
  auto device = commandQueue.device;

  auto width = texture.width;
  auto height = texture.height;
  auto longSide = std::max(width, height);
  auto scale = (double)maxWorkingResolution / longSide;
  auto usage = MTLTextureUsageShaderWrite;
  auto destination = [mtb(device) mtb_newIOSurfaceBackedTextureWithWidth:scale * width
                                                                  height:scale * height
                                                             pixelFormat:MTLPixelFormatRGBA8Unorm
                                                                   usage:usage];

  auto commandBuffer = [commandQueue commandBuffer];
  [self.preprocessor encodeToCommandBuffer:commandBuffer sourceTexture:texture
                        destinationTexture:destination
                 bilateralFilterRangeSigma:bilateralFilterRangeSigma];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  if (commandBuffer.status != MTLCommandBufferStatusCompleted) {
    if (error) {
      *error = commandBuffer.error;
    }
    return nil;
  }
  return destination;
}

- (std::vector<cv::Vec3b>)dominantColorValuesFromHSVImage:(cv::Mat3b)hsvImage {
  std::vector<std::vector<cv::Vec3b>> imageBins;
  auto hsvHistogram = [self calculateHSVHistogramForImage:hsvImage populateBins:&imageBins];
  auto sortedHSBinIndexes = [self hsBinIndexesSortedBySize:imageBins];

  std::vector<cv::Vec3b> dominantColorsHSV;
  auto binsToIterate = std::min(self.configuration.numOfBinsInHField *
                                self.configuration.numOfBinsInSField,
                                self.configuration.maxBinsToIterate);
  for (auto &hsBinIndex : sortedHSBinIndexes) {
    auto imageBin = imageBins[hsBinIndex.hueIndex * self.configuration.numOfBinsInSField
                              + hsBinIndex.saturationIndex];
    if (binsToIterate == 0 || imageBin.empty()) {
      break;
    }

    auto binDominantColorsHSV = [self.binRepresentativePicker
        findRepresentativeColorsInBin:imageBin withIndex:hsBinIndex histogram:hsvHistogram];
    [self addNewBinDominantColors:binDominantColorsHSV toList:&dominantColorsHSV];
    binsToIterate -= 1;
  }
  return dominantColorsHSV;
}

- (std::vector<cv::Vec3b>)convertListFromHSVToLUV:(const std::vector<cv::Vec3b> &)listHSV {
  std::vector<cv::Vec3b> luv;
  cv::cvtColor(listHSV, luv, cv::COLOR_HSV2RGB);
  cv::cvtColor(luv, luv, cv::COLOR_RGB2Luv);
  return luv;
}

- (cv::Vec3b)vectorLUVToRGB:(cv::Vec3b)vecLUV {
  cv::Mat3b matLUV(vecLUV);
  cv::Mat3b matRGB;
  cv::cvtColor(matLUV, matRGB, cv::COLOR_Luv2RGB);
  return matRGB(0,0);
}

- (NSArray<LITDominantColor *> *)dominantColorToLITDominantColor:
    (const std::vector<ScoredColor> &)dominantColorList {
  auto size = dominantColorList.size();
  auto litDominantColors = [NSMutableArray<LITDominantColor *> arrayWithCapacity:size];
  for (auto &dominantColor : dominantColorList) {
    auto rgb = [self vectorLUVToRGB:dominantColor.color];
    auto uiColor = [UIColor colorWithRed:rgb(0) / 255.0
                                   green:rgb(1) / 255.0
                                    blue:rgb(2) / 255.0 alpha:1];
    auto litDminantColor = [[LITDominantColor alloc] initWithColor:uiColor
                                                             score:dominantColor.score];
    [litDominantColors addObject:litDminantColor];
  }
  return litDominantColors;
}

- (cv::Mat3b)convertImageFromHSVToLUV:(const cv::Mat3b &)imageHSV {
  cv::Mat3b imageLUV;
  cv::cvtColor(imageHSV, imageLUV, cv::COLOR_HSV2RGB);
  cv::cvtColor(imageLUV, imageLUV, cv::COLOR_RGB2Luv);
  return imageLUV;
}

- (void)addNewBinDominantColors:(const std::vector<cv::Vec3b> &)binDominantColors
                         toList:(std::vector<cv::Vec3b> *)dominantColors {
  int addedDominantColorsInCurrentBin = 0;
  for (auto &newDominantColor : binDominantColors) {
    if (addedDominantColorsInCurrentBin == self.configuration.maxDominantColorsPerBin) {
     break;
    }
      dominantColors->push_back(newDominantColor);
      addedDominantColorsInCurrentBin++;
  }
}

#pragma mark -
#pragma mark Histogram Preparation
#pragma mark -

- (bool)shouldIgnorePixel:(cv::Vec3b)hsvPixel {
  if (hsvPixel(1) > self.configuration.minimalSaturation * 255.0 &&
      hsvPixel(2) > self.configuration.minimalValue * 255.0) {
    return false;
  }
  return true;
}

- (cv::Mat1f)calculateHSVHistogramForImage:(cv::Mat3b)hsvImage
                              populateBins:(std::vector<std::vector<cv::Vec3b>> *)bins {
  /// Values range of H channel is [0, 180].
  int histSize[3] = {180, 256, 256};
  cv::Mat1f hsvHistogram = cv::Mat::zeros(3, histSize, CV_32FC1);

  bins->resize(self.configuration.numOfBinsInHField * self.configuration.numOfBinsInSField);
  for (int i = 0; i < hsvImage.rows; i++) {
    for (int j = 0; j < hsvImage.cols; j++) {
      auto pixel = hsvImage(i, j);
      if ([self shouldIgnorePixel:pixel]) {
        continue;
      }
      int hBinIndex = pixel(0) / self.binWidthH;
      int sBinIndex = pixel(1) / self.binWidthS;
      (*bins)[hBinIndex * self.configuration.numOfBinsInSField + sBinIndex].push_back(pixel);

      hsvHistogram(pixel(0), pixel(1), pixel(2)) += 1;
    }
  }
  return hsvHistogram;
}

- (std::vector<LITHSBinIndex>)hsBinIndexesSortedBySize:(const std::vector<std::vector<cv::Vec3b>> &)
    bins {
  std::vector<LITHSBinIndex> binIndexes;
  for (unsigned int i = 0; i < self.configuration.numOfBinsInHField; i++) {
    for (unsigned int j = 0; j < self.configuration.numOfBinsInSField; j++) {
      binIndexes.push_back(LITHSBinIndex(i, j));
    }
  }
  auto compare = [&bins, &self](const LITHSBinIndex &left, LITHSBinIndex &right) {
    float priorityLeft = bins[left.hueIndex * self.configuration.numOfBinsInSField +
                              left.saturationIndex].size();
    auto priorityTendencyToSaturationFactorLeft = 1 + ((float)left.saturationIndex /
                                                   (self.configuration.numOfBinsInSField - 1) *
                                                   self.configuration.saturatedPriorityFactor);

    float priorityRight = bins[right.hueIndex * self.configuration.numOfBinsInSField +
                              right.saturationIndex].size();
    auto priorityTendencyToSaturationFactorRight = 1 + ((float)right.saturationIndex /
                                                   (self.configuration.numOfBinsInSField - 1) *
                                                   self.configuration.saturatedPriorityFactor);
    return priorityLeft * priorityTendencyToSaturationFactorLeft >
        priorityRight * priorityTendencyToSaturationFactorRight;
  };
  std::sort(binIndexes.begin(), binIndexes.end(), compare);
  return binIndexes;
}

#pragma mark -
#pragma mark Filtering by LUV Distance
#pragma mark -

- (std::vector<ScoredColor>)sortedLUVColorsByScore:(const std::vector<cv::Vec3b> &)colors
                                        inLUVImage:(const cv::Mat3b &)imageLUV {
  auto dominantColorsSize = (int)colors.size();
  /// \c distancesMat has rows as the number of pixels and columns as the number of dominant colors.
  /// Each entry contain 1 if the distance in LUV color space between the appropriate pixel and
  /// dominant color is below threshold, and 0 otherwise.
  cv::Mat1f distancesMat = cv::Mat1f::zeros(imageLUV.cols * imageLUV.rows, dominantColorsSize);
  int cols = imageLUV.cols;
  static const float kMaxOverlappingAreaBetweenPotentialDominantColors = 1.0 / 3.0;
  auto factor = (1 - kMaxOverlappingAreaBetweenPotentialDominantColors);
  auto distanceTreshold = self.configuration.luvMinDistance * factor;
  imageLUV.forEach([&dominantColorsSize, &distancesMat, &colors ,&cols, &distanceTreshold]
                   (cv::Vec3b &pixel, const int position[]) {
    auto distancesMatRow = position[0] * cols + position[1];
    for (int i = 0; i < dominantColorsSize; i++) {
      auto euclideanDist = cv::norm(cv::Vec3i(pixel) - cv::Vec3i(colors[i]),
                                    cv::NormTypes::NORM_L2);
      if (euclideanDist < distanceTreshold) {
        distancesMat(distancesMatRow, i) = 1;
      }
    }
  });

  std::vector<float> scoreList;
  cv::reduce(distancesMat, scoreList, 0, cv::REDUCE_SUM);

  std::vector<ScoredColor> scoredDominantColorList;
  scoredDominantColorList.resize(dominantColorsSize);
  for (int i = 0; i < dominantColorsSize; i++) {
    auto normalizedScore = scoreList[i] / imageLUV.rows / imageLUV.cols;
    scoredDominantColorList[i] = ScoredColor{colors[i], normalizedScore};
  }

  auto compare = [](const ScoredColor &a, const ScoredColor &b) {
   return a.score >  b.score;
  };
  std::sort(scoredDominantColorList.begin(), scoredDominantColorList.end(), compare);

  return scoredDominantColorList;
}

@end

NS_ASSUME_NONNULL_END
