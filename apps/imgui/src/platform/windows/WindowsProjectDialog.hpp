#pragma once

#include <string>

#include <windef.h>

namespace makelab::imgui::platform::win32 {

struct WindowsDialogResult {
  bool accepted = false;
  std::wstring path;
  std::string diagnostic;
};

WindowsDialogResult OpenProjectFolder(HWND owner);
WindowsDialogResult ChooseImportMediaFile(HWND owner);
WindowsDialogResult ChooseExportFile(HWND owner);

}  // namespace makelab::imgui::platform::win32
