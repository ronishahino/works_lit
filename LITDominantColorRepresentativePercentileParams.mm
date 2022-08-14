// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorRepresentativePercentileParams.h"

NS_ASSUME_NONNULL_BEGIN

LITDominantColorRepresentativePercentileParams
    LITDominantColorRepresentativePercentileParamsMake(float huePercentileRepresentative,
                                                       float saturationPercentileRepresentative,
                                                       float valuePercentileRepresentative) {
    LTParameterAssert(huePercentileRepresentative <= 1 && huePercentileRepresentative >= 0,
                      @"representativePercentile of hue channel must be in range [0, 1]");
    LTParameterAssert(saturationPercentileRepresentative <= 1 &&
                      saturationPercentileRepresentative >= 0,
                      @"representativePercentile of saturation channel must be in range [0, 1]");
    LTParameterAssert(valuePercentileRepresentative <= 1 && valuePercentileRepresentative >= 0,
                      @"representativePercentile of value channel must be in range [0, 1]");
    return {
      .huePercentileRepresentative = huePercentileRepresentative,
      .saturationPercentileRepresentative = saturationPercentileRepresentative,
      .valuePercentileRepresentative = valuePercentileRepresentative
    };
}

NS_ASSUME_NONNULL_END
