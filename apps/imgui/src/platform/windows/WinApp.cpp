#include "imgui.h"
#include "imgui_impl_dx11.h"
#include "imgui_impl_win32.h"

#include "platform/windows/WindowsD3DRenderFrameExecutor.hpp"
#include "platform/windows/WindowsExportExecutor.hpp"
#include "platform/windows/WindowsProjectDialog.hpp"
#include "ui/EditorShell.hpp"

#include <d3d11.h>
#include <tchar.h>
#include <windows.h>

#include <memory>
#include <string>

extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

namespace {

ID3D11Device* gDevice = nullptr;
ID3D11DeviceContext* gDeviceContext = nullptr;
IDXGISwapChain* gSwapChain = nullptr;
ID3D11RenderTargetView* gRenderTargetView = nullptr;

void CreateRenderTarget() {
  ID3D11Texture2D* backBuffer = nullptr;
  gSwapChain->GetBuffer(0, IID_PPV_ARGS(&backBuffer));
  if (backBuffer) {
    gDevice->CreateRenderTargetView(backBuffer, nullptr, &gRenderTargetView);
    backBuffer->Release();
  }
}

void CleanupRenderTarget() {
  if (gRenderTargetView) {
    gRenderTargetView->Release();
    gRenderTargetView = nullptr;
  }
}

bool CreateDeviceD3D(HWND window) {
  DXGI_SWAP_CHAIN_DESC swapChainDesc = {};
  swapChainDesc.BufferCount = 2;
  swapChainDesc.BufferDesc.Width = 0;
  swapChainDesc.BufferDesc.Height = 0;
  swapChainDesc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  swapChainDesc.BufferDesc.RefreshRate.Numerator = 60;
  swapChainDesc.BufferDesc.RefreshRate.Denominator = 1;
  swapChainDesc.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
  swapChainDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  swapChainDesc.OutputWindow = window;
  swapChainDesc.SampleDesc.Count = 1;
  swapChainDesc.SampleDesc.Quality = 0;
  swapChainDesc.Windowed = TRUE;
  swapChainDesc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

  UINT createDeviceFlags = 0;
  D3D_FEATURE_LEVEL featureLevel = D3D_FEATURE_LEVEL_11_0;
  const D3D_FEATURE_LEVEL featureLevelArray[2] = {
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_0,
  };
  const HRESULT result = D3D11CreateDeviceAndSwapChain(nullptr,
                                                       D3D_DRIVER_TYPE_HARDWARE,
                                                       nullptr,
                                                       createDeviceFlags,
                                                       featureLevelArray,
                                                       2,
                                                       D3D11_SDK_VERSION,
                                                       &swapChainDesc,
                                                       &gSwapChain,
                                                       &gDevice,
                                                       &featureLevel,
                                                       &gDeviceContext);
  if (result != S_OK) {
    return false;
  }

  CreateRenderTarget();
  return true;
}

void CleanupDeviceD3D() {
  CleanupRenderTarget();
  if (gSwapChain) {
    gSwapChain->Release();
    gSwapChain = nullptr;
  }
  if (gDeviceContext) {
    gDeviceContext->Release();
    gDeviceContext = nullptr;
  }
  if (gDevice) {
    gDevice->Release();
    gDevice = nullptr;
  }
}

LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam)) {
    return true;
  }

  switch (msg) {
    case WM_SIZE:
      if (gDevice != nullptr && wParam != SIZE_MINIMIZED) {
        CleanupRenderTarget();
        gSwapChain->ResizeBuffers(0, static_cast<UINT>(LOWORD(lParam)), static_cast<UINT>(HIWORD(lParam)),
                                  DXGI_FORMAT_UNKNOWN, 0);
        CreateRenderTarget();
      }
      return 0;
    case WM_SYSCOMMAND:
      if ((wParam & 0xfff0) == SC_KEYMENU) {
        return 0;
      }
      break;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
    default:
      break;
  }
  return DefWindowProcW(hWnd, msg, wParam, lParam);
}

std::string NarrowAscii(const std::wstring& value) {
  std::string out;
  out.reserve(value.size());
  for (wchar_t ch : value) {
    out.push_back(ch >= 32 && ch <= 126 ? static_cast<char>(ch) : '?');
  }
  return out;
}

void LoadFonts(ImFont*& iconFont) {
  ImGuiIO& io = ImGui::GetIO();
  io.Fonts->AddFontFromFileTTF("assets/fonts/Inter-Regular.ttf", 13.0f);
  static const ImWchar iconRanges[] = {
      0xF007, 0xF007, 0xF013, 0xF013, 0xF015, 0xF015, 0xF017, 0xF017,
      0xF019, 0xF019, 0xF01C, 0xF01C, 0xF021, 0xF021, 0xF03D, 0xF03E,
      0xF04B, 0xF04B, 0xF048, 0xF048, 0xF051, 0xF051, 0xF07C, 0xF07E,
      0xF0C4, 0xF0C9, 0xF1DE, 0xF1DE, 0xF1F8, 0xF1F8, 0xF245, 0xF245,
      0xF302, 0xF302, 0xF53F, 0xF53F, 0xF58E, 0xF58E, 0xF5FD, 0xF5FD,
      0xF61F, 0xF61F, 0xF83E, 0xF83E, 0,
  };
  ImFontConfig iconConfig;
  iconConfig.MergeMode = false;
  iconConfig.PixelSnapH = true;
  iconFont = io.Fonts->AddFontFromFileTTF("assets/fonts/fa-solid-900.otf", 13.0f, &iconConfig, iconRanges);
}

