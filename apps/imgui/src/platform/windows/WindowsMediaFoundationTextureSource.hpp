#pragma once

#include <string>

struct ID3D11Device;
struct ID3D11Texture2D;

namespace makelab::imgui::platform::win32 {

struct WindowsSourceTextureResult {
  bool accepted = false;
  ID3D11Texture2D* texture = nullptr;
  int width = 0;
  int height = 0;
  std::string diagnostic;
};

class WindowsMediaFoundationTextureSource {
 public:
  explicit WindowsMediaFoundationTextureSource(ID3D11Device* device);

  WindowsSourceTextureResult DecodeVideoFrameToTexture(const std::wstring& path, double seconds);
  WindowsSourceTextureResult DecodeImageToTexture(const std::wstring& path);

 private:
  ID3D11Device* device_ = nullptr;
};

}  // namespace makelab::imgui::platform::win32
