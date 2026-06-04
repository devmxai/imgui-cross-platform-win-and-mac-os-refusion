# IMGUI Professional Native Shell

This app is the native desktop shell for the IMGUI Professional plan.

Current target:

```text
macOS Apple Silicon M1
C++ / Objective-C++ bootstrap
Dear ImGui editor shell
Metal display backend
```

Hard rule:

```text
ImGui UI -> commands only
Engine -> Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph -> FinalFrameSurface
GPU backend -> displays FinalFrameSurface
```

The shell may draw panels, controls, diagnostics, accepted project state, and a native texture slot. It must not decode media, compose layers, own timeline truth, or draw fake preview pixels.

Build:

```bash
cmake -S apps/imgui -B apps/imgui/build
cmake --build apps/imgui/build
```

Run production shell:

```bash
open "apps/imgui/build/makelab-imgui-professional.app"
```

Run visual fixture shell for screenshot parity work only:

```bash
open "apps/imgui/build/makelab-imgui-professional.app" --args --design-fixture
```

`--design-fixture` is not a preview path. It only fills the asset and timeline panels with visual state so the native UI can be compared against the locked 3360x1824 reference screenshot.

Run with a workspace path for Open Folder smoke testing:

```bash
open "apps/imgui/build/makelab-imgui-professional.app" --args --open-workspace /absolute/path/to/workspace
```
