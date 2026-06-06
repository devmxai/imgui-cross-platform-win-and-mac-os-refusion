#pragma once

#include <string>

namespace makelab::imgui::platform::win32 {

class WindowsProjectWatcher {
 public:
  bool Start(const std::wstring& folder);
  void Stop();
  bool PollChanged();
  const std::string& Diagnostic() const { return diagnostic_; }

 private:
  std::string diagnostic_ = "Windows project watcher is not started.";
};

}  // namespace makelab::imgui::platform::win32
