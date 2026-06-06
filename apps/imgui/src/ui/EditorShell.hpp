#pragma once

#include <array>
#include <string>

#include "model/WorkspaceModel.hpp"
#include "timeline/TimelineTruth.hpp"

namespace makelab::imgui {

enum class LibrarySection {
  Media,
  Text,
  Audio,
  Background,
  Shapes,
};

using AssetItem = makelab::model::AssetItem;
using ClipItem = makelab::model::ClipItem;
using TrackItem = makelab::model::TrackItem;
using WorkspaceViewState = makelab::model::WorkspaceViewState;

struct EditorShellConfig {
  struct LiveScopeSnapshot {
    bool ready = false;
    int64_t frameIndex = 0;
    float averageR = 0.0f;
    float averageG = 0.0f;
    float averageB = 0.0f;
    float lumaMin = 0.0f;
    float lumaMax = 0.0f;
    std::array<float, 16> lumaBuckets{};
  };

  struct PerformanceTelemetry {
    bool ready = false;
    double renderSubmitMs = 0.0;
    double liveScopeReadbackMs = 0.0;
    double frameBudgetMs = 0.0;
    double finalSurfaceMegabytes = 0.0;
    int64_t requestedFrameIndex = 0;
    int64_t acceptedFrameIndex = 0;
    uint64_t requestGeneration = 0;
  };

  struct ExportProgress {
    bool inFlight = false;
    double progress = 0.0;
    const char* phase = "";
    const char* destination = "";
  };

  bool designFixture = false;
  bool finalFrameSurfaceReady = false;
  void* finalFrameSurfaceTexture = nullptr;
  void* iconFont = nullptr;
  int finalFrameSurfaceWidth = 0;
  int finalFrameSurfaceHeight = 0;
  int64_t requestedFrameIndex = 0;
  int64_t acceptedFrameIndex = 0;
  int64_t durationFrames = 0;
  makelab::timeline::FrameRate frameRate;
  double playbackTimeSeconds = 0.0;
  double durationSeconds = 0.0;
  LiveScopeSnapshot liveScope;
  PerformanceTelemetry telemetry;
  ExportProgress exportProgress;
  LibrarySection librarySection = LibrarySection::Media;
  const char* diagnostic = "Preview blocked: FinalFrameSurface is not connected.";
  const WorkspaceViewState* workspace = nullptr;
};

struct EditorShellResult {
  std::string command;
  std::string payload;
  int64_t timelineFrameIndex = 0;
};

EditorShellResult DrawEditorShell(const EditorShellConfig& config);

}  // namespace makelab::imgui
