# Professional Render Plan

## Purpose

Build a professional preview and export foundation for Makelab / Neo Remaker that can handle heavy scenes, video, images, shapes, animation, 3D, 1080p, 1440p, 4K, 60fps, and future higher frame rates without lowering visual quality.

This plan does not replace the current architecture. It strengthens the render path under the existing contract:

```text
User UI
-> Remake Timeline model
-> Remake Engine native scene runtime
-> folder workspace scene files
-> preview / render / export
```

The current workspace contract remains the source of truth:

```text
project.json
composition.json
native-scenes/main/index.html
native-scenes/main/scene.css
native-scenes/main/scene.js
assets/
renders/
proofs/
```

Agents still write directly to:

```text
native-scenes/main/index.html
native-scenes/main/scene.css
native-scenes/main/scene.js
```

No legacy inbox folders. No compiler. No legacy command or transaction layer.

## Superseding FX/Core Rule

This older render plan is historical for browser-rendering lessons, but all FX development now follows the shared HyperFrame Core route. FX must not be implemented as a Web-only renderer feature, native-only renderer feature, scene-file trick, or encoder feature.

Current strict FX route:

```text
timeline/style.effects
-> UnitedGate / HyperFrame IR
-> FrameDescriptor/sub-frame descriptor
-> FX Registry / Normalizer / Compiler
-> FXPassGraph
-> platform adapter execution
-> FinalFrameStream
```

Any text in this file that implies scene files, DOM/canvas tricks, or platform-specific code can define an FX is superseded by `docs/Professional HyperFrame FX Development Standard.md` and `unified-hyperframe-rendering-core-plan.md`.

## Research Inputs

### WebCut Findings

Local reference: archived WebCut research folder.

Important files:

```text
src/modules/advanced-export/export-panel.vue
src/hooks/index.ts
src/libs/ffmpeg.ts
src/types/index.ts
src/hooks/transition.ts
src/modules/transitions/effects-transitions.ts
```

Observed architecture:

- WebCut uses `@webav/av-canvas` and `@webav/av-cliper`.
- Preview is based around `AVCanvas`, clips, sprites, and timeline rails.
- MP4 export uses `canvas.createCombinator(...).output()` and writes a `ReadableStream`.
- FFmpeg.wasm exists, but is not the main render/export path. It is mostly helper tooling for conversion/remux/probe style tasks.
- Timeline identity is simple and useful: `rails -> segments -> sourceKey -> clip/sprite/source`.
- Fast export comes from avoiding DOM screenshot export and using a video-oriented canvas/combinator pipeline.

Lesson for Makelab:

```text
Use stream-based export for browser output.
Do not collect full video in memory when avoidable.
Keep assets/clips/sprites tied to stable timeline identity.
Use FFmpeg.wasm only for auxiliary operations unless there is no better path.
```

### OpenCut Findings

Local reference: archived OpenCut research folder.

Important files:

```text
apps/web/src/services/renderer/canvas-renderer.ts
apps/web/src/services/renderer/scene-exporter.ts
apps/web/src/services/renderer/compositor/wasm-compositor.ts
apps/web/src/services/renderer/gpu-renderer.ts
docs/effects-renderer.md
rust/crates/compositor/src/compositor.rs
rust/crates/gpu/src/context.rs
rust/wasm/src/gpu.rs
```

Observed architecture:

- OpenCut is moving business/rendering logic into Rust/WASM.
- GPU rendering uses WGPU with WebGPU detection and WebGL fallback.
- Effects are GPU pass definitions with shaders and uniforms.
- Texture caching prevents re-uploading unchanged static content every frame.
- Export renders frames deterministically from a scene graph into a canvas source, then encodes/muxes.
- OpenCut's browser export is useful, but not a guaranteed final pipeline for long 4K/60/90fps projects because some paths are serial and buffer-heavy.

Lesson for Makelab:

```text
Use OpenCut as reference for GPU preview/compositor, texture cache, effect passes, and scene graph evaluation.
Do not rely on browser-only export as the only professional final export path for 4K/high-fps projects.
```

### Official Platform Direction

Relevant browser APIs:

- WebCodecs: low-level frame encode/decode and hardware acceleration when available.
- OffscreenCanvas: canvas rendering that can run away from the main UI thread.
- WebGPU/WebGL2: GPU-first rendering for 2D/3D/effects/compositing.
- requestVideoFrameCallback: frame-aware video synchronization.
- File System Access API: efficient local save/open flow in Chromium.

Platform conclusion:

```text
DOM/CSS is not the professional render core for heavy scenes.
DOM/CSS is for app UI and light scene authoring.
Heavy video/motion/3D/glow/blur/transitions must use Canvas/WebGL/WebGPU/WebCodecs paths.
```

