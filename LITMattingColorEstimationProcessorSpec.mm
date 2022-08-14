// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITMattingColorEstimationProcessor.h"

static cv::Mat4b LITCombineImagesByMask(cv::Mat image1, cv::Mat image2, cv::Mat mask) {
  // Combine images by: image1 * mask + image2 * (1 - mask)
  mask.convertTo(mask, CV_32F, 1 / 255.f);
  cv::Mat maskMutliChannels;
  cv::Mat mats[4] = {mask, mask, mask, mask};
  cv::merge(mats, 4, maskMutliChannels);
  maskMutliChannels = maskMutliChannels.reshape(1);

  image1.convertTo(image1, CV_32F);
  image1 = image1.reshape(1);
  image2.convertTo(image2, CV_32F);
  image2 = image2.reshape(1);

  cv::Mat combined1, combined2, combinedImage;
  cv::multiply(image1, maskMutliChannels, combined1);
  cv::multiply(image2, 1 - maskMutliChannels, combined2);
  cv::add(combined1, combined2, combinedImage);

  combinedImage.convertTo(combinedImage, CV_8U);
  combinedImage = combinedImage.reshape(4);
  return combinedImage;
}

SpecBegin(LITMattingColorEstimationProcessor)

__block id<MTLDevice> device;
__block id<MTLTexture> image;
__block id<MTLTexture> alpha;
__block id<MTLTexture> foreground;
__block id<MTLTexture> background;
__block LITMattingColorEstimationProcessor *processor;

beforeEach(^{
  device = MTLCreateSystemDefaultDevice();
  auto bundle = NSBundle.lt_testBundle;
  auto imageMat = LTLoadMatFromBundle(bundle, @"lemur.png");
  image = PNKTextureFromMat(imageMat, device);

  auto alphaMat = LTLoadMatFromBundle(bundle, @"lemur_alpha.png");
  alpha = PNKTextureFromMat(alphaMat, device);

  processor = [[LITMattingColorEstimationProcessor alloc] initWithDevice:device];

  foreground = PNKTextureWithPropertiesOfMat(imageMat, device);
  background = PNKTextureWithPropertiesOfMat(imageMat, device);
});

it(@"should calculate background and foreground images", ^{
  auto configuration = LITMattingColorEstimationProcessorConfigurationDefault();

  auto commandBuffer = [[device newCommandQueue] commandBuffer];
  [processor encodeToCommandBuffer:commandBuffer sourceTexture:image alpha:alpha
             destinationForeground:foreground destinationBackground:background
                     configuration:configuration];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  auto bundle = NSBundle.lt_testBundle;
  auto expectedForeground = LTLoadMatFromBundle(bundle, @"lemur_foreground_output.png");
  auto expectedBackground = LTLoadMatFromBundle(bundle, @"lemur_background_output.png");

  auto foregroundMat = PNKMatFromMTLTexture(foreground);
  expect($(foregroundMat)).to.beCloseToMatPSNR($(expectedForeground), 50);

  auto backgroundMat = PNKMatFromMTLTexture(background);
  expect($(backgroundMat)).to.beCloseToMatPSNR($(expectedBackground), 50);
});

it(@"should restore original image by combining foreground and background", ^{
  LITMattingColorEstimationProcessorConfiguration configuration;
  configuration.numberOfIterationsForLargeScales = 2;
  configuration.numberOfIterationsForSmallScales = 9;
  configuration.smallScalesThreshold = 64;

  auto commandBuffer = [[device newCommandQueue] commandBuffer];
  [processor encodeToCommandBuffer:commandBuffer sourceTexture:image alpha:alpha
             destinationForeground:foreground destinationBackground:background
                     configuration:configuration];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  auto alphaMat = PNKMatFromMTLTexture(alpha);
  auto imageMat = PNKMatFromMTLTexture(image);
  auto foregroundMat = PNKMatFromMTLTexture(foreground);
  auto backgroundMat = PNKMatFromMTLTexture(background);

  auto restoredImage = LITCombineImagesByMask(foregroundMat, backgroundMat, alphaMat);

  expect($(restoredImage)).to.beCloseToMatPSNR($(imageMat), 50);
});

it(@"should calculate only foreground and replace background by constant color", ^{
  auto commandBuffer = [[device newCommandQueue] commandBuffer];
  [processor encodeToCommandBuffer:commandBuffer sourceTexture:image alpha:alpha
             destinationForeground:foreground destinationBackground:nil];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  cv::Mat4b gray((int)image.height, (int)image.width, cv::Scalar(128, 128, 128, 255));

  auto alphaMat = PNKMatFromMTLTexture(alpha);
  auto foregroundMat = PNKMatFromMTLTexture(foreground);

  auto replacedBackground = LITCombineImagesByMask(foregroundMat, gray, alphaMat);

  auto bundle = NSBundle.lt_testBundle;
  auto expected = LTLoadMatFromBundle(bundle, @"lemur_replaced_background.png");

  expect($(replacedBackground)).to.beCloseToMatWithin($(expected), 5);
});

SpecEnd
