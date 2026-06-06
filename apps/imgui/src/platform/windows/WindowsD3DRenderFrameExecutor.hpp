#pragma once

#include <cstdint>
#include <string>

#include "render/PlatformRenderContracts.hpp"

struct ID3D11Device;
struct ID3D11DeviceContext;
struct ID3D11Texture2D;

namespace makelab::imgui::platform::win32 {

struct WindowsFinalFrameSurfaceResult {
  makelab::render::FinalFrameSurfaceStatus status = makelab::render::FinalFrameSurfaceStatus::Rejected;
  int64_t frameIndex = 0;
  uint64_t generation = 0;
  ID3D11Texture2D* texture = nullptr;
  int width = 0;
  int height = 0;
  std::string diagnostic;

  bool accepted() const {
    return status == makelab::render::FinalFrameSurfaceStatus::Accepted;
  }
};

class WindowsD3DRenderFrameExecutor {
 public:
  WindowsD3DRenderFrameExecutor(ID3D11Device* device, ID3D11DeviceContext* context);

  WindowsFinalFrameSurfaceResult RenderFrame(const makelab::model::WorkspaceViewState* workspace,
                                             int64_t frameIndex,
                                             uint64_t requestGeneration,
                                             bool waitForCompletion);

  WindowsFinalFrameSurfaceResult RenderFrame(const makelab::render::FinalFrameSurfaceRequest& request);

  const std::string& Status() const { return status_; }

 private:
  ID3D11Device* device_ = nullptr;
  ID3D11DeviceContext* context_ = nullptr;
  std::string status_;
};

}  // namespace makelab::imgui::platform::win32
