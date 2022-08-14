// Copyright (c) 2022 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITVHSProcessor.h"

#import <MetalToolbox/MTBDevice.h>

SpecBegin(LITVHSProcessor)

it(@"should perform vhs effect", ^{
  auto device = nn(MTLCreateSystemDefaultDevice());
  auto processor = [[LITVHSProcessor alloc] initWithDevice:device
                                               pixelFormat:MTLPixelFormatRGBA8Unorm];

  auto inputMat = LTLoadMat([self class], @"batia_640.jpg");
  auto input = [mtb(device) mtb_newTextureWithContentOfMat:inputMat
      pixelFormat:MTLPixelFormatRGBA8Unorm
      usage:MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget];

  auto output = [mtb(device) mtb_newTextureWithPropertiesOfTexture:mtb(input)];

  auto commandBuffer = [[device newCommandQueue] commandBuffer];
  [processor encodeToCommandBuffer:mtb(commandBuffer) inputTexture:mtb(input)
                     outputTexture:mtb(output) sharpenIntensity:0.0 vhsIntensity:1.0];

  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  auto outputMat = PNKMatFromMTLTexture(output);
  auto expectedMat = LTLoadMat([self class], @"VHS_output.png");
  expect($(outputMat)).to.beCloseToMatPSNR($(expectedMat), 48);
});

it(@"should perform sharpen effect", ^{
  auto device = nn(MTLCreateSystemDefaultDevice());
  auto processor = [[LITVHSProcessor alloc] initWithDevice:device
                                               pixelFormat:MTLPixelFormatRGBA8Unorm];

  auto inputMat = LTLoadMat([self class], @"batia_640.jpg");
  auto input = [mtb(device) mtb_newTextureWithContentOfMat:inputMat
      pixelFormat:MTLPixelFormatRGBA8Unorm
      usage:MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget];

  auto output = [mtb(device) mtb_newTextureWithPropertiesOfTexture:mtb(input)];

  auto commandBuffer = [[device newCommandQueue] commandBuffer];
  [processor encodeToCommandBuffer:mtb(commandBuffer) inputTexture:mtb(input)
                     outputTexture:mtb(output) sharpenIntensity:1.0 vhsIntensity:0.0];

  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  auto outputMat = PNKMatFromMTLTexture(output);
  auto expectedMat = LTLoadMat([self class], @"sharpen_output.png");
  expect($(outputMat)).to.beCloseToMatPSNR($(expectedMat), 50);
});

it(@"should perform sharpen and vhs effect", ^{
  auto device = nn(MTLCreateSystemDefaultDevice());
  auto processor = [[LITVHSProcessor alloc] initWithDevice:device
                                               pixelFormat:MTLPixelFormatRGBA8Unorm];

  auto inputMat = LTLoadMat([self class], @"batia_640.jpg");
  auto input = [mtb(device) mtb_newTextureWithContentOfMat:inputMat
      pixelFormat:MTLPixelFormatRGBA8Unorm
      usage:MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget];

  auto output = [mtb(device) mtb_newTextureWithPropertiesOfTexture:mtb(input)];

  auto commandBuffer = [[device newCommandQueue] commandBuffer];
  [processor encodeToCommandBuffer:mtb(commandBuffer) inputTexture:mtb(input)
                     outputTexture:mtb(output) sharpenIntensity:0.9 vhsIntensity:0.7];

  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  auto outputMat = PNKMatFromMTLTexture(output);
  auto expectedMat = LTLoadMat([self class], @"sharpen_and_vhs_output.png");
  expect($(outputMat)).to.beCloseToMatPSNR($(expectedMat), 50);
});

SpecEnd