## Target Architecture

### Runtime Layers

```text
Makelab React UI
  - project creation
  - folder workspace
  - timeline controls
  - preview diagnostics
  - export controls

Remake Timeline Model
  - fps
  - duration
  - playhead
  - tracks
  - clips
  - source identity

Remake Runtime Contract
  - window.__remake.duration
  - window.__remake.seek(time)
  - window.__remake.playFrom(time)
  - window.__remake.pause()

Professional Render Runtime
  - DOM scene support for light scenes
  - Canvas2D support for moderate scenes
  - WebGL2 / Three.js support for heavy scenes
  - WebGPU / WGPU-style compositor later
  - WebCodecs/WebAV-style export path
  - native/server FFmpeg final export path later
```

### Two Render Modes

#### 1. Preview Mode

Purpose:

```text
Interactive playback, scrub, canvas preview, timeline editing.
```

Requirements:

- No React state updates per frame except minimal playhead telemetry when needed.
- No folder scanning while playback is active.
- No iframe reload while playback is active.
- Scene runtime owns animation loop.
- Timeline clock owns time.
- Preview renders from `window.__remake.seek(time)`.

Backends:

```text
DOM/CSS backend       -> simple text/layout scenes
Canvas2D backend     -> moderate 2D scenes
WebGL2/Three backend -> heavy animation, particles, video transforms, glow, 3D
WebGPU backend       -> later advanced compositor/effects path
```

#### 2. Export Mode

Purpose:

```text
Deterministic frame export at project fps/resolution.
```

Browser fast export:

```text
render frame
-> canvas/video frame
-> WebCodecs/WebAV/Mediabunny-style encode
-> stream output to file
```

Professional final export:

```text
render frame chunks
-> native/server/desktop FFmpeg pipeline
-> high-quality MP4/ProRes/WebM variants
```

Reason:

Browser export can be fast for normal projects, but 4K/60/90fps long projects need a final pipeline that is not limited by a single browser tab's memory and encoder support.

## Non-Negotiable Rules

1. Do not change the folder workspace contract.
2. Do not introduce legacy inbox folders.
3. Do not introduce legacy command or transaction layers.
4. Do not make preview and export evaluate different creative results.
5. Do not lower video quality as the primary performance strategy.
6. Do not rely on CSS `filter`, `backdrop-filter`, or DOM paint for heavy per-frame effects.
7. Do not implement motion blur, motion trails, motion tile, glow streaks, or repeated shadow effects by running `ctx.filter = blur(...)`, `ctx.shadowBlur`, clipping, or vector rasterization inside every sample on every frame. Bake static layer/effect sprites once and reuse cached blurred variants during playback.
8. Do not scan/reload files during active playback.
9. Do not gather long exports into one huge memory buffer when stream output is possible.
10. Do not make FFmpeg.wasm the primary renderer for every project.
11. Do not depend on server export for normal local preview.

## Implementation Phases

## Phase 0: Render Diagnostics Baseline

Goal:

```text
Measure before changing the render path.
```

Add diagnostics inside Makelab preview:

```text
src/engine/remake/composePreviewHtml.ts
src/App.tsx
src/styles.css
```

Tasks:

1. Add preview frame timing probe inside iframe.
2. Track average frame time, p95 frame time, dropped-frame estimate, and long frames.
3. Capture scene warnings:
   - moving CSS filter
   - moving backdrop-filter
   - large animated DOM layers
   - frequent layout reads during animation
4. Add visible diagnostics panel:
   - Good
   - Warning
   - Critical
5. Add copyable diagnostic report for agents.

Acceptance:

- User can identify whether lag is from scene code, app code, file scan, or browser capability.
- Diagnostics do not alter scene output.
- `npm run build` passes.
- `npm run lint` passes.

## Phase 1: Playback Isolation

Goal:

```text
Remove Makelab overhead from active playback.
```

Files:

```text
src/App.tsx
src/project/workspace.ts
```

Tasks:

1. Suspend live reload polling while `isPlaying === true`.
2. Resume scan/polling after pause.
3. Keep manual `Scan / Render Folder` available when paused.
4. Ensure `Play` never re-renders React every frame.
5. Ensure iframe reload happens only after explicit scan or actual file change while paused.

Acceptance:

- No folder reads during playback.
- Playback only calls `window.__remake.playFrom(time)`.
- Scrub only calls `window.__remake.seek(time)`.
- Timeline UI remains responsive.

## Phase 2: GPU Scene Authoring Contract

Goal:

```text
Teach agents to write heavy scenes as GPU-native scenes without changing the workspace structure.
```

Files:

