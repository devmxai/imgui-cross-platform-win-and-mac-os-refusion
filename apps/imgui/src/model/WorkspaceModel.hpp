#pragma once

#include <cstdint>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>

#include "timeline/TimelineTruth.hpp"

namespace makelab::model {

struct AssetItem {
  std::string id;
  std::string name;
  std::string type;
  std::string path;
  int width = 0;
  int height = 0;
  double durationSeconds = 0.0;
};

struct ClipItem {
  struct EffectItem {
    std::string id;
    std::string source;
    std::string kind;
    bool enabled = false;
    std::unordered_map<std::string, double> numbers;
    std::unordered_map<std::string, std::string> strings;
    double activeStartSeconds = 0.0;
    double activeEndSeconds = std::numeric_limits<double>::infinity();
  };

  struct AnimationFrame {
    std::string property;
    double time = 0.0;
    double value = 0.0;
    std::string easing = "easeOut";
  };

  std::string id;
  std::string name;
  std::string type;
  std::string trackId;
  std::string assetId;
  int64_t startFrame = 0;
  int64_t durationFrames = 0;
  double startSeconds = 0.0;
  double durationSeconds = 0.0;
  double trimInSeconds = 0.0;
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
  double skewXDegrees = 0.0;
  double skewYDegrees = 0.0;
  double cornerRadius = 0.0;
  double cornerRadiusTopLeft = 0.0;
  double cornerRadiusTopRight = 0.0;
  double cornerRadiusBottomRight = 0.0;
  double cornerRadiusBottomLeft = 0.0;
  bool borderEnabled = false;
  double borderWidth = 0.0;
  std::string borderColor = "#FFFFFF";
  double borderOpacity = 1.0;
  std::string borderPosition = "inside";
  bool shadowEnabled = false;
  double shadowX = 0.0;
  double shadowY = 0.0;
  double shadowBlur = 0.0;
  double shadowSpread = 0.0;
  std::string shadowColor = "#000000";
  double shadowOpacity = 1.0;
  double motionOutDuration = 0.0;
  std::string motionEasing = "easeOut";
  std::string fit = "cover";
  bool fillEnabled = false;
  std::string fillColor = "#FFFFFF";
  double fillOpacity = 1.0;
  std::string textContent;
  std::string textFontFamily = "SF Pro Display";
  double textFontSize = 48.0;
  std::string textFontWeight = "400";
  std::string textColor = "#FFFFFF";
  std::string textAlign = "center";
  double textLineHeight = 1.0;
  double textLetterSpacing = 0.0;
  std::string textStrokeColor = "#000000";
  double textStrokeWidth = 0.0;
  std::string shapeKind = "rectangle";
  std::vector<AnimationFrame> animationFrames;
  std::vector<EffectItem> effects;
  bool hasEffects = false;
};

struct TrackItem {
  std::string id;
  std::string name;
  std::string kind;
  bool hidden = false;
  bool muted = false;
  std::vector<ClipItem> clips;
};

struct WorkspaceViewState {
  bool opened = false;
  std::string folderName;
  std::string projectName;
  int width = 1080;
  int height = 1920;
  double fps = 30.0;
  makelab::timeline::FrameRate frameRate;
  int64_t durationFrames = 0;
  double durationSeconds = 0.0;
  std::string folderPath;
  std::vector<AssetItem> assets;
  std::vector<TrackItem> tracks;
  std::vector<std::string> diagnostics;
};

}  // namespace makelab::model
