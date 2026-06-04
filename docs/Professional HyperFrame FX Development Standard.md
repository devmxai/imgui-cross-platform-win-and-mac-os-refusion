# Professional HyperFrame FX Development Standard

Status: authoritative, active, and mandatory.

Decision date: 2026-05-29.

This is the single source of truth for building, modifying, correcting, upgrading, testing, and shipping every visual FX in MakeLab / HyperFrame.

This standard replaces the older split FX plans:

```text
Build FX Plan
Professional Motion FX Upgrade Plan
Professional Motion Builder FX
Professional Motion Blur FX V2 Corrective Plan
Universal HyperFrame FX PassGraph Plan
```

Those plans must not be recreated as separate implementation authorities. Future FX work belongs in this document as a catalog entry, implementation track, and acceptance gate.

## 1. Core-First Rule

No FX is developed for one platform first as its source of truth.

The only valid path is:

```text
timeline/style.effects
-> UnitedGate validation
-> HyperFrame IR
-> FrameDescriptor / sub-frame descriptor
-> FX Registry
-> FX Normalizer
-> FX Compiler
-> FXPassGraph
-> Platform Adapter Execution
-> FinalFrameSurface / FinalFrameStream
```

HyperFrame Core owns:

```text
effect names and aliases
schema, defaults, units, bounds
normalization and migration
pass ordering
temporal sample planning
spatial sample planning
quality tiers
fallback policy
diagnostics
golden-frame expectations
UI parameter metadata
```

Platform adapters own only execution:

```text
source texture resolve
GPU/CPU resource allocation
shader / compute / CPU fallback execution
high-precision intermediate targets
capability declaration
adapter diagnostics
final surface handoff
```

Encoders own only encode/mux/output:

```text
FinalFrameStream + AudioPCM -> BMF / WebCodecs / native encoder
```

BMF, WebCodecs, native encoders, UI panels, scene files, Web runtimes, Metal runtimes, and platform shells must not define FX meaning.

## 2. Two FX Tracks

Every FX request starts by classifying the FX into one of two tracks.

### Track A: Build New FX

Use this when the FX does not exist as a canonical HyperFrame effect.

Required sequence:

```text
1. Add an FX Catalog entry with status: planned.
2. Define effect family and semantics.
3. Add FX Registry schema.
4. Add aliases and legacy migration rules.
5. Add FX Normalizer support.
6. Add FX Compiler support.
7. Add FXPassGraph node contract.
8. Add diagnostics and unsupported capability behavior.
9. Add at least one platform adapter executor.
10. Add golden-frame tests and preview/export parity tests.
11. Add UI metadata only after real registry params exist.
12. Promote status from planned to supported only after gates pass.
```

### Track B: Upgrade Existing FX

Use this when the FX already exists but quality, semantics, platform parity, diagnostics, or tests are incomplete.

Required sequence:

```text
1. Add or update an FX Catalog entry with status: corrective, partial, or upgrade.
2. Audit current schema, normalizer, compiler, pass graph, adapters, diagnostics, and tests.
3. Identify whether the bug is Core semantics or adapter execution.
4. Fix Core first if semantics, planning, ordering, samples, or fallback policy are wrong.
5. Fix adapters only to execute the compiled Core plan.
6. Add regression fixtures before marking the correction complete.
7. Update capability declarations and UI metadata.
8. Promote status only after acceptance gates pass.
```

An existing FX must not be patched directly in Web, macOS, BMF, or UI code unless that patch is strictly adapter execution for an already-defined Core plan.

## 3. FX Status Model

Every FX must have one status.

```text
unknown
  No canonical registry entry. Must not be authored.

planned
  Approved for design, but no visual support is promised.

registered
  Schema and normalization exist. Rendering may still be unsupported.

compiled
  FXPassGraph node exists. Platform execution may still be unsupported.

adapter-partial
  At least one adapter executes part of the plan with diagnostics.

corrective
  Existing implementation is known to be insufficient and is under repair.

supported
  Core, adapter execution, diagnostics, preview/export parity, and golden tests pass.

deprecated
  Accepted only for migration. Must normalize to a supported canonical FX or diagnose.
```

No UI, agent, runtime, export report, or platform capability may call an FX `supported` unless it has reached the `supported` status here.

## 4. FX Families

Every FX belongs to one family:

```text
temporal-transform
  Samples layer/source state across shutter or time.

spatial-texture
  Samples one resolved source texture.

edge-sampler
  Defines source behavior outside bounds.

composite
  Changes blend, alpha, matte, mask, shadow, or border behavior.

color
  Changes pixel color, tone, exposure, curves, LUT, chroma, or channels.

transition
  Mixes two time-related sources.

generator
  Creates pixels without a media source.

time-domain
  Changes media time, frame blending, echo, or retiming behavior.
```

Family selection controls pass ordering, resource requirements, diagnostics, and UI grouping.

## 5. FX Catalog

This catalog is the active roadmap. Any new FX or corrective FX work must update this table first.

