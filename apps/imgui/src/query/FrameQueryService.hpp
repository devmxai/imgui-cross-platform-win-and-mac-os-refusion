#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "ui/EditorShell.hpp"

namespace makelab::query {

struct CanvasViewTransform {
  double scale = 1.0;
  double offsetX = 0.0;
  double offsetY = 0.0;
  int compositionWidth = 0;
  int compositionHeight = 0;
  int viewportWidth = 0;
  int viewportHeight = 0;
};

struct Point {
  double x = 0.0;
  double y = 0.0;
};

struct EvaluatedLayer {
  std::string clipId;
  std::string trackId;
  std::string layerType;
  std::string name;
  std::string assetId;
  std::string textContent;
  std::string shapeKind;
  int zIndex = 0;
  int64_t startFrame = 0;
  int64_t durationFrames = 0;
  double localTimeSeconds = 0.0;
  double mediaTimeSeconds = 0.0;
  double x = 0.0;
  double y = 0.0;
  double width = 0.0;
  double height = 0.0;
  double anchorX = 0.5;
  double anchorY = 0.5;
  double opacity = 1.0;
  double rotationDegrees = 0.0;
  double scaleX = 1.0;
  double scaleY = 1.0;
  double cornerRadius = 0.0;
  bool borderEnabled = false;
  bool shadowEnabled = false;
  std::vector<std::string> effects;
};

struct FrameQueryResult {
  int64_t frameIndex = 0;
  double timeSeconds = 0.0;
  int compositionWidth = 0;
  int compositionHeight = 0;
  std::vector<EvaluatedLayer> layers;
  std::vector<std::string> diagnostics;
};

CanvasViewTransform CreateCanvasViewTransform(int compositionWidth,
                                              int compositionHeight,
                                              int viewportWidth,
                                              int viewportHeight);

Point CompositionToViewport(const CanvasViewTransform& transform, Point compositionPoint);
Point ViewportToComposition(const CanvasViewTransform& transform, Point viewportPoint);

FrameQueryResult QueryFrame(const imgui::WorkspaceViewState& workspace, int64_t frameIndex);
const EvaluatedLayer* QueryLayerAtPixel(const FrameQueryResult& frame, double compositionX, double compositionY);
uint64_t FrameTruthFingerprint(const FrameQueryResult& frame);

}  // namespace makelab::query
