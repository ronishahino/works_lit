// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorsProcessor.h"

#import "LITDominantColorSharedExamples.h"

SpecBegin(LITDominantColor)

__block cv::Mat4b inputMat;
__block LITDominantColorsProcessor *processor;
__block id<MTLDevice> device;

beforeEach(^{
  auto bundle = NSBundle.lt_testBundle;
  inputMat = LTLoadMatFromBundle(bundle, @"Lena128.png");
  device = MTLCreateSystemDefaultDevice();

  auto configuration = LITDominantColorsConfigurationDefault();
  processor = [[LITDominantColorsProcessor alloc] initWithDevice:device
                                                   configuration:configuration];
});

it(@"should return empty dominant colors list on grayscale image", ^{
  cv::Mat grayscale;
  cv::cvtColor(inputMat, grayscale, cv::COLOR_RGBA2GRAY);
  cv::cvtColor(grayscale, grayscale, cv::COLOR_GRAY2RGBA);

  auto input = [mtb(device) mtb_newIOSurfaceBackedTextureWithWidth:inputMat.cols
                                                            height:inputMat.rows
                                                       pixelFormat:MTLPixelFormatRGBA8Unorm];
  [input mtb_mappedForWriting:^(cv::Mat *mat) {
    grayscale.copyTo(*mat);
  }];
  auto commandQueue = [device newCommandQueue];
  NSError *error;
  const int kMaxWorkingResolution = 128;
  const float kBilateralFilterRangeSigma = 0.3;
  auto dominantColors = [processor findDominantColorsInImage:input
                                       maxWorkingResolution:kMaxWorkingResolution
                                  bilateralFilterRangeSigma:kBilateralFilterRangeSigma
                                               commandQueue:commandQueue error:&error];
  expect(dominantColors.count).to.equal(0);
});

itBehavesLike(kLITDominantColorExamples, ^{
  auto input = [mtb(device) mtb_newIOSurfaceBackedTextureWithWidth:inputMat.cols
                                                            height:inputMat.rows
                                                       pixelFormat:MTLPixelFormatRGBA8Unorm];
  [input mtb_mappedForWriting:^(cv::Mat *mat) {
    inputMat.copyTo(*mat);
  }];

  auto commandQueue = [device newCommandQueue];
  NSError *error;
  const int kMaxWorkingResolution = 128;
  const float kBilateralFilterRangeSigma = 0.3;
  auto dominantColors = [processor findDominantColorsInImage:input
                                        maxWorkingResolution:kMaxWorkingResolution
                                   bilateralFilterRangeSigma:kBilateralFilterRangeSigma
                                                commandQueue:commandQueue error:&error];

  auto expectedDominantColors = [[NSMutableArray<LITDominantColor *> alloc] initWithObjects:
    [[LITDominantColor alloc] initWithColor:[UIColor colorWithRed:203 / 255.0 green:102 / 255.0
                                                             blue:106 / 255.0 alpha:1]
                                      score:0.443],
    [[LITDominantColor alloc] initWithColor:[UIColor colorWithRed:104 / 255.0 green:28 / 255.0
                                                             blue:67 / 255.0 alpha:1]
                                      score:0.2006],
    [[LITDominantColor alloc] initWithColor:[UIColor colorWithRed:220 / 255.0 green:168 / 255.0
                                                             blue:156 / 255.0 alpha:1]
                                      score:0.1967],
    [[LITDominantColor alloc] initWithColor:[UIColor colorWithRed:134 / 255.0 green:96 / 255.0
                                                             blue:147 / 255.0 alpha:1]
                                      score:0.0316], nil
  ];
  return @{
    kLITDominantColorExamplesInput : input,
    kLITDominantColorExamplesExpectedFileName : @"dominantColor_output.png",
    kLITDominantColorExamplesDetectedDominantColors : dominantColors,
    kLITDominantColorExamplesExpectedDominantColors: expectedDominantColors
  };
});

SpecEnd
