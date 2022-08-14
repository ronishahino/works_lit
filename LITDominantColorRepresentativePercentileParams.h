// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

NS_ASSUME_NONNULL_BEGIN

/// Structure stores configuration parameters for calculating the representative value from a set of
/// color samples.
/// For each set of color samples to be represented by a single value, a representative color is
/// chosen such that it's hue, saturation and value fields are these given percentiles among all
/// values in the set of color samples.
typedef struct {
   /// The percentile for the hue value of the representative.
   /// For example, if the value of this parameter is 0.8 the hue value of each cluster's
   /// representative is the minimal number such that 80% of the colors in this cluster have a lower
   /// hue.
   /// This parameter gets values in range [0, 1].
   float huePercentileRepresentative;

   /// The percentile for the saturation value of the representative.
   /// For example, if the value of this parameter is 0.8 the saturation value of each cluster's
   /// representative is the minimal number such that 80% of the colors in this cluster have a lower
   /// saturation.
   /// This parameter gets values in range [0, 1].
   float saturationPercentileRepresentative;

   /// The percentile for the value channel of the representative.
   /// For example, if the value of this parameter is 0.8 the value of the value channel of each
   /// cluster's representative is the minimal number such that 80% of the colors in this cluster
   /// have a lower value in the value channel.
   /// This parameter gets values in range [0, 1].
   float valuePercentileRepresentative;
} LITDominantColorRepresentativePercentileParams;

LT_C_DECLS_BEGIN

/// Creates LITDominantColorRepresentativePercentileParams.
LITDominantColorRepresentativePercentileParams
    LITDominantColorRepresentativePercentileParamsMake(float huePercentileRepresentative,
                                                       float saturationPercentileRepresentative,
                                                       float valuePercentileRepresentative);

LT_C_DECLS_END

NS_ASSUME_NONNULL_END