| FX | Family | Track | Status | Build % | Quality Confidence % | Canonical Rule |
| --- | --- | --- | --- | ---: | ---: | --- |
| `transformMotionBlur` | temporal-transform | upgrade | corrective | 88 | 64 | Temporal shutter accumulation from transform/source samples. |
| `motionBlur` | alias | upgrade | corrective | 92 | 69 | Must normalize to `transformMotionBlur` or a declared directional blur mode. |
| `motionTrail` | time-domain | upgrade | registered | 35 | 25 | Stylized echo/trail, never a substitute for shutter blur. |
| `motionTile` | edge-sampler | upgrade | adapter-partial | 75 | 60 | Sampler/edge expansion, not duplicated layers. |
| `gaussianBlur` | spatial-texture | upgrade | registered | 55 | 45 | Separable or equivalent blur pass with explicit radius and quality. |
| `directionalBlur` | spatial-texture | build | planned | 15 | 10 | Directional spatial blur, separate from transform shutter blur. |
| `radialBlur` | spatial-texture | build | planned | 30 | 20 | Radial texture reconstruction around a declared center. |
| `spinBlur` | spatial-texture | build | planned | 25 | 15 | Spin/polar sampling around a declared center. |
| `zoomBlur` | spatial-texture | build | planned | 30 | 20 | Zoom/ray sampling toward or away from a declared center. |
| `spiralEchoBlur` | spatial-texture/time-domain | build | planned | 25 | 15 | Stylized spin + zoom + echo decay, distinct from transform blur. |
| `glowStreak` | spatial-texture/composite | build | planned | 25 | 15 | Bloom/streak pass with threshold, direction, and blend policy. |
| `chromaticSplit` | spatial-texture/color | build | planned | 25 | 15 | Channel offset/split pass with bounded displacement. |
| `shaderTransition` | transition | build | planned | 20 | 10 | Registered transition pass, not scene-only code. |

The catalog is intentionally conservative. A new effect may be added only by giving it a family, track, status, schema owner, adapter requirements, diagnostics, and tests.

## 6. Progress Scoring And Build Ledger Rules

This document is also the live build ledger for FX work. Every implementation turn that builds, changes, reviews, or corrects an FX must update the matching FX entry before handoff.

Two percentages are mandatory:

```text
Build %
  How much of the required architecture exists.

Quality Confidence %
  How much confidence we have that rendered output is professional,
  based on visual review, golden frames, diagnostics, and parity.
```

Percentages are not feelings. Use this scoring model:

```text
20% Registry/schema/aliases/defaults exist.
20% Normalizer/compiler/FXPassGraph node exists.
20% Core planning/semantics/order/quality policy are correct.
20% At least one adapter executes the compiled Core plan.
10% Diagnostics and capability reporting are explicit.
10% Golden-frame and preview/export parity tests pass.
```

Quality Confidence must stay lower than Build % when:

```text
visual QA is missing
golden frames are missing
preview/export parity is unproven
platform parity is unproven
fallbacks still affect pixels
the user reports visible artifacts
```

Required update rule:

```text
If code changes an FX, update its FX Card.
If visual review changes confidence, update its FX Card.
If a user reports "70%" or "80%" quality, record it as Review Notes.
If a value, cap, shader method, sample count, or fallback changes, record it.
If a platform adapter is added or removed, record it.
If tests pass or fail, record the exact command and result.
```

No FX handoff is complete unless this document says:

```text
what was built
what remains
where the implementation lives
which values are currently used
which diagnostics exist
which tests passed
which user/agent review notes are known
```

### FX Card Template

Every FX must keep a card using this shape:

```text
FX:
Track:
Status:
Build %:
Quality Confidence %:
Last Updated:
Current Implementation:
Current Values / Parameters:
Core Files:
Adapter Files:
Diagnostics:
Tests / Verification:
Known Issues:
User Review Notes:
Agent Review Notes:
Next Required Build Step:
Promotion Gate:
```

### Build Log Entry Template

Append one entry when an FX receives meaningful work:

```text
Date:
FX:
Change Type: build | upgrade | corrective | review | test
Before:
After:
Files Changed:
Values / Methods Changed:
Verification:
Reviewer Notes:
Next Step:
```

## 7. Current FX Build Ledger

Last ledger refresh: 2026-05-29.

Verification snapshot:

```text
npm run motionfx:verify
Motion FX contract verified for 10 effect intents and 7 WebGL2 shader effects.
```

### transformMotionBlur

