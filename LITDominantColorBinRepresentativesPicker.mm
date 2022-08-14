// Copyright (c) 2020 Lightricks. All rights reserved.
// Created by Roni Shahino.

#import "LITDominantColorBinRepresentativesPicker.h"

#import <queue>

#import "LITDominantColorUtilities.h"

using namespace lit_dominant_color;

NS_ASSUME_NONNULL_BEGIN

/// Structure stores DBScan point status. Indicating whether the point is noise and whether it has
/// already been visited.
struct LITDBScanPoint {

  /// Gets true if the point is noise.
  bool isNoise;

  /// Gets true if the point has already been visited.
  bool visited;

  LITDBScanPoint() {
    visited = false;
  }
};

/// Structure stores the colors that DBScan cluster contains. This structure used to extract the
/// cluster representative.
struct LITDBScanCluster {

  /// The cluster colors in HSV color space.
  cv::Mat3b clusterColors;

  /// Number of color instances for each color.
  std::vector<int> clusterColorRepetitions;

  /// The total instances of all colors in cluster.
  int totalClusterSize;

  /// Number of used elements in \c clusterColors and \c clusterColorRepetitions.
  int usedElements;
};

@interface LITDominantColorBinRepresentativesPicker ()

/// A list that contains all neighbors inside radius \c dbScanRadius of the origin point.
/// For each point P, its neighbors will be P + relativeNeighbor for each relativeNeighbor
/// in relativeNeighborList.
@property (nonatomic, readonly) std::vector<cv::Point3i> relativeNeighborList;

/// Bin width in hue filed field.
@property (nonatomic, readonly) int binHueWidth;

/// Bin width in saturation field.
@property (nonatomic, readonly) int binSaturationWidth;

/// LITDominantColorRepresentativesPicker configuration parameters.
@property (nonatomic, readonly) LITDominantColorRepresentativesPickerConfiguration configuration;

/// Parameters define how to extract a representative from a bin.
@property (nonatomic, readonly) LITDominantColorRepresentativePercentileParams
    representativePercentileParams;

@end

@implementation LITDominantColorBinRepresentativesPicker
- (instancetype)initWithBinHueWidth:(int)binHueWidth binSaturationWidth:(int)binSaturationWidth
     representativePercentileParams:
    (LITDominantColorRepresentativePercentileParams)representativePercentileParams
  representativePickerConfiguration:
    (LITDominantColorRepresentativesPickerConfiguration)representativePickerConfiguration {
  if (self = [super init]) {
    _binHueWidth = binHueWidth;
    _binSaturationWidth = binSaturationWidth;
    _representativePercentileParams = representativePercentileParams;
    _configuration = representativePickerConfiguration;

    _relativeNeighborList = [self calculateRelativeNeighbors];
  }
  return self;
};

- (std::vector<cv::Vec3b>)findRepresentativeColorsInBin:(const std::vector<cv::Vec3b> &)bin
                                              withIndex:(LITHSBinIndex)hsBinIndex
                                              histogram:(const cv::Mat1f &)histogram {
  auto representatives = [self findRepresentativesByDBScanInBin:bin withIndex:hsBinIndex
                                                      histogram:histogram];

  /// if not found any cluster in the bin with DBScan, create one cluster from all bin,
  /// and return its representative as the bin dominant color.
  if (representatives.empty()) {
    auto clusterRepresentative = representativeOfSlice(cv::Mat3b(bin), (int)bin.size(),
                                                       self.representativePercentileParams);
    representatives = {clusterRepresentative};
  }
  return representatives;
}

#pragma mark -
#pragma mark DBScan
#pragma mark -

