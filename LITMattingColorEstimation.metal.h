// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

/// Textures used by kernels of Matting Color Estimation Processor.
enum TextureIndex {
  /// Resize source texture.
   ResizeSource,
   /// Resize destination texture.
   ResizeDestination,
  /// Image texture of update step.
  Image,
  /// Alpha texture of update step.
  Alpha,
  /// Input background of update step.
  InputBackground,
  /// Output background of update step.
  OutputBackground,
  /// Input foreground of update step.
  InputForeground,
  /// Output foreground of update step.
  OutputForeground
};