```text
src/project/workspace.ts
docs/professional-render-plan.md
```

Workspace-generated file:

```text
AGENT_INSTRUCTIONS.md
```

Tasks:

1. Update generated `AGENT_INSTRUCTIONS.md` with a `Professional Render Rules` section.
2. Define two scene styles:
   - `DOM Scene` for simple layouts.
   - `GPU Scene` for heavy animation/video/3D/effects.
3. Require heavy scenes to use a full-composition `<canvas>`.
4. Require deterministic renderer functions:

```js
function init() {}
function render(time) {}
function resize() {}
function dispose() {}

window.__remake = {
  duration,
  seek(time) { render(time); },
  playFrom(time) {},
  pause() {}
};
```

5. Warn agents not to animate CSS filter/backdrop-filter/drop-shadow per frame.
6. Encourage Canvas2D/WebGL/Three.js for glow, blur, particles, transitions, video transforms, and 3D.

Acceptance:

- New workspaces guide agents toward GPU scenes for heavy work.
- No new compiler.
- No new scene.json.
- No commands or transactions.

## Phase 3: Professional Preview Backend

Goal:

```text
Add an app-level professional preview backend without replacing raw scene files.
```

New proposed paths:

```text
src/engine/rendering/types.ts
src/engine/rendering/renderDiagnostics.ts
src/engine/rendering/capabilities.ts
src/engine/rendering/professionalPreview.ts
```

Tasks:

1. Detect browser capabilities:
   - WebGL2
   - WebGPU
   - OffscreenCanvas
   - WebCodecs
   - VideoEncoder
   - VideoDecoder
   - File System Access API
2. Expose capability report in UI.
3. Add optional preview hints injected into iframe:
   - composition width/height/fps/duration
   - render mode
   - diagnostics hooks
4. Add `Professional Preview` status:
   - DOM
   - Canvas2D
   - WebGL2
   - WebGPU available
5. Do not force scenes into a framework. The scene remains raw HTML/CSS/JS.

Acceptance:

- User can see whether current browser/device supports professional render features.
- Existing DOM scenes still work.
- GPU scenes can be written directly in `scene.js`.

## Phase 4: Asset Pipeline Foundation

Goal:

```text
Prepare high-resolution video/image workflows without blocking the UI.
```

New proposed paths:

```text
src/engine/assets/types.ts
src/engine/assets/assetProbe.ts
src/engine/assets/proxyPolicy.ts
src/engine/assets/mediaCache.ts
```

Workspace folders already exist:

```text
assets/
renders/
proofs/
```

Tasks:

1. Add asset metadata model:
   - id
   - file name
   - type
   - width/height
   - duration
   - fps if known
   - codec if known
2. Add preview proxy policy:
   - original quality remains untouched
   - preview may use proxy if media is too heavy
   - export uses original unless user selects proxy export
3. Use image/video metadata only; no destructive conversion.
4. Plan OPFS/cache integration later for large local projects.

Acceptance:

- Makelab can reason about heavy assets before rendering them.
- No quality loss in source files.
- Preview optimization is separate from final export quality.

## Phase 5: Browser Fast Export

Goal:

```text
Implement fast local export for normal projects using browser-native video pipelines.
```

Inspirations:

```text
WebCut: AVCanvas createCombinator -> ReadableStream
OpenCut: CanvasSource -> MP4/WebM output
```

New proposed paths:

```text
src/engine/export/types.ts
src/engine/hyperframe/exportPipeline.ts
src/engine/hyperframe/exportExecutor.ts
src/engine/hyperframe/webCodecsCanvasEncoder.ts
src/engine/export/exportProgress.ts
src/engine/export/streamSave.ts
```

Tasks:

1. Add export profile:
   - resolution
   - fps
   - bitrate
   - format
   - codec
   - audio on/off
2. Prefer stream output:

```text
ReadableStream -> WritableStream -> selected file
```

3. Select one HyperFrame export executor:
   - BMF executor when a verified adapter is executable.
   - Browser final-frame-stream encoder only while BMF final-frame-stream artifacts are unavailable.
4. Do not restore DOM raster, `MediaRecorder`, or `html-to-image` export paths.
5. Keep FFmpeg/BMF artifacts as explicit adapters, not hidden fallback renderers.
6. Add export diagnostics:
   - encoder support
   - estimated frame count
   - estimated memory risk
   - expected export path

Acceptance:

- 1080p/30 and 1080p/60 normal projects export locally.
- Export progress is visible.
- Output is written as stream where possible.
- Large projects prefer browser final-frame-stream streaming output when File System Access is available and fall back to Blob download only when needed.

## Phase 6: GPU Compositor Prototype

Goal:

```text
Create a real GPU compositor path for Makelab-native layers and future video editing.
```