```text
Track: upgrade
Status: corrective
Build %: 85
Quality Confidence %: 61
Last Updated: 2026-05-29
Current Implementation:
  Core planner exists in TypeScript.
  Sub-frame FrameDescriptor contract exists.
  FXPassGraph serializes MotionBlurSamplePlan on transformMotionBlur passes.
  Export FinalFrameStream passes the Core FXPassGraph into runtime.renderFrame.
  Preview seek, interactive seek, and playback now provide Core FXPassGraph from previewPipeline/App.
  Playback runtime receives a Core FXPassGraph provider for each scheduled playback frame.
  Web runtime consumes motionBlurSamplePlan when it is provided by the Core request.
  Missing Core plans now emit motion-blur-core-sample-plan-unavailable when fallback planning is used.
  Export-quality runtime blur no longer uses local sample planning when Core plan is missing.
  Core export quality policy now allows up to 192 motion blur samples.
  Motion blur sample-plan verification now asserts cinematic adaptive sample counts and normalized weights.
  macOS planner/Metal hooks exist in current workspace.
  macOS native preview motionBlur samples now consume the per-sample resolved FX source texture, so motionTile expansion is not mixed with raw video texture drawing.
  macOS native preview and Metal export resolve per-sample source/pre-transform FX before opening the motionBlur render encoder.
  Web runtime still has transitional platform-local planning fallback when no Core plan is provided.
Current Values / Parameters:
  shutterAngle
  shutterPhase
  amount
  samples: fixed number | auto
  sampleCurve
  export target sample range: 16-192 depending on motion and capability
  preferred accumulation: rgba16Float
  acceptable fallback: rgba16Unorm
  diagnostic fallback: rgba8/bgra8Unorm
Core Files:
  src/engine/hyperframe/motionBlurQualityPlanner.ts
  src/engine/hyperframe/frameDescriptor.ts
  src/engine/hyperframe/fxPassGraph.ts
  src/engine/hyperframe/sourceSurfaceProvider.ts
Adapter Files:
  src/engine/remake/composePreviewHtml.ts
  macos-native/Sources/MakelabMac/MotionBlurQualityPlanner.swift
  macos-native/Sources/MakelabMac/MetalRenderGraphFrameRenderer.swift
  macos-native/Sources/MakelabMac/NativeRenderEngine.swift
Diagnostics:
  motion-blur-adaptive-samples-selected
  motion-blur-samples-clamped-by-backend
  motion-blur-low-precision-accumulation
  motion-blur-canvas-readback-fallback
  motion-blur-playback-quality-downgrade
  motion-blur-subframe-descriptor-unavailable
  motion-blur-source-sample-unavailable
  motion-blur-core-sample-plan-unavailable
Tests / Verification:
  npm run motionfx:verify passes.
  swift build passes for macOS native app code.
  macOS motionBlur encoder lifecycle is guarded so motionTile compute passes cannot be opened inside an active motionBlur render encoder.
  Golden rendered frame suite is still required.
Known Issues:
  Needs final removal/blocking of platform-local planning fallback from preview/playback after adapter coverage is proven.
  Needs real golden frames for 359->1, 1->359, 720/1440 spin, off-center anchors, video + tile + blur.
  Needs high-precision accumulation proven outside text-contract checks.
User Review Notes:
  User confirmed the current artifact looks like low-sample temporal copies, not After Effects-quality blur.
  User requires Core-first FX development, not Web/macOS-specific patching.
  User reported that motionBlur alone kept the video size correct, but adding motionTile made the native preview look scaled.
  User reported a full app crash after adding motionBlur on top of rotation + motionTile; crash report showed Metal SIGABRT in applyMotionTile from renderMotionBlurTexture.
Agent Review Notes:
  Current build fixes the native preview source-resolution mismatch and Metal encoder lifecycle crash path, but visual confidence remains limited until golden frames exist.
Next Required Build Step:
  Add rendered golden-frame visual tests for extreme rotation and video + motionTile + blur.
Promotion Gate:
  Raise to 85% only after professional paths require Core-plan-only sample planning and high-precision accumulation is verified.
```

### motionBlur

```text
Track: upgrade
Status: corrective alias
Build %: 91
Quality Confidence %: 67
Last Updated: 2026-05-29
Current Implementation:
  Legacy authoring name normalizes toward transformMotionBlur.
  Export/runtime handoff now carries the serialized transformMotionBlur sample plan when available.
  Preview/playback calls now carry Core FXPassGraph through the preview pipeline when a render plan is available.
  Core export policy now supports cinematic sample counts through transformMotionBlur.
  Native preview alias execution inherits the corrected motionTile + transformMotionBlur sample source path.
  Native preview and export alias execution inherit the corrected Metal encoder lifecycle.
Current Values / Parameters:
  enabled
  strength/amount compatibility
  shutterAngle/shutterPhase compatibility
  samples | auto
Core Files:
  src/engine/hyperframe/effectNormalizer.ts
  src/project/types.ts
Adapter Files:
  Adapter execution is inherited from transformMotionBlur.
Diagnostics:
  Must inherit transformMotionBlur diagnostics.
Tests / Verification:
  npm run motionfx:verify passes.
Known Issues:
  Alias is only safe when transformMotionBlur itself reaches supported status.
User Review Notes:
  User expects motionBlur to mean professional shutter blur, not echo copies.
Agent Review Notes:
  Alias completeness is higher than visual confidence because final quality still depends on transformMotionBlur visual gates.
Next Required Build Step:
  Ensure every old motionBlur parameter maps into registry-backed canonical params.
Promotion Gate:
  Raise to supported only when transformMotionBlur is supported.
```

### motionTrail

```text
Track: upgrade
Status: registered
Build %: 35
Quality Confidence %: 25
Last Updated: 2026-05-29
Current Implementation:
  Effect intent exists, but it still needs strict separation from transformMotionBlur.
Current Values / Parameters:
  enabled
  decay/opacity-style trail params are expected but need canonical schema audit.
Core Files:
  src/project/types.ts
  src/engine/hyperframe/effectNormalizer.ts
Adapter Files:
  src/engine/remake/composePreviewHtml.ts
Diagnostics:
  Needs motion-trail-specific unsupported/fallback diagnostics.
Tests / Verification:
  npm run motionfx:verify checks presence only.
Known Issues:
  Must not be used as the implementation of shutter blur.
User Review Notes:
  User explicitly wants motionTrail separate from motionBlur.
Agent Review Notes:
  Needs a dedicated time-domain echo contract.
Next Required Build Step:
  Define canonical schema and pass type for trail/echo semantics.
Promotion Gate:
  Raise above 50% only after compiler/pass graph separation is explicit.
```

