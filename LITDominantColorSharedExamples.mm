// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorSharedExamples.h"

#import "LITDominantColor.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const kLITDominantColorExamples = @"dominantColorSharedExamples";
NSString * const kLITDominantColorExamplesExpectedDominantColors = @"expectedDominantColors";
NSString * const kLITDominantColorExamplesDetectedDominantColors = @"detectedDominantColors";
NSString * const kLITDominantColorExamplesInput = @"dominantColorInputImage";
NSString * const kLITDominantColorExamplesExpectedFileName = @"dominantColorExpectedFileName";

static cv::Mat4b LITVisualizeDominantColors(NSArray<LITDominantColor*> *dominantColors,
                                            cv::Mat4b image) {
  auto dominantColorsHeight = image.rows / 5;
  cv::Mat4b output(image.rows + dominantColorsHeight, image.cols);
  image.copyTo(output.rowRange(dominantColorsHeight, image.rows + dominantColorsHeight));

  auto dominantColorsWidth = image.cols / (int)dominantColors.count;
  for (int i = 0 ; i < (int)dominantColors.count; i++) {
    cv::Point origin(dominantColorsWidth * i, 0);
    cv::Rect rect(origin, cv::Size(dominantColorsWidth, dominantColorsHeight));
    CGFloat red, green, blue;
    [dominantColors[i].color getRed:&red green:&green blue:&blue alpha:nil];
    auto color = cv::Scalar(red * 255.0, green * 255.0, blue * 255.0, 255);
    cv::rectangle(output, rect, color, cv::FILLED);
  }
  return output;
}

SharedExamplesBegin(LITDominantColor)

sharedExamples(kLITDominantColorExamples, ^(NSDictionary *data) {
  __block NSArray<LITDominantColor *> *expectedDominantColors;
  __block NSArray<LITDominantColor *> *dominantColors;
  __block id<MTLTexture> input;
  __block NSString *expectedFileName;

  beforeEach(^{
    expectedDominantColors = data[kLITDominantColorExamplesExpectedDominantColors];
    dominantColors = data[kLITDominantColorExamplesDetectedDominantColors];
    input = data[kLITDominantColorExamplesInput];
    expectedFileName = (NSString *)data[kLITDominantColorExamplesExpectedFileName];
  });

  it(@"should find dominant colors in the image", ^{
    expect(dominantColors.count).to.equal(expectedDominantColors.count);

    auto reorderedDominantColors = [[NSMutableArray<LITDominantColor *> alloc] init];
    auto mutableDominantColors = [NSMutableArray<LITDominantColor *> arrayWithArray:dominantColors];
    bool allColorsFound = YES;
    for (LITDominantColor *expected in expectedDominantColors) {
      bool found = NO;
      for (LITDominantColor *dominantColor in mutableDominantColors) {
        CGFloat red, green, blue;
        [dominantColor.color getRed:&red green:&green blue:&blue alpha:nil];

        CGFloat expectedRed, expectedGreen, expectedBlue;
        [expected.color getRed:&expectedRed green:&expectedGreen blue:&expectedBlue alpha:nil];
        if (std::abs(red - expectedRed) <= 4 / 255.0 &&
            std::abs(green - expectedGreen) <= 4 / 255.0 &&
            std::abs(blue - expectedBlue) <= 4 / 255.0) {
          expect(dominantColor.score).to.beCloseToWithin(expected.score, 0.02);
          found = YES;
          [mutableDominantColors removeObject:dominantColor];
          [reorderedDominantColors addObject:dominantColor];
          break;
        }
      }
      expect(found).to.beTruthy();

      if(!found) {
        allColorsFound = NO;
        break;
      }
    }

    [mtb(input) mtb_mappedForReading:^(const cv::Mat &image) {
      cv::Mat4b outputImage;
      if (allColorsFound) {
        outputImage = LITVisualizeDominantColors(reorderedDominantColors, image);
      } else {
        outputImage = LITVisualizeDominantColors(dominantColors, image);
      }
      auto bundle = NSBundle.lt_testBundle;
      auto expected = LTLoadMatFromBundle(bundle, expectedFileName);
      expect($(outputImage)).to.beCloseToMatWithin($(expected), 4);
    }];
  });
});

SharedExamplesEnd

NS_ASSUME_NONNULL_END
