# Shared Render Contracts

This folder defines the platform-neutral contract for native preview, live
scope, and export execution.

The accepted path is:

```text
Gates
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> PlatformRenderFrameExecutor
-> FinalFrameSurface
```

Platform adapters may attach native handles to their own result structs, but
they must preserve the shared request, status, frame index, generation, size,
and diagnostic contract.

Rules:

- Preview, live scope, and export must consume accepted FinalFrameSurface data.
- Unsupported platform execution fails closed with diagnostics.
- UI never creates preview pixels or export frames.
- FX and timeline meaning are shared before a platform executor implements a
  native pass.

