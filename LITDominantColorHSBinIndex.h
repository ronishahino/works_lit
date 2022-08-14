// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

NS_ASSUME_NONNULL_BEGIN

/// Structure stores a bin index in hue-saturation fields.
struct LITHSBinIndex {

  /// Index of the bin in hue field.
  int hueIndex;

  /// Index of the bin in saturation field.
  int saturationIndex;

  LITHSBinIndex (int hIndex, int sIndex) {
    hueIndex = hIndex;
    saturationIndex = sIndex;
  }
};

NS_ASSUME_NONNULL_END
