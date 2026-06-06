#include "platform/windows/WindowsExportExecutor.hpp"

namespace makelab::imgui::platform::win32 {

WindowsExportResult WindowsExportExecutor::ExportFromFinalFrameSurface(const makelab::model::WorkspaceViewState* workspace,
                                                                       const std::wstring& destinationPath) {
  (void)destinationPath;
  WindowsExportResult result;
  if (!workspace || !workspace->opened) {
    result.diagnostic = "Windows export rejected: no accepted workspace from Gates.";
    return result;
  }
  result.diagnostic = "Windows export rejected: Media Foundation encoder is not connected to FinalFrameSurface yet.";
  return result;
}

}  // namespace makelab::imgui::platform::win32