- (std::vector<cv::Vec3b>)findRepresentativesByDBScanInBin:(const std::vector<cv::Vec3b> &)bin
                                                 withIndex:(LITHSBinIndex)hsBinIndex
                                                 histogram:(const cv::Mat1f &)globalHistogram {
  int binLocalHistogramSize = self.binHueWidth * self.binSaturationWidth * 256;
  std::vector<LITDBScanPoint> dbScanPoints;
  dbScanPoints.resize(binLocalHistogramSize);

  /// To improve performance, \c reusableCluster stores each cluster parameters, and use the same
  /// memory for all clusters in the bin. when preparing for new cluster treating it's content as
  /// garbage, and refill it with the new cluster content.
  LITDBScanCluster reusableCluster;
  int imageBinSize = (int)bin.size();
  auto largestOptionalClusterSize = std::min(imageBinSize, binLocalHistogramSize);
  reusableCluster.clusterColors = cv::Mat3b(largestOptionalClusterSize, 1);
  reusableCluster.clusterColorRepetitions.resize(largestOptionalClusterSize);

  std::vector<std::pair<cv::Vec3b,int>> clusterRepresentativeColorAndSizeList;
  for (auto &colorValue : bin) {
    if ([self isVisited:colorValue dbPoints:dbScanPoints]) {
      continue;
    }
    std::vector<cv::Vec3b> uniqueNeighborValues;
    auto numberOfNeighbors = [self neighborsCountOfPoint:colorValue inBinIndex:hsBinIndex
                                               histogram:globalHistogram
                             populateUniqueNeighborValue:&uniqueNeighborValues];
    if (numberOfNeighbors + 1 < self.configuration.dbScanMinNeighbors) {
      [self setAsNoise:colorValue dbPoints:&dbScanPoints];
      continue;
    }
    [self resetCluster:&reusableCluster];
    [self processPoints:&dbScanPoints startingAtCorePoint:colorValue
        withUniqueNeighborValues:uniqueNeighborValues populateCluster:&reusableCluster
        histogram:globalHistogram inBinIndex:hsBinIndex];
    auto hsv = [self representativeOfCluster:reusableCluster];
    clusterRepresentativeColorAndSizeList.push_back({hsv, reusableCluster.totalClusterSize});
  }
  auto representatives =
      [self sortRepresentativeColorByClusterSize:clusterRepresentativeColorAndSizeList];
  return representatives;
 }

- (unsigned int)neighborsCountOfPoint:(cv::Vec3b)point inBinIndex:(LITHSBinIndex)hsBinIndex
                            histogram:(cv::Mat1f)histogram
          populateUniqueNeighborValue:(std::vector<cv::Vec3b> *)uniqueNeighborValues {
   unsigned int numberOfNeighbors = 0;
   numberOfNeighbors += histogram(point(0), point(1), point(2)) - 1;

    for (auto &relativeNeighbor : self.relativeNeighborList) {
      auto neighbor = cv::Point3i(point) + relativeNeighbor;
      if (neighbor.x >= hsBinIndex.hueIndex * self.binHueWidth &&
          neighbor.x < (hsBinIndex.hueIndex + 1) * self.binHueWidth &&
          neighbor.y >= hsBinIndex.saturationIndex * self.binSaturationWidth &&
          neighbor.y < (hsBinIndex.saturationIndex + 1) * self.binSaturationWidth &&
          neighbor.z >= 0 && neighbor.z < 256) {
        auto neighborRepetitions = histogram(neighbor.x, neighbor.y, neighbor.z);
        if (neighborRepetitions > 0) {
          uniqueNeighborValues->push_back(cv::Vec3b(neighbor.x, neighbor.y, neighbor.z));
          numberOfNeighbors += neighborRepetitions;
        }
      }
    }
  return numberOfNeighbors;
}

- (void)processPoints:(std::vector<LITDBScanPoint> *)dbScanPoints
  startingAtCorePoint:(const cv::Vec3b &)startCorePoint
withUniqueNeighborValues:(const std::vector<cv::Vec3b> &)uniqueNeighborValues
      populateCluster:(LITDBScanCluster *)reusableCluster histogram:(const cv::Mat1f &)histogram
           inBinIndex:(LITHSBinIndex)hsBinIndex {
  /// \c LITDBScanCluster uses the point value as a color, while \c LITDBScanPoint uses the point
  /// value as an abstract point, indicating the point position in the histogram.
  [self addPoint:startCorePoint toDBPoints:dbScanPoints];
  [self addColor:startCorePoint toCluster:reusableCluster repetitions:histogram(startCorePoint(0),
                                                                                startCorePoint(1),
                                                                                startCorePoint(2))];
  std::queue<cv::Vec3b> clusterSet;
  for (auto &neighbor : uniqueNeighborValues) {
    clusterSet.push(neighbor);
  }
  while (!clusterSet.empty()) {
    auto point = clusterSet.front();
    clusterSet.pop();
    if ([self isVisited:point dbPoints:*dbScanPoints]) {
      if ([self isNoise:point dbPoints:*dbScanPoints]) {
         [self addPoint:point toDBPoints:dbScanPoints];
         [self addColor:point toCluster:reusableCluster repetitions:histogram(point(0),point(1),
                                                                                       point(2))];
      }
      continue;
    }

   [self addPoint:point toDBPoints:dbScanPoints];
   [self addColor:point toCluster:reusableCluster repetitions:histogram(point(0),point(1),
                                                                        point(2))];
   std::vector<cv::Vec3b> uniqueNeighborValues;
   auto numberOfNeighbors = [self neighborsCountOfPoint:point inBinIndex:hsBinIndex
                                              histogram:histogram
                            populateUniqueNeighborValue:&uniqueNeighborValues];
    if (numberOfNeighbors + 1 < self.configuration.dbScanMinNeighbors) {
      continue;
    }
    for (auto &neighbor : uniqueNeighborValues) {
      clusterSet.push(neighbor);
    }
  }
}