### motionTile

```text
Track: upgrade
Status: adapter-partial
Build %: 74
Quality Confidence %: 59
Last Updated: 2026-06-04
Current Implementation:
  Sampler/edge expansion exists in current web adapter paths.
  It is understood as edge-sampler behavior, not duplicated layers.
  macOS native preview now preserves the resolved motionTile texture through transformMotionBlur samples instead of applying tile scale to raw video samples.
  macOS native preview and Metal export run motionTile compute resolves before motionBlur render accumulation.
  ImGui native macOS preview adapter executes motionTileSampler as a Metal compute pass before FinalFrameSurface composite.
Current Values / Parameters:
  mode: mirror | repeat | clamp | linear
  expansion
  outputWidth
  outputHeight
  mirrorEdges compatibility
Core Files:
  src/project/types.ts
  src/engine/hyperframe/effectNormalizer.ts
  src/engine/hyperframe/fxPassGraph.ts
Adapter Files:
  src/engine/remake/composePreviewHtml.ts
  macos-native/Sources/MakelabMac/MetalFXRuntime.swift
  macos-native/Sources/MakelabMac/NativeRenderEngine.swift
  macos-native/Sources/MakelabMac/MetalRenderGraphFrameRenderer.swift
  apps/imgui/src/platform/macos/MacApp.mm
Diagnostics:
  playback-motion-tile-gpu-unavailable
Tests / Verification:
  npm run motionfx:verify passes.
Known Issues:
  Needs full platform adapter contract and cross-platform golden frames.
User Review Notes:
  User wants motionTile available as real FX, not duplicated footage.
  User confirmed disabling motionTile removed the scale artifact, and re-enabling motionTile brought it back before this corrective pass.
  User reported a native app crash when motionBlur was added after motionTile + rotation.
Agent Review Notes:
  Native preview now keeps motionTile tied to the resolved source texture path during transformMotionBlur and avoids nested Metal compute/render encoders, but rendered parity evidence is still required.
  ImGui native adapter follows the existing WebGPU expansion normalization rule: values under 1 expand by adding 1, values over 10 are interpreted as percentages.
  2026-06-04 corrective note: ImGui native motionTile now propagates boundsScaleX/Y into draw bounds around the same layer center, matching the Swift Metal renderer pattern instead of tiling inside the original rectangle.
  2026-06-04 corrective note: ImGui native motionTile now allocates intermediate textures at the expanded pixel dimensions before scaling draw bounds, preserving source pixel density and reducing soft/flickering tile edges.
Next Required Build Step:
  Move all behavior into canonical edge-sampler pass contract and add golden fixtures.
Promotion Gate:
  Raise above 75% only after Web/macOS adapter parity exists.
```

### gaussianBlur

```text
Track: upgrade
Status: adapter-partial
Build %: 62
Quality Confidence %: 47
Last Updated: 2026-06-04
Current Implementation:
  Effect intent exists and basic rendering paths are present.
  ImGui native macOS preview adapter executes gaussianBlur as a two-pass separable Metal compute pass before FinalFrameSurface composite.
Current Values / Parameters:
  radius/blur amount; exact canonical schema needs final audit.
Core Files:
  src/project/types.ts
  src/engine/hyperframe/effectNormalizer.ts
Adapter Files:
  src/engine/remake/composePreviewHtml.ts
  apps/imgui/src/platform/macos/MacApp.mm
Diagnostics:
  Needs explicit low-quality/fallback diagnostics.
Tests / Verification:
  npm run motionfx:verify checks presence.
Known Issues:
  Needs separable/GPU pass contract and golden frames.
User Review Notes:
  No specific user quality percentage recorded yet.
Agent Review Notes:
  Existing blur should be treated as partial until adapter parity and tests exist.
  ImGui native adapter clamps radius to the current native preview execution limit and does not promote visual quality without golden-frame evidence.
Next Required Build Step:
  Define radius units, quality policy, and adapter pass contract.
Promotion Gate:
  Raise above 70% only after golden frames and preview/export parity.
```

### radialBlur / spinBlur / zoomBlur / spiralEchoBlur

```text
Track: build
Status: planned
Build %: 25-30
Quality Confidence %: 15-20
Last Updated: 2026-05-29
Current Implementation:
  Some shader/effect names are present in the current web-oriented contract checks.
  The canonical Core taxonomy and adapter contract are not complete.
Current Values / Parameters:
  center policy required: layer | composition | explicit point
  edge policy required: mirror | clamp | repeat | transparent
  sample count required: adaptive or quality-tiered
  spin/zoom amount required per effect
Core Files:
  src/project/types.ts
  src/engine/hyperframe/effectNormalizer.ts
  src/engine/hyperframe/fxPassGraph.ts
Adapter Files:
  src/engine/remake/composePreviewHtml.ts
Diagnostics:
  motion-blur-radial-effect-required exists for routing confusion.
  Dedicated radial/spin/zoom diagnostics still needed.
Tests / Verification:
  npm run motionfx:verify passes name/presence checks.
Known Issues:
  Must not be routed through transformMotionBlur.
  Needs high-sample reconstruction and vortex golden frames.
User Review Notes:
  User's After Effects reference requires professional spin/radial quality.
Agent Review Notes:
  This family should be built as first-class spatial/hybrid FX after transformMotionBlur core planning is clean.
Next Required Build Step:
  Create separate canonical pass contracts for radialBlur/spinBlur/zoomBlur/spiralEchoBlur.
Promotion Gate:
  Raise above 50% only after registry schema, compiler, and one adapter pass are complete.
```

