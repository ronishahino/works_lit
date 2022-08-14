// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorPreprocessor.h"

#import "LITBilateralFilter.h"
#import "LITColorConversion.h"
#import "LITQuadCopy.h"

NS_ASSUME_NONNULL_BEGIN

@interface LITDominantColorPreprocessor ()

/// Device to run this processor on.
@property (nonatomic, readonly) id<MTLDevice> device;

/// Processor used to operate bilateralFilter to the image.
@property (nonatomic, readonly) LITBilateralFilter *bilateralFilterProcessor;

/// Processor used to convert the image color space.
@property (nonatomic, readonly) LITColorConversion *colorConversionProcessor;

/// Processor used to resize the images.
@property (nonatomic, readonly) LITQuadCopy *quadCopyProcessor;

@end

@implementation LITDominantColorPreprocessor

- (instancetype)initWithDevice:(id<MTLDevice>)device {
  if (self = [super init]) {
    _device = device;
    _bilateralFilterProcessor = [[LITBilateralFilter alloc] initWithDevice:device];
    _colorConversionProcessor = [[LITColorConversion alloc] initWithDevice:device];
    _quadCopyProcessor = [[LITQuadCopy alloc] initWithDevice:device];
  }
  return self;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)sourceTexture
           destinationTexture:(id<MTLTexture>)destinationTexture
    bilateralFilterRangeSigma:(float)bilateralFilterRangeSigma {
  LTParameterAssert(sourceTexture.pixelFormat == MTLPixelFormatBGRA8Unorm ||
                    sourceTexture.pixelFormat == MTLPixelFormatRGBA8Unorm, @"Source texture %@ must"
                    "have pixel format MTLPixelFormatBGRA8Unorm or MTLPixelFormatRGBA8Unorm",
                    sourceTexture);
  LTParameterAssert(destinationTexture.pixelFormat == MTLPixelFormatBGRA8Unorm ||
                    destinationTexture.pixelFormat == MTLPixelFormatRGBA8Unorm, @"Destination"
                    "texture %@ must have pixel format MTLPixelFormatBGRA8Unorm or"
                    "MTLPixelFormatRGBA8Unorm", destinationTexture);

  auto size = MTLSizeMake(destinationTexture.width, destinationTexture.height, 3);
  auto resizedImage = [MPSTemporaryImage mtb_unorm8TemporaryImageWithCommandBuffer:commandBuffer
                                                                              size:size];
  [self encodeResizeToCommandBuffer:commandBuffer sourceTexture:sourceTexture
                   destinationImage:resizedImage];

  auto bilateralFilterImage = [MPSTemporaryImage
                               mtb_unorm8TemporaryImageWithCommandBuffer:commandBuffer size:size];
  [self encodeBilateralFilterToCommandBuffer:commandBuffer sourceImage:resizedImage
                            destinationImage:bilateralFilterImage
                   bilateralFilterRangeSigma:bilateralFilterRangeSigma];
  resizedImage.readCount = 0;

  [self encodeRGB2HSVToCommandBuffer:commandBuffer sourceImage:bilateralFilterImage
                  destinationTexture:destinationTexture];
  bilateralFilterImage.readCount = 0;
}

- (void)encodeResizeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                      sourceTexture:(id<MTLTexture>)sourceTexture
                   destinationImage:(MPSTemporaryImage *)destinationImage {
  [self.quadCopyProcessor encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture
                             destinationTexture:destinationImage.texture];
}

- (void)encodeBilateralFilterToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                 sourceImage:(MPSTemporaryImage *)sourceImage
                            destinationImage:(MPSTemporaryImage *)destinationImage
                   bilateralFilterRangeSigma:(float)bilateralFilterRangeSigma {
 [self.bilateralFilterProcessor encodeToCommandBuffer:commandBuffer
                                        sourceTexture:sourceImage.texture
                                         guideTexture:sourceImage.texture iterations:1
                                           rangeSigma:bilateralFilterRangeSigma
                                 useFastApproximation:YES
                                   destinationTexture:destinationImage.texture];
}

- (void)encodeRGB2HSVToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                         sourceImage:(MPSTemporaryImage *)sourceImage
                  destinationTexture:(id<MTLTexture>)destinationTexture {
  [self.colorConversionProcessor encodeToCommandBuffer:commandBuffer
                                         sourceTexture:sourceImage.texture
                                    colorTransformType:LITColorTransformTypeRGBAToHSV
                                    destinationTexture:destinationTexture];
}

@end

NS_ASSUME_NONNULL_END
