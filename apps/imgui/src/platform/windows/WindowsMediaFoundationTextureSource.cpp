#include "platform/windows/WindowsMediaFoundationTextureSource.hpp"

namespace makelab::imgui::platform::win32 {

WindowsMediaFoundationTextureSource::WindowsMediaFoundationTextureSource(ID3D11Device* device) : device_(device) {}

WindowsSourceTextureResult WindowsMediaFoundationTextureSource::DecodeVideoFrameToTexture(const std::wstring& path,
                                                                                         double seconds) {
  (void)path;
  (void)seconds;
  WindowsSourceTextureResult result;
  result.diagnostic =
      device_ ? "Media Foundation D3D source texture decode is not implemented yet."
              : "Media Foundation D3D source texture decode rejected: D3D device is unavailable.";
  return result;
}

WindowsSourceTextureResult WindowsMediaFoundationTextureSource::DecodeImageToTexture(const std::wstring& path) {
  (void)path;
  WindowsSourceTextureResult result;
  result.diagnostic =
      device_ ? "Windows image source texture decode is not implemented yet."
              : "Windows image source texture decode rejected: D3D device is unavailable.";
  return result;
}

}  // namespace makelab::imgui::platform::win32
