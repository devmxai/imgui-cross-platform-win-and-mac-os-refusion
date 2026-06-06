#pragma once

#include <string>

#include "model/WorkspaceModel.hpp"

namespace makelab::imgui::platform::win32 {

struct WindowsExportResult {
  bool accepted = false;
  std::string diagnostic;
};

class WindowsExportExecutor {
 public:
  WindowsExportResult ExportFromFinalFrameSurface(const makelab::model::WorkspaceViewState* workspace,
                                                  const std::wstring& destinationPath);
};

}  // namespace makelab::imgui::platform::win32
