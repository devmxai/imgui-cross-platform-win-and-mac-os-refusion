# Native Preview And Export Audit

Created for Gate 1 of the Native Render Engine Creative Corrective Plan.

## Scope

This audit classifies every current macOS preview, playback, scrub, canvas, and export path before replacing the mixed SwiftUI/snapshot/partial-Metal stack with `NativeRenderEngine`.

## Findings

| Path | Owner | Used By | Native Status | Action | Reason |
| --- | --- | --- | --- | --- | --- |
| `EditorState.play()` task loop | `EditorState.swift` | Play, timeline playhead, canvas invalidation | Not acceptable | Replace | Uses `Task.sleep`, `Date`, and `@Published currentFrame` as render clock, causing MainActor churn. |
| `currentFrame` as frame authority | `EditorState.swift` | Play, scrub, descriptor, render graph, timeline UI | Transitional only | Downgrade to UI observer state | Frame truth must move into `NativeRenderEngine`; SwiftUI may observe throttled time only. |
| `previewAudioPlayer` | `EditorState.swift` | Preview audio | Transitional only | Move under engine clock | Audio currently advances separately from visual frame truth. |
| `MetalPreviewSurface` | `MetalPreviewSurface.swift` | Partial canvas background/video | Partial native | Replace with thin `NativeRenderSurface` host | It renders only partial video/background and coordinates with SwiftUI using `nativePreviewHasVideoFrame`. |
| `nativePreviewHasVideoFrame` | `EditorState.swift`, `MetalPreviewSurface.swift`, `ContentView.swift` | Play visual path switching | Not acceptable | Remove | It switches between Metal and SwiftUI visual paths and can create white/black flashes. |
| `CompositionLayerOverlay` | `ContentView.swift` | Canvas visual layers | Not acceptable | Remove from render truth | SwiftUI renders text, shapes, image/video, borders, shadows, masks on top of Metal. |
| `PreviewRenderNode` | `ContentView.swift` | Canvas visual layers | Not acceptable | Replace with compositor passes | Visual interpretation belongs to `MetalCompositor`, not SwiftUI. |
| `VideoFrameSnapshotView` | `ContentView.swift` | Pause/scrub video preview | Not acceptable for realtime | Remove from Play/Scrub | Uses still-frame extraction and SwiftUI image rendering. |
| `AVAssetImageGenerator` preview usage | `ContentView.swift` | Pause/scrub video preview | Forbidden for Play/Scrub | Restrict to thumbnails/diagnostics only | It is not a realtime source provider. |
| `RenderGraphCompiler` | `RenderGraph.swift` | Descriptor to visual execution plan | Keep | Keep and extend | Correct bridge from FrameDescriptor to renderable nodes. |
| `FXPassGraphCompiler` | `FXPassGraph.swift` | FX diagnostics/pass planning | Keep | Keep and make executable | Correct graph boundary, but current runtime does not execute passes. |
| `NativeTimelineExporter` Quartz renderer | `NativeTimelineExporter.swift` | Export | Compatibility only | Replace with offscreen Metal export | Export must use same compositor as preview, not Quartz render truth. |
| `QuartzRenderGraphFrameRenderer` | `NativeTimelineExporter.swift` | Export frames | Compatibility only | Quarantine/remove | It can remain only as an explicitly labeled fallback while native export is being built. |
| Timeline auto-scroll per frame | `EditorState.keepTimelineTimeVisible` | Playback UI | Not acceptable at render rate | Throttle/debounce | Timeline UI must not redraw at 60fps. |

## Gate 1 Verdict

The current app shell is native, but the current preview/export renderer is not a single native render engine. It has multiple visual authorities:

```text
EditorState clock
SwiftUI visual overlay
AVAssetImageGenerator snapshots
partial MetalPreviewSurface
Quartz export renderer
```

The next implementation gate must introduce `NativeRenderEngine` as the only owner of realtime frame execution and make SwiftUI an observer/UI shell only.

## Closure Update

Implemented corrective changes:

```text
NativeRenderSurface replaces MetalPreviewSurface in the canvas.
CompositionLayerOverlay / PreviewRenderNode / VideoFrameSnapshotView are removed from the active canvas path.
NativeRenderEngine owns the MTKView draw loop.
EditorState no longer drives playback with a 16ms Task.sleep render loop.
Video playback no longer performs seek/play on every draw frame.
FrameDescriptor -> RenderGraph -> FXPassGraph evaluation is cached per frame/revision inside NativeRenderEngine.
Automatic export now selects MetalRenderGraphFrameRenderer when Metal initializes.
QuartzRenderGraphFrameRenderer remains explicit compatibility fallback only.
```

Remaining professional hardening:

```text
Share preview/export compositor implementation as one reusable MetalCompositor module.
Add golden-frame preview/export pixel parity tests.
Add full Metal FX runtime for motionTile, gaussianBlur, glow, colorCorrection, motionBlur, and temporal FX.
Replace deprecated synchronous AVFoundation metadata reads with async load APIs.
Add GPU timing diagnostics and dropped-frame counters.
```
