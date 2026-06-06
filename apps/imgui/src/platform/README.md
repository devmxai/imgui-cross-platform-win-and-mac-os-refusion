# Platform Adapter Boundary

Platform folders execute shared contracts on native OS and GPU technologies.

Current folders:

```text
macos/
windows/
```

Allowed:

```text
native window bootstrap
native file dialogs
native project watcher
native decode as source texture
native GPU execution
FinalFrameSurface allocation and presentation
live scope readback or compute
native encoder and audio mux
capability diagnostics
```

Forbidden:

```text
forking shared UI
changing FX meaning
changing timeline meaning
changing export meaning
inventing alternate preview truth
silently approximating unsupported features
```

Each platform must consume the same:

```text
Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph -> FinalFrameSurface
```

Shared handoff files:

```text
apps/imgui/src/model/WorkspaceModel.hpp
apps/imgui/src/render/PlatformRenderContracts.hpp
```

Platform-specific result structs may carry native texture handles, but must keep
the shared request, frame index, generation, status, size, and diagnostic
contract.
