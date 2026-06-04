# macOS Engine Reference

These files preserve the native macOS engine/platform execution reference that
existed when the current Dear ImGui checkpoint was accepted.

Included:

```text
UnitedGate
CanonicalHyperFrameBridge
RenderGraph
FXPassGraph
Metal FX execution
NativeRenderEngine
FinalFrameSurface host
NativeTimelineExporter
```

Excluded:

```text
legacy SwiftUI application shell
ContentView
EditorState
MakelabMacApp
```

The active application is `apps/imgui`. These Swift files are not an alternate
UI or frame truth. They preserve native execution contracts and implementation
knowledge needed to continue the macOS/Windows cross-platform engine path.
