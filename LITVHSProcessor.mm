// Copyright (c) 2022 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITVHSProcessor.h"
#import "LITVHSProcessor.metal.h"

#import <MetalToolbox/MPSTemporaryImage+Factory.h>

#import "LITChromaticAberrationUtils.h"
#import "LITQuadCopy.h"
#import "LITQuadRenderer.h"
#import "MTBDevice+Lithography.h"

NS_ASSUME_NONNULL_BEGIN

// Returns value of a piecewise linear function for x in the range [0, 1],
// where: f(0) = 0, f(1) = 1, f(intervalX) = intervalY.
static float LITPiecewiseLinearFunction(float x, float intervalX, float intervalY) {
  if (x <= intervalX) {
    return x / intervalX * intervalY;
  }
  return (x - intervalX) / (1 - intervalX) * (1 - intervalY) + intervalY;
}

static float LITSharpenGaussianSigma(float intensity) {
  static const CGFloat kCoarseGaussianFactorSharpen = 0.0012;
  return intensity * kCoarseGaussianFactorSharpen;
}

static const float kIntensityVHSStep = 0.7;
static float LITVHSGaussianSigma(float intensity) {
  static const CGFloat kCoarseGaussianFactorVHS = 0.0024;
  auto highPassRadius = LITPiecewiseLinearFunction(intensity, kIntensityVHSStep, 0.8);
  return highPassRadius * kCoarseGaussianFactorVHS;
}

static VHSParameters LITCreateVHSParameters(float intensity, CGSize size) {
  static const CGFloat kBlurRadiusFactor = 0.00078;
  auto blurRadius = LITPiecewiseLinearFunction(intensity, kIntensityVHSStep, 0.5);
  float blurIntensity = blurRadius * kBlurRadiusFactor * std::max(size.width, size.height);

  auto highPassIntensity = LITPiecewiseLinearFunction(intensity, kIntensityVHSStep, 0.8);

  static const float kMaxDispersion = 0.06;
  auto dispersionDistance = LITDispersionDistance(kMaxDispersion * intensity, 0, 0);

  return {
    .originalIntensity = intensity,
    .blurIntensity = blurIntensity,
    .highPassIntensity = highPassIntensity,
    .dispersionDistance = dispersionDistance
  };
}

static const MTLTextureUsage kTextureUsage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

@interface LITVHSProcessor()

/// Device used for rendering.
@property (readonly, nonatomic) MTBDevice *device;

/// Adjust pipeline state.
@property (readonly, nonatomic) id<MTLRenderPipelineState> pipelineState;

/// Renderer used to render the VHS effect.
@property (readonly, nonatomic) LITQuadRenderer *quadRenderer;

/// Processor used to resize texture.
@property (readonly, nonatomic) LITQuadCopy *quadCopy;
@end

@implementation LITVHSProcessor

