// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColor.h"

NS_ASSUME_NONNULL_BEGIN

@implementation LITDominantColor

- (instancetype)initWithColor:(UIColor *)color score:(float)score {
  if (self = [super init]) {
    _color = color;
    _score = score;
  }
  return self;
}

@end

NS_ASSUME_NONNULL_END
