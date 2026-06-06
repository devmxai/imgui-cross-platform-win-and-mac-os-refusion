#include "platform/windows/WindowsProjectDialog.hpp"

#include <shobjidl.h>
#include <windows.h>

#include <cstdio>

namespace makelab::imgui::platform::win32 {
namespace {

std::string HResultMessage(const char* operation, HRESULT hr) {
  char buffer[160];
  std::snprintf(buffer, sizeof(buffer), "%s failed: HRESULT 0x%08lX.", operation, static_cast<unsigned long>(hr));
  return buffer;
}

WindowsDialogResult PickPath(HWND owner, bool folder, bool save, const wchar_t* title) {
  WindowsDialogResult result;
  IFileDialog* dialog = nullptr;
  const HRESULT createHr = CoCreateInstance(save ? CLSID_FileSaveDialog : CLSID_FileOpenDialog,
                                           nullptr,
                                           CLSCTX_INPROC_SERVER,
                                           IID_PPV_ARGS(&dialog));
  if (FAILED(createHr) || !dialog) {
    result.diagnostic = HResultMessage("IFileDialog creation", createHr);
    return result;
  }

  DWORD options = 0;
  dialog->GetOptions(&options);
  if (folder) {
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
  } else {
    dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_OVERWRITEPROMPT);
  }
  if (title) {
    dialog->SetTitle(title);
  }

  const HRESULT showHr = dialog->Show(owner);
  if (showHr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    result.diagnostic = "Windows native dialog cancelled.";
    dialog->Release();
    return result;
  }
  if (FAILED(showHr)) {
    result.diagnostic = HResultMessage("IFileDialog show", showHr);
    dialog->Release();
    return result;
  }

  IShellItem* item = nullptr;
  const HRESULT itemHr = dialog->GetResult(&item);
  if (FAILED(itemHr) || !item) {
    result.diagnostic = HResultMessage("IFileDialog result", itemHr);
    dialog->Release();
    return result;
  }

  PWSTR widePath = nullptr;
  const HRESULT pathHr = item->GetDisplayName(SIGDN_FILESYSPATH, &widePath);
  if (FAILED(pathHr) || !widePath) {
    result.diagnostic = HResultMessage("IFileDialog path", pathHr);
    item->Release();
    dialog->Release();
    return result;
  }

  result.accepted = true;
  result.path = widePath;
  CoTaskMemFree(widePath);
  item->Release();
  dialog->Release();
  return result;
}

}  // namespace

WindowsDialogResult OpenProjectFolder(HWND owner) {
  return PickPath(owner, true, false, L"Open Makelab Project Folder");
}

WindowsDialogResult ChooseImportMediaFile(HWND owner) {
  return PickPath(owner, false, false, L"Import Media Into Accepted Project");
}

WindowsDialogResult ChooseExportFile(HWND owner) {
  return PickPath(owner, false, true, L"Export FinalFrameSurface MP4");
}

}  // namespace makelab::imgui::platform::win32