- (std::vector<cv::Vec3b>)sortRepresentativeColorByClusterSize:
    (std::vector<std::pair<cv::Vec3b,int>>)clusterRepresentativeColorAndSizeList {
  auto compare = [](const std::pair<cv::Vec3b,int> &a, const std::pair<cv::Vec3b,int> &b) {
   return a.second >  b.second;
  };
  std::sort(clusterRepresentativeColorAndSizeList.begin(),
            clusterRepresentativeColorAndSizeList.end(), compare);

  std::vector<cv::Vec3b> sortedRepresentatives;
  for (auto &[color, size] : clusterRepresentativeColorAndSizeList) {
    sortedRepresentatives.push_back(color);
  }
  return sortedRepresentatives;
}

#pragma mark -
#pragma mark LITDBScanPoint
#pragma mark -

- (bool)isVisited:(const cv::Vec3b &)point dbPoints:(const std::vector<LITDBScanPoint> &)dbPoints {
  auto relativeOffset = [self offsetOfPointInDBScanPointList:point];
  return dbPoints[relativeOffset].visited;
}

- (bool)isNoise:(const cv::Vec3b &)point dbPoints:(const std::vector<LITDBScanPoint> &)dbPoints {
  auto relativeOffset = [self offsetOfPointInDBScanPointList:point];
  return dbPoints[relativeOffset].isNoise;
}

- (void)setAsNoise:(const cv::Vec3b &)point dbPoints:(std::vector<LITDBScanPoint> *)dbPoints {
  auto relativeOffset = [self offsetOfPointInDBScanPointList:point];
  (*dbPoints)[relativeOffset].isNoise = true;
  (*dbPoints)[relativeOffset].visited = true;
}

- (void)addPoint:(const cv::Vec3b &)point toDBPoints:(std::vector<LITDBScanPoint> *)dbPoints {
  auto relativeOffset = [self offsetOfPointInDBScanPointList:point];
  (*dbPoints)[relativeOffset].isNoise = false;
  (*dbPoints)[relativeOffset].visited = true;
}

- (int)offsetOfPointInDBScanPointList:(const cv::Vec3b &)point {
  cv::Vec3b relativePoint(point(0) % self.binHueWidth,
                          point(1) % self.binSaturationWidth,
                          point(2));
  return 256 * self.binSaturationWidth * relativePoint(0) + 256 * relativePoint(1)
      + relativePoint(2);
}

#pragma mark -
#pragma mark Cluster Handling
#pragma mark -

- (void)resetCluster:(LITDBScanCluster *)cluster {
  cluster->totalClusterSize = 0;
  cluster->usedElements = 0;
}

- (void)addColor:(const cv::Vec3b &)color toCluster:(LITDBScanCluster *)cluster
     repetitions:(int)repetitions {
  auto indexToInsert = (*cluster).usedElements;
  (*cluster).clusterColors(indexToInsert, 0) = color;
  (*cluster).clusterColorRepetitions[indexToInsert] = repetitions;
  (*cluster).totalClusterSize += repetitions;
  (*cluster).usedElements += 1;
}

- (cv::Vec3b)representativeOfCluster:(LITDBScanCluster)cluster {
  auto usedClusterColors = cluster.clusterColors.rowRange(0, cluster.usedElements);
 return representativeOfSlice(usedClusterColors, cluster.totalClusterSize,
                              self.representativePercentileParams, cluster.clusterColorRepetitions);
}

