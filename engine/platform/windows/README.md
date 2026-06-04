# Windows Platform Adapter

Status: planned native adapter boundary.

The Windows platform adapter executes HyperFrame Core contracts on Windows technologies.

## Intended Chain

```text
apps/windows WinUI shell
-> WindowsEditorSession / EditorViewModel
-> Core project contract
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> WindowsRenderEngine
-> FinalFrameSurface / FinalFrameStream
-> Windows encoder backend
```

## Native Technologies

```text
WinUI 3 / Windows App SDK
SwapChainPanel or Win2D CanvasControl for preview host
Direct3D / Direct2D for native rendering
Media Foundation for decode and encode
```

## Rule

Windows adapter work must execute Core contracts. It must not define new FX semantics, animation semantics, timeline meanings, sample planner behavior, or export meaning.
