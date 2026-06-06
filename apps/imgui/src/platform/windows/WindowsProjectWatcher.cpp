#include "platform/windows/WindowsProjectWatcher.hpp"

namespace makelab::imgui::platform::win32 {

bool WindowsProjectWatcher::Start(const std::wstring& folder) {
  (void)folder;
  diagnostic_ = "ReadDirectoryChangesW project watcher is not implemented yet.";
  return false;
}

void WindowsProjectWatcher::Stop() {
  diagnostic_ = "Windows project watcher stopped.";
}

bool WindowsProjectWatcher::PollChanged() {
  return false;
}

}  // namespace makelab::imgui::platform::win32
