// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorLogoProcessor.h"

#import "LITDominantColorSharedExamples.h"

SpecBegin(LITDominantColorLogoProcessor)

__block LITDominantColorLogoProcessor *processor;
__block id<MTLDevice> device;

beforeEach(^{
  device = MTLCreateSystemDefaultDevice();
  LITDominantColorsLogoConfiguration configuration = LITDominantColorsLogoConfigurationDefault();
  processor = [[LITDominantColorLogoProcessor alloc] initWithConfiguration:configuration];
});

itBehavesLike(kLITDominantColorExamples, ^{
  auto bundle = NSBundle.lt_testBundle;
  auto image = LTLoadMatFromBundle(bundle,@"logo_input.png");

  auto input = [mtb(device) mtb_newIOSurfaceBackedTextureWithWidth:image.cols
                                                            height:image.rows
                                                       pixelFormat:MTLPixelFormatRGBA8Unorm];
  [input mtb_mappedForWriting:^(cv::Mat *mat) {
    image.copyTo(*mat);
  }];

  const int kMaxWorkingResolution = 256;
  auto dominantColors = [processor dominantColorsInImage:input
                                    maxWorkingResolution:kMaxWorkingResolution];

  auto expectedDominantColors = [[NSMutableArray<LITDominantColor *> alloc] initWithObjects:
    [[LITDominantColor alloc] initWithColor:[UIColor colorWithRed:236 / 255.0 green:16 / 255.0
                                                             blue:148 / 255.0 alpha:1]
                                      score:0.49],
    [[LITDominantColor alloc] initWithColor:[UIColor colorWithRed:181 / 255.0 green:29 / 255.0
                                                             blue:145 / 255.0 alpha:1]
                                      score:0.127],
    [[LITDominantColor alloc] initWithColor:[UIColor colorWithRed:93 / 255.0 green:43 / 255.0
                                                             blue:137 / 255.0 alpha:1]
                                      score:0.07], nil
  ];

  return @{
    kLITDominantColorExamplesInput : input,
    kLITDominantColorExamplesExpectedFileName : @"dominantColorLogo_output.png",
    kLITDominantColorExamplesDetectedDominantColors : dominantColors,
    kLITDominantColorExamplesExpectedDominantColors: expectedDominantColors
  };
});

it(@"should return an empty dominant color list on a constant color image", ^{
  cv::Mat4b whiteImage(10, 10, cv::Scalar(255, 255, 255, 255));
  auto input = [mtb(device) mtb_newIOSurfaceBackedTextureWithWidth:whiteImage.cols
                                                            height:whiteImage.rows
                                                       pixelFormat:MTLPixelFormatRGBA8Unorm];
   [input mtb_mappedForWriting:^(cv::Mat *mat) {
     whiteImage.copyTo(*mat);
   }];

   const int kMaxWorkingResolution = 256;
   auto dominantColors = [processor dominantColorsInImage:input
                                     maxWorkingResolution:kMaxWorkingResolution];
  expect(dominantColors.count).to.equal(0);
});

SpecEnd