OpenCut inspiration:

```text
Rust/WASM/WGPU compositor
texture cache
effect passes
shader uniforms
scene graph -> frame descriptor
```

Makelab initial implementation should be smaller:

```text
TypeScript WebGL2 compositor first
WASM/WGPU later if justified
```

New proposed paths:

```text
src/engine/rendering/compositor/types.ts
src/engine/rendering/compositor/webgl2Compositor.ts
src/engine/rendering/compositor/textureCache.ts
src/engine/rendering/compositor/effectPasses.ts
```

Tasks:

1. Define `FrameDescriptor`:

```ts
type FrameDescriptor = {
  width: number;
  height: number;
  time: number;
  layers: RenderLayer[];
};
```

2. Define `RenderLayer`:

```ts
type RenderLayer = {
  id: string;
  sourceId: string;
  kind: "image" | "video" | "canvas" | "text" | "shape";
  transform: Transform2D;
  opacity: number;
  blendMode?: string;
  effects?: EffectInstance[];
};
```

3. Add texture cache:
   - upload static texture once
   - reuse unchanged textures
   - release unused textures
4. Add effect pass model:
   - blur
   - glow
   - color grade
   - mask feather
5. Keep preview and export using the same frame descriptor.

Acceptance:

- Heavy blur/glow runs as shader passes, not CSS filters.
- Static content is cached.
- Preview/export can share the same evaluation model.

## Phase 7: Professional Final Export Path

Goal:

```text
Guarantee professional output for 1440p/4K/60/90fps and long projects.
```

Reason:

Browser-only export is valuable, but it is not a guaranteed final pipeline for every project size and device. 4K/90fps is about 746 million pixels per second before layers, effects, decode, encode, and audio.

Pro path options:

```text
Desktop/native helper
Local render worker process
Server render worker
FFmpeg final encode
```

Tasks:

1. Define portable render job JSON:
   - composition
   - timeline
   - asset paths
   - render profile
   - output path
2. Render in chunks:
   - frame ranges
   - progress
   - resume support
3. Encode with FFmpeg:
   - H.264/H.265/ProRes/WebM options
   - high bitrate
   - audio mux
4. Keep browser preview identical through shared frame evaluation rules.

Acceptance:

- Normal exports can stay in-browser.
- Professional 4K/high-fps exports have a reliable final pipeline.
- No quality reduction is required for final output.

## Phase 8: Quality And Performance Gates

Goal:

```text
Prevent regressions and catch scene/render bottlenecks early.
```

Tasks:

1. Add performance test scenes:
   - DOM light scene
   - CSS-heavy stress scene
   - Canvas2D scene
   - WebGL scene
   - video transform scene
   - 4K still/image scene
2. Add metrics:
   - frame time average
   - p95
   - p99
   - dropped frame estimate
   - texture upload count
   - memory estimate
3. Add warnings:
   - moving CSS filter
   - large animated DOM layer
   - no GPU backend
   - export will buffer entire output
4. Add check before final export:
   - resolution
   - fps
   - duration
   - asset size
   - chosen backend

Acceptance:

- We know why a scene lags before changing it.
- We can tell agents exactly what to fix.
- Performance remains measurable as features grow.

## Recommended Execution Order

Implement in this order:

```text
1. Phase 0: Render Diagnostics Baseline
2. Phase 1: Playback Isolation
3. Phase 2: GPU Scene Authoring Contract
4. Phase 3: Professional Preview Backend capability reporting
5. Phase 4: Asset Pipeline Foundation
6. Phase 5: Browser Fast Export prototype
7. Phase 6: GPU Compositor Prototype
8. Phase 7: Professional Final Export Path
9. Phase 8: Quality And Performance Gates
```

Do not jump to export before diagnostics and playback isolation. If the current scene lags, first prove whether it is:

```text
scene rendering cost
file scan/reload cost
React/UI cost
browser/device capability
asset decode cost
encoder/export cost
```

## Immediate Next Step

The first implementation checkpoint should be:

```text
checkpoint: add professional render diagnostics and playback isolation
```

Scope:

```text
Phase 0 + Phase 1 only
```

Expected result:

- The app reports why a scene is lagging.
- Playback does not scan folder files while playing.
- The preview can show professional render capability support.
- No workspace contract changes.
- `npm run build` passes.
- `npm run lint` passes.

## Final Direction

Makelab should not become only WebCut or only OpenCut.

The right synthesis is:

```text
Remake Engine authoring contract
+ Remake Timeline timing model
+ WebCut-style stream export
+ OpenCut-style GPU compositor and texture cache
+ optional native/server FFmpeg final export
= professional browser-first video/animation editor
```
