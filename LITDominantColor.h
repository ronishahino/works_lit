// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

NS_ASSUME_NONNULL_BEGIN

/// class represent a dominant color in an image.
@interface LITDominantColor : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Initializes with \c color and \c score.
- (instancetype)initWithColor:(UIColor *)color score:(float)score NS_DESIGNATED_INITIALIZER;

/// RGB value of the dominant color.
@property (readonly, nonatomic) UIColor *color;

/// Dominant color score in the range (0,1]. Higher scores mean more pixel colors in the image are
/// similar to the dominant color.
@property (readonly, nonatomic) float score;

@end

NS_ASSUME_NONNULL_END