### glowStreak / chromaticSplit / shaderTransition

```text
Track: build
Status: planned
Build %: 20-25
Quality Confidence %: 10-15
Last Updated: 2026-05-29
Current Implementation:
  Names are present in effect intent and shader-effect contract checks.
  Production Core pass semantics are not complete.
Current Values / Parameters:
  To be defined per FX before implementation.
Core Files:
  src/project/types.ts
  src/engine/hyperframe/effectNormalizer.ts
Adapter Files:
  src/engine/remake/composePreviewHtml.ts
Diagnostics:
  Needs dedicated unsupported/fallback diagnostics.
Tests / Verification:
  npm run motionfx:verify checks presence only.
Known Issues:
  Must not be scene-only shader code.
User Review Notes:
  No user quality percentage recorded yet.
Agent Review Notes:
  Keep planned until schema/compiler/pass graph are real.
Next Required Build Step:
  Add individual FX cards when each one enters active build.
Promotion Gate:
  Raise above 40% only after registry schema and compiler nodes exist.
```

### Build Log

```text
Date: 2026-06-04
FX: transformMotionBlur / motionBlur / motionTile
Change Type: adapter execution / corrective
Before:
  ImGui native macOS preview could parse transformMotionBlur but did not execute true temporal shutter accumulation.
  Motion blur could only be diagnosed or approximated outside the ImGui native adapter.
  Premultiplied temporal accumulation was not separated from straight source texture drawing, risking soft/glowing alpha edges.
After:
  ImGui native macOS preview executes transformMotionBlur as sub-frame RenderGraph samples from the same clip motion.
  Each sample evaluates FrameDescriptor at its sample time, compiles a per-sample RenderGraph/FXPassGraph, resolves pre-transform FX such as motionTile, and accumulates into an RGBA16Float surface.
  Post-temporal shader FX can run after the accumulated motion surface before the FinalFrameSurface composite.
  The accumulated surface is composited through a premultiplied Metal fragment path to avoid double-alpha darkening or unstable bright edges.
  2026-06-04 corrective update: ImGui native preview now treats transformMotionBlur as transform-only shutter accumulation for the current source texture, avoiding per-sample video decode/seek and preventing multi-frame video smearing during preview.
  2026-06-04 corrective update: ImGui native preview caps transformMotionBlur at the preview quality budget and bypasses multi-sample accumulation when measured transform displacement is effectively zero.
  2026-06-04 quality correction: ImGui native transformMotionBlur no longer clamps every frame to 16 samples. Playback uses the Core playback ceiling of 24 samples, while paused preview uses the Core paused-preview ceiling of 64 samples and includes measured angular sweep in adaptive selection. This removes visible polygon/spoke breakup during large rotation without changing FX semantics.
Files Changed:
  apps/imgui/src/platform/macos/MacApp.mm
  docs/Professional HyperFrame FX Development Standard.md
Values / Methods Changed:
  transformMotionBlur Build %: 85 -> 88
  transformMotionBlur Quality Confidence %: 61 -> 64
  motionBlur Build %: 91 -> 92
  motionBlur Quality Confidence %: 67 -> 69
  motionTile Build %: 74 -> 75
  motionTile Quality Confidence %: 59 -> 60
Verification:
  cmake --build apps/imgui/build passed.
  npm run architecture:verify passed.
  npm run motionfx:verify passed.
Reviewer Notes:
  This is native adapter execution for existing HyperFrame FX contracts. It does not change Core semantics and does not give UI authority.
  Visual confidence remains capped until rendered golden-frame parity is captured for video + rotation + motionTile + transformMotionBlur.
Next Step:
  Retest the reported project visually, then add golden-frame parity coverage for preview/live scrub/export from FinalFrameSurface.
```

```text
Date: 2026-06-04
FX: motionTile / gaussianBlur / transformMotionBlur
Change Type: adapter execution
Before:
  ImGui native macOS preview only diagnosed style.effects and did not execute FXPassGraph adapter passes.
  motionTile and gaussianBlur were visible only through other platform/runtime paths.
  transformMotionBlur had no safe ImGui native temporal sample-plan executor.
After:
  ImGui native macOS preview parses canonical style.effects into native FX pass entries.
  motionTile executes as a Metal compute edge-sampler pass before FinalFrameSurface composite.
  gaussianBlur executes as a two-pass separable Metal compute pass before FinalFrameSurface composite.
  transformMotionBlur is preserved as an FXPassGraph diagnostic instead of a fake directional/echo blur.
Files Changed:
  apps/imgui/src/ui/EditorShell.hpp
  apps/imgui/src/platform/macos/MacApp.mm
  docs/Professional HyperFrame FX Development Standard.md
Values / Methods Changed:
  gaussianBlur Status: registered -> adapter-partial
  gaussianBlur Build %: 55 -> 62
  gaussianBlur Quality Confidence %: 45 -> 47
  motionTile adapter file coverage now includes apps/imgui/src/platform/macos/MacApp.mm
Verification:
  cmake --build apps/imgui/build passed.
Reviewer Notes:
  This is platform adapter execution for existing Core effect contracts, not new FX semantics.
  Golden-frame and Preview/Export parity evidence are still required before promotion.
Next Step:
  Mirror Core MotionBlurSamplePlan in the ImGui adapter before enabling transformMotionBlur pixels.
```