#pragma mark -
#pragma mark Neighbor Index Initialization
#pragma mark -

- (std::vector<cv::Point3i>)calculateRelativeNeighbors {
  std::vector<cv::Point3i> relativeNeighbors;
  auto firstOctantNeighbors = [self calculateRelativeNeighborsForFirstOctant];
  for (auto &firstOctantNeighbor : firstOctantNeighbors) {
    auto allOctantsNeighbors = [self reflectFirstOctantsToAllOctants:firstOctantNeighbor];
    relativeNeighbors.insert(relativeNeighbors.end(), allOctantsNeighbors.begin(),
                             allOctantsNeighbors.end());
  }
  return relativeNeighbors;
}

- (std::vector<cv::Point3i>)calculateRelativeNeighborsForFirstOctant {
  std::vector<cv::Point3i> originPoint = {cv::Point3i(0,0,0)};
  auto expandedNeighborsInXAxis = [self expandNeighbors:originPoint inAxis:0];
  auto expandedNeighborsInXYAxis = [self expandNeighbors:expandedNeighborsInXAxis inAxis:1];
  auto expandedNeighborsInXYZAxis = [self expandNeighbors:expandedNeighborsInXYAxis inAxis:2];

  // delete the first point which is (0,0,0), namely the original point. which is not a neighbor
  // of itself.
  expandedNeighborsInXYZAxis.erase(expandedNeighborsInXYZAxis.begin());
  return expandedNeighborsInXYZAxis;
}

- (std::vector<cv::Point3i>)reflectFirstOctantsToAllOctants:(cv::Point3i)firstOctantNeighbor {
  std::vector<cv::Point3i> reflectedNeighbors;
  for (int i = -1 ; i <= 1; i += 2) {
    if (firstOctantNeighbor.x == 0 && i == 1) {
      continue;
    }
    for (int j = -1 ; j <= 1; j += 2) {
      if (firstOctantNeighbor.y == 0 && j == 1) {
        continue;
      }
      for (int k = -1 ; k <= 1; k += 2) {
        if (firstOctantNeighbor.z == 0 && k == 1) {
          continue;
        }
        cv::Point3i reflectedNeighbor(i * firstOctantNeighbor.x, j * firstOctantNeighbor.y,
                                      k * firstOctantNeighbor.z);
        reflectedNeighbors.push_back(reflectedNeighbor);
      }
    }
  }
  return reflectedNeighbors;
}

- (std::vector<cv::Point3i>)expandNeighbors:(const std::vector<cv::Point3i> &)originNeighbors
                                     inAxis:(int)axis {
  std::vector<cv::Point3i> neighborsExpandedInAxis;
  for (auto &originNeighbor: originNeighbors) {
    for (int i = 0; i < 256 ; i++) {
      auto candidateNeighbor = [self shiftPoint:originNeighbor by:i axis:axis];
      if ([self minkowskiDistanceFromOrigin:candidateNeighbor] > self.configuration.dbScanRadius) {
        break;
      }
      neighborsExpandedInAxis.push_back(candidateNeighbor);
    }
  }
  return neighborsExpandedInAxis;
}

- (cv::Point3i)shiftPoint:(cv::Point3i)point by:(int)shift axis:(int)axis {
  cv::Point3i shiftedPoint = point;
  switch (axis) {
   case 0:
     shiftedPoint.x += shift;
     break;
   case 1:
     shiftedPoint.y += shift;
     break;
   case 2:
     shiftedPoint.z += shift;
     break;
   default:
      LTParameterAssert(NO, @"Shift point must get axis less than or equals to 2, got %d", axis);
   }
  return shiftedPoint;
}

- (double)minkowskiDistanceFromOrigin:(cv::Point3i)point {
  auto pointDouble = cv::Point3d(point) / 255.0;

  auto dist = std::pow(std::abs((pointDouble.x)*self.configuration.dbScanPointMultipliers[0]), 3) +
              std::pow(std::abs((pointDouble.y)*self.configuration.dbScanPointMultipliers[1]), 3) +
              std::pow(std::abs((pointDouble.z)*self.configuration.dbScanPointMultipliers[2]), 3);
  dist = std::cbrt(dist);
  return dist;
}

@end

NS_ASSUME_NONNULL_END
