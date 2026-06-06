#include "query/FrameQueryService.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <string>

namespace makelab::query {
namespace {

double Clamp01(double value, double fallback = 0.0) {
  const double next = std::isfinite(value) ? value : fallback;
  return std::clamp(next, 0.0, 1.0);
}

double CubicBezierCoordinate(double t, double p1, double p2) {
  const double c = 3.0 * p1;
  const double b = 3.0 * (p2 - p1) - c;
  const double a = 1.0 - c - b;
  return ((a * t + b) * t + c) * t;
}

double CubicBezierDerivative(double t, double p1, double p2) {
  const double c = 3.0 * p1;
  const double b = 3.0 * (p2 - p1) - c;
  const double a = 1.0 - c - b;
  return (3.0 * a * t + 2.0 * b) * t + c;
}

bool ParseCubicBezier(const std::string& easing, double& x1, double& y1, double& x2, double& y2) {
  return std::sscanf(easing.c_str(), "cubic-bezier(%lf,%lf,%lf,%lf)", &x1, &y1, &x2, &y2) == 4 ||
         std::sscanf(easing.c_str(), "cubic-bezier(%lf, %lf, %lf, %lf)", &x1, &y1, &x2, &y2) == 4;
}

double CubicBezierEasedProgress(double x, double x1, double y1, double x2, double y2) {
  const double target = Clamp01(x, 0.0);
  x1 = std::clamp(x1, 0.0, 1.0);
  x2 = std::clamp(x2, 0.0, 1.0);
  double t = target;
  for (int i = 0; i < 8; ++i) {
    const double current = CubicBezierCoordinate(t, x1, x2) - target;
    const double derivative = CubicBezierDerivative(t, x1, x2);
    if (std::abs(current) < 0.000001 || std::abs(derivative) < 0.000001) {
      break;
    }
    t = std::clamp(t - current / derivative, 0.0, 1.0);
  }
  double low = 0.0;
  double high = 1.0;
  for (int i = 0; i < 8; ++i) {
    const double current = CubicBezierCoordinate(t, x1, x2);
    if (std::abs(current - target) < 0.000001) {
      break;
    }
    if (current < target) {
      low = t;
    } else {
      high = t;
    }
    t = (low + high) * 0.5;
  }
  return CubicBezierCoordinate(t, y1, y2);
}

double EasedProgress(double value, const std::string& easing) {
  const double t = Clamp01(value, 0.0);
  if (easing == "linear") return t;
  double x1 = 0.0;
  double y1 = 0.0;
  double x2 = 1.0;
  double y2 = 1.0;
  if (ParseCubicBezier(easing, x1, y1, x2, y2)) {
    return CubicBezierEasedProgress(t, x1, y1, x2, y2);
  }
  if (easing == "easeIn" || easing == "easeInCubic") return t * t * t;
  if (easing == "easeOut" || easing == "easeOutCubic") return 1.0 - std::pow(1.0 - t, 3.0);
  if (easing == "easeInQuad") return t * t;
  if (easing == "easeOutQuad") return 1.0 - (1.0 - t) * (1.0 - t);
  if (easing == "easeInOutQuad") {
    return t < 0.5 ? 2.0 * t * t : 1.0 - std::pow(-2.0 * t + 2.0, 2.0) / 2.0;
  }
  if (easing == "easeInQuart") return t * t * t * t;
  if (easing == "easeOutQuart") return 1.0 - std::pow(1.0 - t, 4.0);
  if (easing == "easeInOutQuart") {
    return t < 0.5 ? 8.0 * t * t * t * t : 1.0 - std::pow(-2.0 * t + 2.0, 4.0) / 2.0;
  }
  if (easing == "easeInOut" || easing == "cubic-bezier(0.42, 0, 0.58, 1)") {
    return t < 0.5 ? 2.0 * t * t : 1.0 - std::pow(-2.0 * t + 2.0, 2.0) / 2.0;
  }
  if (easing == "easeOutBack" || easing == "backOut") {
    const double c1 = 1.70158;
    const double c3 = c1 + 1.0;
    return 1.0 + c3 * std::pow(t - 1.0, 3.0) + c1 * std::pow(t - 1.0, 2.0);
  }
  return 1.0 - std::pow(1.0 - t, 3.0);
}

double AnimatedValue(const std::vector<model::ClipItem::AnimationFrame>& frames,
                     const std::string& property,
                     double localTime,
                     double fallback) {
  std::vector<model::ClipItem::AnimationFrame> propertyFrames;
  for (const auto& frame : frames) {
    if (frame.property == property && std::isfinite(frame.time) && std::isfinite(frame.value)) {
      propertyFrames.push_back(frame);
    }
  }
  if (propertyFrames.empty()) {
    return fallback;
  }
  std::sort(propertyFrames.begin(), propertyFrames.end(), [](const auto& left, const auto& right) {
    return left.time < right.time;
  });
  if (localTime <= propertyFrames.front().time) {
    return propertyFrames.front().value;
  }
  for (size_t index = 1; index < propertyFrames.size(); ++index) {
    const auto& previous = propertyFrames[index - 1];
    const auto& next = propertyFrames[index];
    if (localTime <= next.time) {
      const double span = std::max(0.000001, next.time - previous.time);
      const double progress = EasedProgress((localTime - previous.time) / span, next.easing);
      return previous.value + (next.value - previous.value) * progress;
    }
  }
  return propertyFrames.back().value;
}

EvaluatedLayer EvaluateClip(const model::WorkspaceViewState& workspace,
                            const model::TrackItem& track,
                            const model::ClipItem& clip,
                            int zIndex,
                            int64_t frameIndex) {
  EvaluatedLayer layer;
  layer.clipId = clip.id;
  layer.trackId = track.id;
  layer.layerType = clip.type.empty() ? track.kind : clip.type;
  layer.name = clip.name.empty() ? clip.id : clip.name;
  layer.assetId = clip.assetId;
  layer.textContent = clip.textContent;
  layer.shapeKind = clip.shapeKind;
  layer.zIndex = zIndex;
  layer.startFrame = clip.startFrame;
  layer.durationFrames = clip.durationFrames;
  layer.localTimeSeconds = timeline::FrameToSeconds({frameIndex - clip.startFrame}, workspace.frameRate);
  layer.mediaTimeSeconds = std::max(0.0, layer.localTimeSeconds + clip.trimInSeconds);
  layer.width = clip.width > 0.0 ? clip.width : workspace.width;
  layer.height = clip.height > 0.0 ? clip.height : workspace.height;
  layer.anchorX = clip.anchorX;
  layer.anchorY = clip.anchorY;
  layer.x = (clip.width > 0.0 || clip.height > 0.0) ? clip.x : 0.0;
  layer.y = (clip.width > 0.0 || clip.height > 0.0) ? clip.y : 0.0;
  layer.opacity = Clamp01(clip.opacity, 1.0);
  layer.rotationDegrees = clip.rotationDegrees;
  layer.scaleX = clip.scaleX == 0.0 ? 1.0 : clip.scaleX;
  layer.scaleY = clip.scaleY == 0.0 ? 1.0 : clip.scaleY;
  layer.cornerRadius = std::max(0.0, clip.cornerRadius);
  layer.borderEnabled = clip.borderEnabled;
  layer.shadowEnabled = clip.shadowEnabled;

  const double animatedX = AnimatedValue(clip.animationFrames, "x", layer.localTimeSeconds, std::numeric_limits<double>::quiet_NaN());
  const double animatedY = AnimatedValue(clip.animationFrames, "y", layer.localTimeSeconds, std::numeric_limits<double>::quiet_NaN());
  const double animatedPositionX = AnimatedValue(clip.animationFrames, "positionX", layer.localTimeSeconds, std::numeric_limits<double>::quiet_NaN());
  const double animatedPositionY = AnimatedValue(clip.animationFrames, "positionY", layer.localTimeSeconds, std::numeric_limits<double>::quiet_NaN());
  const double animatedCenterX = AnimatedValue(clip.animationFrames, "centerX", layer.localTimeSeconds, std::numeric_limits<double>::quiet_NaN());
  const double animatedCenterY = AnimatedValue(clip.animationFrames, "centerY", layer.localTimeSeconds, std::numeric_limits<double>::quiet_NaN());
  const double translateX = AnimatedValue(clip.animationFrames, "translateX", layer.localTimeSeconds, 0.0);
  const double translateY = AnimatedValue(clip.animationFrames, "translateY", layer.localTimeSeconds, 0.0);
  const double opacity = AnimatedValue(clip.animationFrames, "opacity", layer.localTimeSeconds, layer.opacity);
  const double scale = AnimatedValue(clip.animationFrames, "scale", layer.localTimeSeconds, 1.0);
  const double scaleX = AnimatedValue(clip.animationFrames, "scaleX", layer.localTimeSeconds, scale);
  const double scaleY = AnimatedValue(clip.animationFrames, "scaleY", layer.localTimeSeconds, scale);
  const double rotation = AnimatedValue(clip.animationFrames, "rotation", layer.localTimeSeconds, 0.0);
  const double cornerRadius = AnimatedValue(clip.animationFrames, "cornerRadius", layer.localTimeSeconds, layer.cornerRadius);

  if (std::isfinite(animatedX)) {
    layer.x = animatedX;
  } else if (std::isfinite(animatedPositionX)) {
    layer.x = animatedPositionX - layer.width * layer.anchorX;
  }
  if (std::isfinite(animatedY)) {
    layer.y = animatedY;
  } else if (std::isfinite(animatedPositionY)) {
    layer.y = animatedPositionY - layer.height * layer.anchorY;
  }
  if (std::isfinite(animatedCenterX)) {
    layer.x = animatedCenterX - layer.width * 0.5;
  }
  if (std::isfinite(animatedCenterY)) {
    layer.y = animatedCenterY - layer.height * 0.5;
  }
  layer.x += translateX;
  layer.y += translateY;
  layer.opacity = Clamp01(opacity, layer.opacity);
  layer.scaleX *= scaleX;
  layer.scaleY *= scaleY;
  layer.rotationDegrees += rotation;
  layer.cornerRadius = std::max(0.0, cornerRadius);

  if (layer.layerType == "background" || track.kind == "background") {
    layer.x = 0.0;
    layer.y = 0.0;
    layer.width = workspace.width;
    layer.height = workspace.height;
    layer.anchorX = 0.0;
    layer.anchorY = 0.0;
  }

  for (const auto& effect : clip.effects) {
    if (effect.enabled) {
      layer.effects.push_back(effect.kind.empty() ? effect.source : effect.kind);
    }
  }
  return layer;
}

bool ContainsPixel(const EvaluatedLayer& layer, double compositionX, double compositionY) {
  const double centerX = layer.x + layer.width * layer.anchorX;
  const double centerY = layer.y + layer.height * layer.anchorY;
  const double radians = -layer.rotationDegrees * M_PI / 180.0;
  const double cosR = std::cos(radians);
  const double sinR = std::sin(radians);
  const double dx = compositionX - centerX;
  const double dy = compositionY - centerY;
  const double localX = (dx * cosR - dy * sinR) / (layer.scaleX == 0.0 ? 1.0 : layer.scaleX);
  const double localY = (dx * sinR + dy * cosR) / (layer.scaleY == 0.0 ? 1.0 : layer.scaleY);
  const double left = -layer.width * layer.anchorX;
  const double right = layer.width * (1.0 - layer.anchorX);
  const double top = -layer.height * layer.anchorY;
  const double bottom = layer.height * (1.0 - layer.anchorY);
  return localX >= left && localX <= right && localY >= top && localY <= bottom;
}

void HashByte(uint64_t& hash, uint8_t value) {
  hash ^= value;
  hash *= 1099511628211ULL;
}

void HashString(uint64_t& hash, const std::string& value) {
  for (unsigned char character : value) {
    HashByte(hash, character);
  }
  HashByte(hash, 0xff);
}

void HashInteger(uint64_t& hash, int64_t value) {
  for (int shift = 0; shift < 64; shift += 8) {
    HashByte(hash, static_cast<uint8_t>((static_cast<uint64_t>(value) >> shift) & 0xff));
  }
}

void HashDouble(uint64_t& hash, double value) {
  const int64_t quantized = static_cast<int64_t>(std::llround((std::isfinite(value) ? value : 0.0) * 1000000.0));
  HashInteger(hash, quantized);
}

}  // namespace

CanvasViewTransform CreateCanvasViewTransform(int compositionWidth,
                                              int compositionHeight,
                                              int viewportWidth,
                                              int viewportHeight) {
  CanvasViewTransform transform;
  transform.compositionWidth = std::max(1, compositionWidth);
  transform.compositionHeight = std::max(1, compositionHeight);
  transform.viewportWidth = std::max(1, viewportWidth);
  transform.viewportHeight = std::max(1, viewportHeight);
  const double scaleX = static_cast<double>(transform.viewportWidth) / static_cast<double>(transform.compositionWidth);
  const double scaleY = static_cast<double>(transform.viewportHeight) / static_cast<double>(transform.compositionHeight);
  transform.scale = std::min(scaleX, scaleY);
  transform.offsetX = (static_cast<double>(transform.viewportWidth) - static_cast<double>(transform.compositionWidth) * transform.scale) * 0.5;
  transform.offsetY = (static_cast<double>(transform.viewportHeight) - static_cast<double>(transform.compositionHeight) * transform.scale) * 0.5;
  return transform;
}

Point CompositionToViewport(const CanvasViewTransform& transform, Point compositionPoint) {
  return {
      transform.offsetX + compositionPoint.x * transform.scale,
      transform.offsetY + compositionPoint.y * transform.scale,
  };
}

Point ViewportToComposition(const CanvasViewTransform& transform, Point viewportPoint) {
  const double scale = transform.scale == 0.0 ? 1.0 : transform.scale;
  return {
      (viewportPoint.x - transform.offsetX) / scale,
      (viewportPoint.y - transform.offsetY) / scale,
  };
}

FrameQueryResult QueryFrame(const model::WorkspaceViewState& workspace, int64_t frameIndex) {
  FrameQueryResult result;
  result.frameIndex = timeline::ClampFrame(frameIndex, std::max<int64_t>(1, workspace.durationFrames));
  result.timeSeconds = timeline::FrameToSeconds({result.frameIndex}, workspace.frameRate);
  result.compositionWidth = workspace.width;
  result.compositionHeight = workspace.height;
  if (!workspace.opened) {
    result.diagnostics.push_back("queryFrame rejected: workspace is not opened by UnitedGate.");
    return result;
  }

  const int trackCount = static_cast<int>(workspace.tracks.size());
  for (int trackIndex = 0; trackIndex < trackCount; ++trackIndex) {
    const auto& track = workspace.tracks[trackIndex];
    if (track.hidden) {
      continue;
    }
    for (const auto& clip : track.clips) {
      if (clip.durationFrames <= 0 || clip.startFrame < 0) {
        result.diagnostics.push_back("queryFrame skipped invalid clip timing: " + clip.id);
        continue;
      }
      if (result.frameIndex < clip.startFrame || result.frameIndex >= clip.startFrame + clip.durationFrames) {
        continue;
      }
      result.layers.push_back(EvaluateClip(workspace, track, clip, trackCount - trackIndex - 1, result.frameIndex));
    }
  }
  std::sort(result.layers.begin(), result.layers.end(), [](const auto& left, const auto& right) {
    return left.zIndex < right.zIndex;
  });
  return result;
}

const EvaluatedLayer* QueryLayerAtPixel(const FrameQueryResult& frame, double compositionX, double compositionY) {
  for (auto it = frame.layers.rbegin(); it != frame.layers.rend(); ++it) {
    if (ContainsPixel(*it, compositionX, compositionY)) {
      return &(*it);
    }
  }
  return nullptr;
}

uint64_t FrameTruthFingerprint(const FrameQueryResult& frame) {
  uint64_t hash = 1469598103934665603ULL;
  HashInteger(hash, frame.frameIndex);
  HashDouble(hash, frame.timeSeconds);
  HashInteger(hash, frame.compositionWidth);
  HashInteger(hash, frame.compositionHeight);
  HashInteger(hash, static_cast<int64_t>(frame.layers.size()));
  for (const auto& layer : frame.layers) {
    HashString(hash, layer.clipId);
    HashString(hash, layer.trackId);
    HashString(hash, layer.layerType);
    HashString(hash, layer.name);
    HashString(hash, layer.assetId);
    HashString(hash, layer.textContent);
    HashString(hash, layer.shapeKind);
    HashInteger(hash, layer.zIndex);
    HashInteger(hash, layer.startFrame);
    HashInteger(hash, layer.durationFrames);
    HashDouble(hash, layer.localTimeSeconds);
    HashDouble(hash, layer.mediaTimeSeconds);
    HashDouble(hash, layer.x);
    HashDouble(hash, layer.y);
    HashDouble(hash, layer.width);
    HashDouble(hash, layer.height);
    HashDouble(hash, layer.anchorX);
    HashDouble(hash, layer.anchorY);
    HashDouble(hash, layer.opacity);
    HashDouble(hash, layer.rotationDegrees);
    HashDouble(hash, layer.scaleX);
    HashDouble(hash, layer.scaleY);
    HashDouble(hash, layer.cornerRadius);
    HashInteger(hash, layer.borderEnabled ? 1 : 0);
    HashInteger(hash, layer.shadowEnabled ? 1 : 0);
    HashInteger(hash, static_cast<int64_t>(layer.effects.size()));
    for (const auto& effect : layer.effects) {
      HashString(hash, effect);
    }
  }
  return hash;
}

}  // namespace makelab::query