```text
Date: 2026-06-04
FX: motionTile
Change Type: corrective
Before:
  ImGui native motionTile sampled the mirrored source inside the original layer rectangle.
  Rotated clips looked like the video was shrunk and tiled inside itself instead of extending edge pixels into the rotation gaps.
After:
  ImGui native motionTile preserves the compute-resolved texture and propagates boundsScaleX/Y into the draw node.
  The draw node expands around the same layer center/anchor before FinalFrameSurface composite, matching the Swift Metal renderer pattern.
  Intermediate motionTile textures are now allocated at expanded pixel dimensions so source pixels are not stretched after bounds expansion.
Files Changed:
  apps/imgui/src/platform/macos/MacApp.mm
  docs/Professional HyperFrame FX Development Standard.md
Values / Methods Changed:
  motionTile adapter execution now returns boundsScaleX/Y instead of only a texture.
  motionTile adapter allocation now uses ceil(sourceTextureSize * effectiveExpansion), clamped to the native texture limit.
Verification:
  cmake --build apps/imgui/build passed.
Reviewer Notes:
  This corrects adapter geometry only; Core effect semantics remain unchanged.
Next Step:
  Add golden-frame comparison for rotation + motionTile mirror.
```

```text
Date: 2026-05-29
FX: transformMotionBlur / motionBlur
Change Type: upgrade
Before:
  FXPassGraph exposed sampleBudget for transformMotionBlur but did not serialize the full MotionBlurSamplePlan.
  Export runtime.renderFrame received frame/profile only.
  Runtime motion blur relied on local sample planning whenever it rendered.
After:
  FXPassGraph transformMotionBlur passes serialize motionBlurSamplePlan.
  MotionBlurSamplePlan diagnostics are carried on the pass.
  FinalFrameStream computes the Core FXPassGraph for export and passes it into runtime.renderFrame.
  Runtime renderFrame accepts provided fxPassGraph and exposes it through frame diagnostics.
  Runtime temporal video/sample code consumes the Core motionBlurSamplePlan when present.
Files Changed:
  src/engine/hyperframe/fxPassGraph.ts
  src/engine/hyperframe/finalFrameStream.ts
  src/engine/export/types.ts
  src/engine/hyperframe/previewPipeline.ts
  src/engine/remake/composePreviewHtml.ts
  scripts/verify-motion-fx-contract.mjs
  docs/Professional HyperFrame FX Development Standard.md
Values / Methods Changed:
  transformMotionBlur Build %: 65 -> 72
  transformMotionBlur Quality Confidence %: 45 -> 48
  motionBlur Build %: 80 -> 83
  motionBlur Quality Confidence %: 55 -> 58
Verification:
  npm run motionfx:verify passed.
  npm run build passed.
Reviewer Notes:
  This is a Core-plan handoff step, not final visual quality closure.
Next Step:
  Make preview/playback/render entry points provide Core FXPassGraph, then remove private planning fallback.
```

```text
Date: 2026-05-29
FX: transformMotionBlur / motionBlur
Change Type: upgrade
Before:
  Export path could provide a Core FXPassGraph, but preview seek and playback were still calling runtime.renderFrame/playFrom without a Core graph.
After:
  previewPipeline creates Core FXPassGraph from HyperFrameRenderPlan for pausedPreview and interactive seek.
  App passes previewRenderPlan into preview seek, interactive timeline seek, live patch seek, and playback.
  Runtime playFrom accepts a Core FXPassGraph provider and playback frames request per-frame Core graphs.
  Runtime uses provided graph as frame diagnostics and motion blur sample-plan source.
Files Changed:
  src/App.tsx
  src/engine/hyperframe/previewPipeline.ts
  src/vite-env.d.ts
  src/engine/remake/composePreviewHtml.ts
  scripts/verify-motion-fx-contract.mjs
  docs/Professional HyperFrame FX Development Standard.md
Values / Methods Changed:
  transformMotionBlur Build %: 72 -> 78
  transformMotionBlur Quality Confidence %: 48 -> 50
  motionBlur Build %: 83 -> 86
  motionBlur Quality Confidence %: 58 -> 60
Verification:
  npm run motionfx:verify passed.
  npm run build passed.
Reviewer Notes:
  Preview/playback now participate in Core graph handoff, but visual confidence remains capped until golden-frame evidence exists.
Next Step:
  Add golden-frame visual tests and then make missing Core plans block professional export-quality blur.
```

```text
Date: 2026-05-29
FX: transformMotionBlur / motionBlur
Change Type: corrective
Before:
  Core export quality policy still capped motion blur at 48 samples.
  Runtime could fall back to local sample planning in export if the Core motionBlurSamplePlan was missing.
  Verification checked contracts textually, but did not execute a sample-plan fixture.
After:
  Core export quality policy allows up to 192 motion blur samples.
  Export-quality runtime blur refuses local sample planning when the Core sample plan is absent.
  Added motion-blur sample-plan verification fixture for extreme rotation.
  The fixture verifies selected sample count, cap behavior, diagnostics, shutter window, sample times, and normalized weights.
Files Changed:
  src/engine/hyperframe/canonicalFrameRenderer.ts
  src/engine/remake/composePreviewHtml.ts
  scripts/verify-motion-fx-contract.mjs
  scripts/verify-motion-blur-sample-plan.mjs
  package.json
  docs/Professional HyperFrame FX Development Standard.md
Values / Methods Changed:
  Core export max motion samples: 48 -> 192
  transformMotionBlur Build %: 78 -> 82
  transformMotionBlur Quality Confidence %: 50 -> 55
  motionBlur Build %: 86 -> 88
  motionBlur Quality Confidence %: 60 -> 62
Verification:
  npm run motionfx:verify passed both contract and sample-plan fixture.
  npm run build passed.
Reviewer Notes:
  This adds algorithmic sample-plan proof, not final rendered pixel proof.
Next Step:
  Add rendered golden-frame visual tests for extreme rotation and video + motionTile + blur.
```