void HandleCommand(HWND window,
                   const makelab::imgui::EditorShellResult& result,
                   makelab::imgui::LibrarySection& librarySection,
                   std::string& status) {
  using namespace makelab::imgui;
  using namespace makelab::imgui::platform::win32;

  if (result.command.empty()) {
    return;
  }
  if (result.command == "SelectLibrarySection") {
    if (result.payload == "media") librarySection = LibrarySection::Media;
    if (result.payload == "text") librarySection = LibrarySection::Text;
    if (result.payload == "audio") librarySection = LibrarySection::Audio;
    if (result.payload == "background") librarySection = LibrarySection::Background;
    if (result.payload == "shapes") librarySection = LibrarySection::Shapes;
    return;
  }
  if (result.command == "OpenProject") {
    const WindowsDialogResult dialog = OpenProjectFolder(window);
    if (!dialog.accepted) {
      status = dialog.diagnostic;
      return;
    }
    status = "Windows Open Folder selected: " + NarrowAscii(dialog.path) +
             ". Next step must bind this path through Gates and accepted workspace reload.";
    return;
  }
  if (result.command == "BeginPlayback") {
    status = "Playback blocked: WindowsD3DRenderFrameExecutor has not produced FinalFrameSurface.";
    return;
  }
  if (result.command == "RequestRender") {
    status = "Render requested: Windows must execute Gates -> RenderGraph -> FXPassGraph -> FinalFrameSurface.";
    return;
  }
  if (result.command == "RequestExport") {
    WindowsExportExecutor exporter;
    const WindowsExportResult exportResult = exporter.ExportFromFinalFrameSurface(nullptr, L"");
    status = exportResult.diagnostic;
    return;
  }
  if (result.command == "ScrubTimeline") {
    status = "Scrub requested: Windows scheduler must request FinalFrameSurface for the timeline frame.";
    return;
  }

  status = "Windows command observed: " + result.command + ".";
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
  const HRESULT coInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  (void)coInit;

  WNDCLASSEXW wc = {sizeof(wc),
                    CS_CLASSDC,
                    WndProc,
                    0L,
                    0L,
                    instance,
                    nullptr,
                    nullptr,
                    nullptr,
                    nullptr,
                    L"MakelabImGuiProfessional",
                    nullptr};
  RegisterClassExW(&wc);
  HWND window = CreateWindowW(wc.lpszClassName,
                              L"Makelab IMGUI Professional",
                              WS_OVERLAPPEDWINDOW,
                              100,
                              100,
                              1680,
                              980,
                              nullptr,
                              nullptr,
                              wc.hInstance,
                              nullptr);

  if (!CreateDeviceD3D(window)) {
    CleanupDeviceD3D();
    UnregisterClassW(wc.lpszClassName, wc.hInstance);
    if (SUCCEEDED(coInit)) {
      CoUninitialize();
    }
    return 1;
  }

  ShowWindow(window, SW_SHOWDEFAULT);
  UpdateWindow(window);

  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGuiIO& io = ImGui::GetIO();
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
  io.IniFilename = nullptr;

  ImGui::StyleColorsDark();
  ImFont* iconFont = nullptr;
  LoadFonts(iconFont);

  ImGui_ImplWin32_Init(window);
  ImGui_ImplDX11_Init(gDevice, gDeviceContext);

  makelab::imgui::platform::win32::WindowsD3DRenderFrameExecutor frameExecutor(gDevice, gDeviceContext);
  makelab::imgui::LibrarySection librarySection = makelab::imgui::LibrarySection::Media;
  std::string status =
      "Windows platform shell ready. Preview waits for WindowsD3DRenderFrameExecutor -> FinalFrameSurface.";
  bool done = false;
  while (!done) {
    MSG msg;
    while (PeekMessageW(&msg, nullptr, 0U, 0U, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
      if (msg.message == WM_QUIT) {
        done = true;
      }
    }
    if (done) {
      break;
    }

    ImGui_ImplDX11_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();

    const makelab::imgui::platform::win32::WindowsFinalFrameSurfaceResult surface =
        frameExecutor.RenderFrame(nullptr, 0, 0, false);

    makelab::imgui::EditorShellConfig config;
    config.designFixture = false;
    config.iconFont = iconFont;
    config.librarySection = librarySection;
    config.finalFrameSurfaceReady = surface.accepted() && surface.texture != nullptr;
    config.finalFrameSurfaceTexture = surface.texture;
    config.finalFrameSurfaceWidth = surface.width;
    config.finalFrameSurfaceHeight = surface.height;
    config.frameRate = makelab::timeline::FrameRateFromFps(30.0);
    config.diagnostic = status.c_str();

    const makelab::imgui::EditorShellResult result = makelab::imgui::DrawEditorShell(config);
    HandleCommand(window, result, librarySection, status);

    ImGui::Render();
    const float clearColor[4] = {0.027f, 0.043f, 0.047f, 1.0f};
    gDeviceContext->OMSetRenderTargets(1, &gRenderTargetView, nullptr);
    gDeviceContext->ClearRenderTargetView(gRenderTargetView, clearColor);
    ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());
    gSwapChain->Present(1, 0);
  }

  ImGui_ImplDX11_Shutdown();
  ImGui_ImplWin32_Shutdown();
  ImGui::DestroyContext();

  CleanupDeviceD3D();
  DestroyWindow(window);
  UnregisterClassW(wc.lpszClassName, wc.hInstance);
  if (SUCCEEDED(coInit)) {
    CoUninitialize();
  }
  return 0;
}
