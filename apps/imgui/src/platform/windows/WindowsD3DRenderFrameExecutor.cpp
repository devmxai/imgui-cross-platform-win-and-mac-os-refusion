#include "platform/windows/WindowsD3DRenderFrameExecutor.hpp"

namespace makelab::imgui::platform::win32 {

WindowsD3DRenderFrameExecutor::WindowsD3DRenderFrameExecutor(ID3D11Device* device,
                                                             ID3D11DeviceContext* context)
    : device_(device), context_(context) {
  status_ = "WindowsD3DRenderFrameExecutor created. FinalFrameSurface execution is not connected yet.";
}

WindowsFinalFrameSurfaceResult WindowsD3DRenderFrameExecutor::RenderFrame(
    const makelab::model::WorkspaceViewState* workspace,
    int64_t frameIndex,
    uint64_t requestGeneration,
    bool waitForCompletion) {
  makelab::render::FinalFrameSurfaceRequest request;
  request.workspace = workspace;
  request.frameIndex = frameIndex;
  request.requestGeneration = requestGeneration;
  request.waitForCompletion = waitForCompletion;
  request.intent = makelab::render::NativeRenderIntent::PausedPreview;
  return RenderFrame(request);
}

WindowsFinalFrameSurfaceResult WindowsD3DRenderFrameExecutor::RenderFrame(
    const makelab::render::FinalFrameSurfaceRequest& request) {
  WindowsFinalFrameSurfaceResult result;
  result.frameIndex = request.frameIndex;
  result.generation = request.requestGeneration;

  if (!device_ || !context_) {
    result.diagnostic = "WindowsD3DRenderFrameExecutor rejected: D3D device/context is unavailable.";
    status_ = result.diagnostic;
    return result;
  }
  if (!request.workspace || !request.workspace->opened) {
    result.diagnostic = "WindowsD3DRenderFrameExecutor rejected: no accepted workspace from Gates.";
    status_ = result.diagnostic;
    return result;
  }

  result.diagnostic =
      "WindowsD3DRenderFrameExecutor rejected: RenderGraph/FXPassGraph D3D execution is not implemented yet.";
  status_ = result.diagnostic;
  return result;
}

}  // namespace makelab::imgui::platform::win32