```text
Date: 2026-05-29
FX: transformMotionBlur / motionBlur / motionTile
Change Type: corrective
Before:
  macOS native preview passed motionTile boundsScale into transformMotionBlur samples but drew raw per-sample video textures.
  Re-enabling motionTile with transformMotionBlur could visually scale/enlarge the video because destination bounds expansion was mixed with an unresolved source texture.
After:
  macOS native preview compiles the per-sample FXPassGraph during transformMotionBlur accumulation.
  Each temporal sample resolves its own source/pre-transform FX texture before drawing.
  MotionTile expansion now travels with sampleResolved.texture and sampleResolved.boundsScale together, avoiding raw-video-plus-expanded-bounds mismatch.
Files Changed:
  macos-native/Sources/MakelabMac/NativeRenderEngine.swift
  scripts/verify-motion-fx-contract.mjs
  docs/Professional HyperFrame FX Development Standard.md
Values / Methods Changed:
  transformMotionBlur Build %: 82 -> 84
  transformMotionBlur Quality Confidence %: 55 -> 60
  motionBlur Build %: 88 -> 90
  motionBlur Quality Confidence %: 62 -> 66
  motionTile Build %: 65 -> 72
  motionTile Quality Confidence %: 50 -> 58
Verification:
  npm run motionfx:verify passed.
  swift build passed for macOS native app code.
Reviewer Notes:
  This fixes the native preview execution bug behind the user-reported scale artifact. It is not yet a golden-frame proof.
Next Step:
  Rebuild/open the macOS app and visually test motionTile + transformMotionBlur on the reported project, then add golden-frame regression coverage.
```

```text
Date: 2026-05-29
FX: transformMotionBlur / motionBlur / motionTile
Change Type: corrective
Before:
  macOS native preview opened a motionBlur render encoder and then attempted to run motionTile compute resolves inside that active encoder.
  Metal aborted the app with SIGABRT / MTLReportFailure when motionBlur was added on top of rotation + motionTile.
  Metal export had the same encoder ordering risk.
After:
  Native preview resolves all per-sample source/pre-transform FX textures before opening the motionBlur accumulation render encoder.
  Metal export uses the same resolve-before-render ordering.
  Contract verification now checks the encoder lifecycle ordering for both preview and export.
Files Changed:
  macos-native/Sources/MakelabMac/NativeRenderEngine.swift
  macos-native/Sources/MakelabMac/MetalRenderGraphFrameRenderer.swift
  scripts/verify-motion-fx-contract.mjs
  docs/Professional HyperFrame FX Development Standard.md
Values / Methods Changed:
  transformMotionBlur Build %: 84 -> 85
  transformMotionBlur Quality Confidence %: 60 -> 61
  motionBlur Build %: 90 -> 91
  motionBlur Quality Confidence %: 66 -> 67
  motionTile Build %: 72 -> 74
  motionTile Quality Confidence %: 58 -> 59
Verification:
  npm run motionfx:verify passed.
  swift build passed for macOS native app code.
Reviewer Notes:
  Crash reports showed MTLReportFailure -> applyMotionTile -> renderMotionBlurTexture. The fix changes encoder ordering, not sample quality.
Next Step:
  Rebuild/open the macOS app and retest the exact rotation + motionTile + motionBlur scene, then add golden-frame and crash-regression coverage.
```

## 8. Required Core Artifacts

Every FX must define these Core artifacts:

```text
FXRegistry entry
parameter schema
default values
unit definitions
bounds
aliases
legacy migration
normalizer
compiler
FXPassGraph node type
resource dependencies
pass ordering rules
capability requirements
diagnostics
quality policy
golden fixtures
UI metadata
```

If one artifact is missing, the FX is not complete.

## 9. Adapter Contract

Each platform adapter consumes the same Core plan.

```text
FXPassGraph node
-> adapter capability check
-> source resolve
-> intermediate texture allocation
-> pass execution
-> diagnostics
-> final surface
```

Allowed adapter differences:

```text
Metal vs WebGPU vs WebGL2 vs Vulkan vs DirectX implementation
texture formats available
sample caps
performance budgets
fallback availability
hardware color/format limitations
```

Forbidden adapter differences:

```text
different effect meaning
different parameter units
different aliases
private sample planning
silent fallback
UI-only parameters
encoder-side compositing
duplicated timeline layers
```

## 10. Quality Profiles

Profiles may change budgets, not meaning.

```text
interactive
playback
pausedPreview
render
export
```

Profiles may change:

```text
sample count within Core policy
texture scale within Core policy
cache strategy
diagnostic strictness
adapter fallback permission
```

Profiles must not change:

```text
effect semantics
layer order
transform meaning
sample distribution meaning
alpha compositing policy
source selection
fallback success/failure semantics
```

## 11. Diagnostics

Silent fallback is forbidden.

Required diagnostic classes:

```text
fx-unsupported
fx-unsupported-param
fx-adapter-pass-missing
fx-capability-missing
fx-quality-downgrade
fx-low-precision-target
fx-source-sample-unavailable
fx-source-sample-approximated
fx-sample-count-clamped
fx-fallback-used
fx-golden-parity-failed
```

Diagnostics must appear in preview/render/export reports when relevant.

## 12. UI And Agent Contract

UI and agents author intent only:

```text
clip.style.effects.<effectName>
```

UI controls must be generated from or validated against FX Registry metadata. Agents must not create scene-only FX, duplicated media layers, hidden canvas loops, CSS-only effects, or platform-only parameters.

Correct:

```text
one layer
-> canonical FX intent
-> Core plan
-> adapter execution
```

Incorrect:

```text
duplicate media layers to fake blur/trails
scene.js-only effect
DOM/CSS-only effect truth
BMF effect graph
platform renderer invents parameters
```

## 13. Motion Blur V2 Standard

`transformMotionBlur` is the current highest-risk corrective FX and must follow this stricter standard.

It is a temporal compositor pass:

```text
frame index
-> shutter window
-> adaptive sample plan
-> evaluate FrameDescriptor at each sample time
-> resolve source/media at each sample time
-> render layer samples into isolation target
-> high-precision weighted accumulation
-> normalized premultiplied output
-> composite once at layer z-index
```

Core planner inputs:

```text
effect params
fps
shutterAngle
shutterPhase
amount
layer transform across shutter
layer bounds and anchor
composition size
quality profile
platform capability declaration
```

Core planner outputs:

```text
shutterStartTime
shutterEndTime
sampleTimes[]
weights[]
estimatedMaxPixelDisplacement
estimatedAngularSweep
requiredSampleCount
selectedSampleCount
qualityTier
diagnostics[]
```

Recommended export sample targets:

```text
normal motion: 16-32
fast translation or scale: 32-64
strong rotation: 64-128
extreme spin/vortex transform blur: 128-192 when backend allows
stylized radial/spin/spiral: 64-160 shader samples depending on spread
```

Required precision:

```text
preferred: rgba16Float
acceptable: rgba16Unorm
last-resort diagnostic fallback: rgba8/bgra8Unorm
```

Required motion blur diagnostics:

```text
motion-blur-adaptive-samples-selected
motion-blur-samples-clamped-by-backend
motion-blur-low-precision-accumulation
motion-blur-canvas-readback-fallback
motion-blur-playback-quality-downgrade
motion-blur-subframe-descriptor-unavailable
motion-blur-source-sample-unavailable
motion-blur-core-sample-plan-unavailable
motion-blur-radial-effect-required
```

Required motion blur golden fixtures:

```text
fast transform rotation 360/720/1440 degrees per second
rotation boundary 359 degrees -> 1 degree
rotation boundary 1 degree -> 359 degrees
authored multiple-turn spin
off-center anchor rotation
large video with motionTile mirror + transformMotionBlur
transparent PNG with rotation blur
text/shape layer with scale + rotation blur
radial spin blur vortex
spiral echo blur transition
preview/export same-frame comparison
cross-platform diagnostic and golden parity
```

`motionTrail`, `radialBlur`, `spinBlur`, `zoomBlur`, and `spiralEchoBlur` are separate FX families. They must not be used to fake `transformMotionBlur`.

## 14. Pass Ordering

Default order:

```text
sourceResolve
-> edge-sampler FX
-> pre-transform spatial FX
-> temporal-transform FX
-> post-transform spatial FX
-> composite / mask / border / shadow
-> adjustment / group / transition FX
-> final composite
```

Any FX that changes ordering must document why and add regression fixtures.

## 15. Acceptance Gates

An FX is complete only when:

```text
1. Catalog entry exists.
2. Registry schema exists.
3. Normalizer handles aliases and migration.
4. Compiler emits FXPassGraph node.
5. Unsupported adapters emit diagnostics.
6. At least one adapter executes the compiled plan.
7. Preview/render/export use the same semantics.
8. UI params map to registry params.
9. Golden-frame tests exist.
10. Cross-platform parity expectations are documented.
11. Fallbacks are explicit and reported.
12. No duplicate layer workaround is required.
```

## 16. Change Request Template

Every FX implementation or correction should begin with this template:

```text
FX:
Track: build | upgrade
Current status:
Target status:
Family:
Core schema changes:
Normalizer changes:
Compiler / FXPassGraph changes:
Adapter execution changes:
Diagnostics:
Golden fixtures:
Preview/export parity checks:
UI metadata:
Acceptance gates:
Files expected to change:
```

If this template cannot be filled, the work is not ready to implement.

## 17. Forbidden Forever

```text
Web-only FX source of truth
macOS-only FX source of truth
BMF/WebCodecs/native encoder FX
duplicated media layers as FX
scene-only FX
DOM/CSS-only visual truth
private platform sample planners
silent unsupported fallback
UI sliders without registry parameters
declaring support without tests
calling a diagnostic fallback professional quality
```

No pass, no FX.
No schema, no FX.
No diagnostics, no FX.
No preview/export parity, no FX.
