// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITMattingColorEstimationProcessor.h"

#import "LITImageValidator.h"
#import "LITMattingColorEstimation.metal.h"
#import "LITQuadCopy.h"

NS_ASSUME_NONNULL_BEGIN

LITMattingColorEstimationProcessorConfiguration
    LITMattingColorEstimationProcessorConfigurationDefault(void) {
  return {
    .numberOfIterationsForSmallScales = 10,
    .numberOfIterationsForLargeScales = 2,
    .smallScalesThreshold = 32
  };
}

@interface LITMattingColorEstimationProcessor ()

/// Device to encode this kernel operation.
@property (readonly, nonatomic) id<MTLDevice> device;

/// Compiled state of kernel for background and foreground update step.
@property (readonly, nonatomic) id<MTLComputePipelineState> updateStepState;

/// Compiled state of kernel for nearest neighbor resizing.
@property (readonly, nonatomic) id<MTLComputePipelineState> resizeState;

@end

@implementation LITMattingColorEstimationProcessor

- (instancetype)initWithDevice:(id<MTLDevice>)device {
  if (self = [super init]) {
     _device = device;
    auto updateStepFunctionName = @"foregroundAndBackgroundUpdateStep";
    _updateStepState = [LITComputeStateFactory computeStateWithDevice:device
                                                         functionName:updateStepFunctionName];
    _resizeState = [LITComputeStateFactory computeStateWithDevice:device
                                                     functionName:@"nearestNeighborResize"];
   }
   return self;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)sourceTexture alpha:(id<MTLTexture>)alpha
        destinationForeground:(nullable id<MTLTexture>)destinationForeground
        destinationBackground:(nullable id<MTLTexture>)destinationBackground {
  [self encodeToCommandBuffer:commandBuffer sourceTexture:sourceTexture alpha:alpha
        destinationForeground:destinationForeground destinationBackground:destinationBackground
                configuration:LITMattingColorEstimationProcessorConfigurationDefault()];
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)sourceTexture alpha:(id<MTLTexture>)alpha
        destinationForeground:(nullable id<MTLTexture>)destinationForeground
        destinationBackground:(nullable id<MTLTexture>)destinationBackground
                configuration:(LITMattingColorEstimationProcessorConfiguration)configuration {
  [self validateImage:sourceTexture alpha:alpha foreground:destinationForeground
           background:destinationBackground];

  auto pyramidScales = [self pyramidScalesWithWidth:(int)sourceTexture.width
                                             height:(int)sourceTexture.height];

  std::vector<MPSTemporaryImage *> imageScales;
  [self encodeRescaleToCommandBuffer:commandBuffer texture:sourceTexture scales:pyramidScales
                        outputImages:&imageScales];
  std::vector<MPSTemporaryImage *> alphaScales;
  [self encodeRescaleToCommandBuffer:commandBuffer texture:alpha scales:pyramidScales
                        outputImages:&alphaScales];

  [self encodeToCommandBuffer:commandBuffer imageScales:imageScales alphaScales:alphaScales
             outputBackground:destinationBackground outputForeground:destinationForeground
                pyramidScales:pyramidScales configuration:configuration];
}

- (void)validateImage:(id<MTLTexture>)image alpha:(id<MTLTexture>)alpha
           foreground:(nullable id<MTLTexture>)foreground
           background:(nullable id<MTLTexture>)background {
  const auto kPixelFormat = {
    MTLPixelFormatBGRA8Unorm, MTLPixelFormatRGBA8Unorm, MTLPixelFormatBGRA8Unorm_sRGB,
    MTLPixelFormatRGBA8Unorm_sRGB
  };
  [LITImageValidator validateTexture:image forPixelFormats:kPixelFormat];

  [[LITImageValidator validateTexture:alpha forPixelFormats:{MTLPixelFormatR8Unorm}]
     validateTexture:alpha  forSameSizeAsTexture:image];

  if (background) {
    [[LITImageValidator validateTexture:nn(background) forPixelFormats:kPixelFormat]
        validateTexture:nn(background)  forSameSizeAsTexture:image];
  }

  if (foreground) {
    [[LITImageValidator validateTexture:nn(foreground) forPixelFormats:kPixelFormat]
        validateTexture:nn(foreground)  forSameSizeAsTexture:image];
  }

  LTParameterAssert(foreground || background,
                    @"Either foreground texture or the background texture must be non null");
}

- (std::vector<MTLSize>)pyramidScalesWithWidth:(int)width height:(int)height {
  int numPyramidLevels =  std::ceil(std::log2(std::max(width, height)));
  std::vector<MTLSize> scales;
  for (int level = 1; level <= numPyramidLevels; level++) {
    scales.push_back(MTLSizeMake(pow(width, ((float)level / numPyramidLevels)),
                                 pow(height, ((float)level / numPyramidLevels)), 3));
  }
  return scales;
}