- (instancetype)initWithDevice:(MTBDevice *)device pixelFormat:(MTLPixelFormat)pixelFormat {
  if (self = [super init]) {
    _device = device;

    auto fragmentFunction = [[device lit_library]
                             newFunctionWithName:@"vhsFragmentShader"];
    LTAssert(fragmentFunction, @"Failed to get fragment function vhsFragmentShader");

    _quadRenderer = [[LITQuadRenderer alloc] initWithDevice:device pixelFormat:pixelFormat
                                           fragmentFunction:fragmentFunction];
    _quadCopy = [[LITQuadCopy alloc] initWithDevice:device];
  }
  return self;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                 inputTexture:(id<MTLTexture>)inputTexture
                outputTexture:(id<MTLTexture>)outputTexture
             sharpenIntensity:(CGFloat)sharpenIntensity
                 vhsIntensity:(CGFloat)vhsIntensity {
  [self encodeToCommandBuffer:commandBuffer inputTexture:inputTexture outputTexture:outputTexture
                         quad:LITQuadFromCGSize(mtb(inputTexture).mtb_cgSize)
             sharpenIntensity:sharpenIntensity vhsIntensity:vhsIntensity];
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                 inputTexture:(id<MTLTexture>)inputTexture
                outputTexture:(id<MTLTexture>)outputTexture
                         quad:(LITQuad)quad
             sharpenIntensity:(CGFloat)sharpenIntensity
                 vhsIntensity:(CGFloat)vhsIntensity {
  auto blurred = [self encodeDownsampleWithCommandBuffer:commandBuffer texture:mtb(inputTexture)
                                         reductionFactor:2];
  auto doubleBlurred = [self encodeDownsampleWithCommandBuffer:commandBuffer
                                                       texture:mtb(blurred.texture)
                                               reductionFactor:2];

  MPSTemporaryImage *coarseGaussianSharpen = nil, *coarseGaussianVHS = nil;
  if (sharpenIntensity > 0) {
    coarseGaussianSharpen = [self coarseGaussianTexture:doubleBlurred
                                          gaussianSigma:LITSharpenGaussianSigma(sharpenIntensity)
                                          commandBuffer:commandBuffer];
  }
  if (vhsIntensity > 0) {
    coarseGaussianVHS = [self coarseGaussianTexture:doubleBlurred
                                      gaussianSigma:LITVHSGaussianSigma(vhsIntensity)
                                      commandBuffer:commandBuffer];
  }

  auto vhsParams = LITCreateVHSParameters(vhsIntensity, mtb(inputTexture).mtb_cgSize);

  auto normalizedQuad = [self normalizedQuad:quad width:inputTexture.width
                                      height:inputTexture.height];
  auto quadToStandardSquare = LITQuadToStandardSquareHomography(normalizedQuad);
  auto renderPassDescriptor = [self.class renderPassDescriptorWithTexture:mtb(outputTexture)];
  auto encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
  [self.quadRenderer encodeToCommandEncoder:encoder fragmentSetUpBlock:^{
    [encoder setFragmentTexture:inputTexture atIndex:TextureIndex::SourceTexture];
    [encoder setFragmentTexture:blurred.texture atIndex:TextureIndex::BlurredTexture];

    [encoder setFragmentTexture:coarseGaussianSharpen.texture
                        atIndex:TextureIndex::CoarseGaussianTextureSharpen];
    [encoder setFragmentTexture:coarseGaussianVHS.texture
                        atIndex:TextureIndex::CoarseGaussianTextureVHS];

    [encoder setFragmentBytes:&quadToStandardSquare length:sizeof(quadToStandardSquare)
                      atIndex:BufferIndex::QuadToStandardSquare];
    float sharpenIntensityFloat = sharpenIntensity;
    [encoder setFragmentBytes:&sharpenIntensityFloat length:sizeof(float)
                      atIndex:BufferIndex::SharpenIntensity];
    [encoder setFragmentBytes:&vhsParams length:sizeof(vhsParams) atIndex:BufferIndex::VHSParams];
  }];
  [encoder endEncoding];
  blurred.readCount = 0;
  doubleBlurred.readCount = 0;
  coarseGaussianSharpen.readCount = 0;
  coarseGaussianVHS.readCount = 0;
}

+ (MTLRenderPassDescriptor *)renderPassDescriptorWithTexture:(MTBTexture *)texture {
  auto descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  descriptor.colorAttachments[0].texture = texture;
  descriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
  descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
  return descriptor;
}

- (MPSTemporaryImage *)encodeDownsampleWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                                 texture:(MTBTexture *)texture
                                         reductionFactor:(int)reductionFactor {
  auto downsampledSize = std::ceil(texture.mtb_cgSize / reductionFactor);
  auto downsampledTexture = [MPSTemporaryImage
                             mtb_temporaryImageWithCommandBuffer:commandBuffer
                             width:downsampledSize.width height:downsampledSize.height
                             pixelFormat:texture.pixelFormat usage:kTextureUsage];
  [self.quadCopy encodeToCommandBuffer:commandBuffer sourceTexture:texture
                    destinationTexture:downsampledTexture.texture];
  return downsampledTexture;
}

- (MPSTemporaryImage *)coarseGaussianTexture:(MPSTemporaryImage *)texture
                               gaussianSigma:(float)gaussianSigma
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
  auto destination = [MPSTemporaryImage mtb_temporaryImageWithCommandBuffer:commandBuffer
                                                                      width:texture.width
                                                                     height:texture.height
                                                                pixelFormat:texture.pixelFormat
                                                                      usage:kTextureUsage];

  CGFloat sigma = gaussianSigma * std::max(texture.width, texture.height);
  auto gaussianProcessor = [[MPSImageGaussianBlur alloc] initWithDevice:self.device
                                                                  sigma:sigma];
  gaussianProcessor.edgeMode = MPSImageEdgeModeClamp;
  [gaussianProcessor encodeToCommandBuffer:commandBuffer sourceTexture:texture.texture
                        destinationTexture:destination.texture];
  return destination;
}

- (LITQuad)normalizedQuad:(LITQuad)quad width:(unsigned long)width height:(unsigned long)height {
  return LITQuadMake(CGPointMake(quad.v0.x / width, quad.v0.y / height),
                     CGPointMake(quad.v1.x / width, quad.v1.y / height),
                     CGPointMake(quad.v2.x / width, quad.v2.y / height),
                     CGPointMake(quad.v3.x / width, quad.v3.y / height));
}

@end

NS_ASSUME_NONNULL_END
