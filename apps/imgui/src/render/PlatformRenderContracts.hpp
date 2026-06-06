#pragma once

#include <cstdint>
#include <string>

#include "model/WorkspaceModel.hpp"

namespace makelab::render {

enum class FinalFrameSurfaceStatus {
  Accepted,
  Preserved,
  Rejected,
};

enum class NativeRenderIntent {
  PausedPreview,
  PlaybackRealtime,
  ScrubInteractive,
  ExportFrame,
};

struct FinalFrameSurfaceRequest {
  const makelab::model::WorkspaceViewState* workspace = nullptr;
  int64_t frameIndex = 0;
  uint64_t requestGeneration = 0;
  bool allowPreserve = true;
  bool waitForCompletion = false;
  NativeRenderIntent intent = NativeRenderIntent::PausedPreview;
};

struct FinalFrameSurfaceResultBase {
  FinalFrameSurfaceStatus status = FinalFrameSurfaceStatus::Rejected;
  uint64_t requestGeneration = 0;
  int64_t requestedFrameIndex = 0;
  int64_t surfaceFrameIndex = -1;
  int width = 0;
  int height = 0;
  std::string diagnostic;

  bool accepted() const {
    return status == FinalFrameSurfaceStatus::Accepted;
  }
};

struct PlatformRenderCapability {
  bool nativeDeviceReady = false;
  bool sourceTextureDecodeReady = false;
  bool finalFrameSurfaceReady = false;
  std::string backendName;
  std::string diagnostic;
};

}  // namespace makelab::render