- (void)encodeRescaleToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                             texture:(id<MTLTexture>)texture
                              scales:(const std::vector<MTLSize> &)scales
                        outputImages:(std::vector<MPSTemporaryImage *> *)outputImages {
  auto inputImage = [MPSImage mtb_imageWithTexture:texture];
  (*outputImages).reserve(scales.size());
  std::transform(scales.begin(), scales.end(), std::back_inserter(*outputImages),
                 [&](MTLSize scale) -> MPSTemporaryImage * {
    return [self encodeResizeToCommandBuffer:commandBuffer image:inputImage outputSize:scale];
  });
}

- (MPSTemporaryImage *)encodeResizeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                             image:(nullable MPSImage *)image
                                        outputSize:(MTLSize)outputSize {
  auto resizedImage = [MPSTemporaryImage mtb_unorm8TemporaryImageWithCommandBuffer:commandBuffer
                                                                              size:outputSize];

  auto encoder = [[MTBComputeCommandEncoder encoderWithCommandBuffer:commandBuffer
                                                               state:self.resizeState]
      outputImage:resizedImage atIndex:TextureIndex::ResizeDestination];
  if (image) {
    encoder = [encoder inputImage:nn(image) atIndex:TextureIndex::ResizeSource];
  }
  [[encoder dispatchThreadsWithInputSize:MTLSizeMake(outputSize.width, outputSize.height, 1)]
      endEncoding];

  return resizedImage;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  imageScales:(const std::vector<MPSTemporaryImage *> &)imageScales
                  alphaScales:(const std::vector<MPSTemporaryImage *> &)alphaScales
             outputBackground:(nullable id<MTLTexture>)outputBackground
             outputForeground:(nullable id<MTLTexture>)outputForeground
                pyramidScales:(const std::vector<MTLSize > &)pyramidScales
                configuration:(LITMattingColorEstimationProcessorConfiguration)configuration {
  MPSTemporaryImage *prevBackground = nil;
  MPSTemporaryImage *prevForeground = nil;

  for (int i = 0; i < (int)pyramidScales.size(); i++) {
    auto background = [self encodeResizeToCommandBuffer:commandBuffer image:prevBackground
                                             outputSize:pyramidScales[i]];
    auto foreground = [self encodeResizeToCommandBuffer:commandBuffer image:prevForeground
                                             outputSize:pyramidScales[i]];

    auto temporaryBackground =
        [MPSTemporaryImage mtb_unorm8TemporaryImageWithCommandBuffer:commandBuffer
                                                                size:pyramidScales[i]];
    auto temporaryForeground =
        [MPSTemporaryImage mtb_unorm8TemporaryImageWithCommandBuffer:commandBuffer
                                                                size:pyramidScales[i]];

    int numIterations = [self numberOfIterationForScale:pyramidScales[i]
                                          configuration:configuration];
    imageScales[i].readCount = numIterations;
    alphaScales[i].readCount = numIterations;
    background.readCount = 1 + numIterations / 2;
    foreground.readCount = 1 + numIterations / 2;
    temporaryBackground.readCount = std::ceil((float)numIterations / 2);
    temporaryForeground.readCount = std::ceil((float)numIterations / 2);

    for (int iteration = 0; iteration < numIterations; iteration++) {
      id<MTLTexture> currentIterationBackgroundOutput = temporaryBackground.texture;
      id<MTLTexture> currentIterationForegroundOutput = temporaryForeground.texture;
      auto isLastIteration = (i == (int)pyramidScales.size() - 1 && iteration == numIterations - 1);
      if (isLastIteration) {
        currentIterationBackgroundOutput = outputBackground;
        currentIterationForegroundOutput = outputForeground;
      }
      [[[[[[[[[MTBComputeCommandEncoder encoderWithCommandBuffer:commandBuffer
                                                           state:self.updateStepState]
          inputImage:imageScales[i] atIndex:TextureIndex::Image]
          inputImage:alphaScales[i] atIndex:TextureIndex::Alpha]
          inputImage:foreground atIndex:TextureIndex::InputForeground]
          inputImage:background atIndex:TextureIndex::InputBackground]
          texture:currentIterationForegroundOutput atIndex:TextureIndex::OutputForeground]
          texture:currentIterationBackgroundOutput atIndex:TextureIndex::OutputBackground]
          dispatchThreadsWithInputSize:MTLSizeMake(pyramidScales[i].width,
                                                  pyramidScales[i].height , 1)]
          endEncoding];
      std::swap(background, temporaryBackground);
      std::swap(foreground, temporaryForeground);
    }
    prevForeground = foreground;
    prevBackground = background;
  }

  prevBackground.readCount -= 1;
  prevForeground.readCount -= 1;
}

- (int)numberOfIterationForScale:(MTLSize)scale
                   configuration:(LITMattingColorEstimationProcessorConfiguration)configuration {
  if ((int)scale.width <= configuration.smallScalesThreshold &&
      (int)scale.height <= configuration.smallScalesThreshold) {
    return configuration.numberOfIterationsForSmallScales;
  } else {
    return configuration.numberOfIterationsForLargeScales;
  }
}

@end

NS_ASSUME_NONNULL_END
