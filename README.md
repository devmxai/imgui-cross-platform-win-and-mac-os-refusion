# IMGUI Cross Platform Win and Mac OS refusion

Independent native C++ / Dear ImGui desktop editor repository.

Current validated platform:

```text
macOS Apple Silicon
Dear ImGui UI
C++ / Objective-C++
Metal
AVFoundation / VideoToolbox texture sources
```

Planned second platform:

```text
Windows
Dear ImGui UI
C++
Direct3D
Media Foundation texture sources
```

## Non-Negotiable Architecture

```text
ImGui UI
  -> commands and display only

Engine
  -> Gates
  -> HyperFrame IR
  -> FrameDescriptor
  -> RenderGraph
  -> FXPassGraph
  -> FinalFrameSurface

GPU backend
  -> displays FinalFrameSurface
```

Preview, Live Scope, and Export must consume the same `FinalFrameSurface` truth.

Forbidden:

```text
UI-owned rendering
fake preview
MediaPlayer fallback
WebView fallback
Canvas fallback
alternate preview or export truth
```

## Current macOS Status

The current checkpoint builds and runs on macOS Apple Silicon.

Validated functionality includes:

```text
native ImGui editor shell
Open Folder project loading
native Metal FinalFrameSurface preview
video, image, text, shape, and background visual nodes
timeline playback and live scrub commands
motionTile Metal execution
gaussianBlur Metal execution
transformMotionBlur temporal accumulation
adaptive high-quality rotation blur
event-driven idle rendering
bounded video texture cache
Objective-C++ ARC memory management
```

See [Current macOS Status](docs/CURRENT_MACOS_STATUS.md) for validation details and remaining work.

## Build

Requirements:

```text
macOS
Apple Clang
CMake 3.24+
Git
```

Build:

```bash
cmake -S apps/imgui -B apps/imgui/build
cmake --build apps/imgui/build
```

Run:

```bash
open -n apps/imgui/build/makelab-imgui-professional.app
```

Run with a workspace:

```bash
open -n apps/imgui/build/makelab-imgui-professional.app --args --open-workspace /absolute/path/to/project
```

## Verify Architecture

```bash
npm run verify
```

## Important Documents

- [IMGUI Professional Architecture Plan](docs/architecture/imgui-professional-plan.md)
- [Professional HyperFrame FX Development Standard](docs/Professional%20HyperFrame%20FX%20Development%20Standard.md)
- [Current macOS Status](docs/CURRENT_MACOS_STATUS.md)

## Repository Boundary

This repository is independent. It contains the native ImGui desktop application and its governing documentation only. It does not inherit the Git history, remotes, web UI, Qt UI, or Flutter implementation from any previous repository.
