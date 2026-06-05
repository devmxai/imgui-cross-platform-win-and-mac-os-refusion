# Timeline Truth V2 Execution Master Plan

Status: approved for implementation by user request. Phase 1, Phase 2, Phase 4, Phase 5, and Phase 9 are implemented; Phase 3, Phase 7, Phase 8, and Phase 10 are in progress.

Decision scope: native ImGui desktop editor, macOS first, Windows second, with one cross-platform timing and frame-truth contract.

This plan exists to remove every independent time authority from the application. The editor must behave like a professional compositor/editor: one timeline truth, one accepted frame truth, one pixel truth, and one render path.

## 1. Non-Negotiable Frame Path

The only accepted frame path is:

```text
UI Command
-> TimelineCoordinator
-> UnitedGate
-> HyperFrame Timeline Truth
-> HyperFrame IR
-> FrameDescriptor(frameIndex)
-> RenderGraph
-> FXPassGraph
-> FinalFrameSurface
-> Preview / Live Scrub / Export
```

The UI is not part of timing truth, visual truth, media truth, or export truth.

Forbidden:

```text
UI-owned playback clock
UI-owned render clock
UI-generated preview pixels
UI-side media decoding
UI-side layer composition
UI-side FX interpretation
wall-clock accepted playhead state
MediaPlayer preview fallback
WebView preview fallback
Canvas preview fallback
partial frame marked as ready
stale source frame marked as accepted
export that interprets timeline/layers/FX independently
agent query that guesses from raw JSON only
```

## 2. OpenTimelineIO Boundary

OpenTimelineIO is allowed only for precise time math and interchange boundaries.

Allowed:

```text
OpenTimelineIO opentime
-> RationalTime
-> TimeRange
-> TimeTransform
-> OpenTimeAdapter
-> UnitedGate
```

Forbidden:

```text
OpenTimelineIO types inside PlatformRenderFrameExecutor
OpenTimelineIO types inside TimelineCoordinator runtime state
OpenTimelineIO Timeline as project source of truth
OpenTimelineIO effects/metadata as render truth
OpenTimelineIO becoming the native scheduler
```

HyperFrame Timeline Truth is the internal source of truth. OpenTime is a precision tool at the boundary, not the application brain.

## 3. Canonical Time Model

Introduce one internal time model:

```cpp
struct FrameRate {
  int64_t numerator;
  int64_t denominator;
};

struct FrameIndex {
  int64_t value;
};

struct FrameRange {
  int64_t startFrame;
  int64_t endFrame; // exclusive
};

struct FrameDuration {
  int64_t frames;
};

struct TimelinePosition {
  FrameIndex frame;
  FrameRate rate;
};
```

Rules:

```text
FrameIndex is the visual timeline authority.
FrameRange is always half-open: [startFrame, endFrame).
FrameRate preserves rational rates such as 24000/1001, 30000/1001, 60000/1001.
Seconds are display/interop values only.
Milliseconds are display/diagnostic values only.
double seconds must not be stored in commands, accepted frame state, or renderer requests.
```

Derived display values:

```text
seconds = frameIndex * rate.denominator / rate.numerator
timecode = derived from FrameIndex + FrameRate
milliseconds = derived diagnostic only
```

## 4. Source Time Mapping

Timeline time and media source time are different concepts.

Canonical media mapping:

```cpp
struct SourceTimeMap {
  FrameRange timelineRange;
  FrameIndex sourceInFrame;
  FrameRate sourceRate;
  TimeTransformPolicy transformPolicy;
};
```

Rules:

```text
Clip placement is timeline frame based.
Trim/source sampling is source frame or source rational-time based.
Video/image/text/shape visibility is timeline frame based.
Animation and temporal FX may evaluate subframe rational samples.
Audio uses sampleIndex + sampleRate and is reconciled through the timeline rate.
```

OpenTime `TimeTransform` may be used to calculate `SourceTimeMap`, but the renderer consumes `SourceTimeMap`, not OpenTime itself.

## 5. Project Contract Migration

Current project files may still contain legacy seconds fields. V2 must canonicalize them at the gate.

Accepted project fields after migration:

```json
{
  "timebase": {
    "rate": {
      "numerator": 30000,
      "denominator": 1001
    },
    "rangePolicy": "half-open"
  },
  "tracks": [
    {
      "clips": [
        {
          "startFrame": 90,
          "durationFrames": 120,
          "trimInFrame": 0
        }
      ]
    }
  ]
}
```

Compatibility rules:

```text
Legacy start/duration seconds may be read temporarily.
UnitedGate converts legacy seconds once into canonical frame fields.
Canonical frame fields are authoritative when present.
Ambiguous timing is rejected, not silently repaired.
Out-of-range timing is rejected, not clamped silently.
duration <= 0 is rejected, not rewritten to a magic fallback.
```

## 6. UnitedGate Requirements

UnitedGate becomes the first enforcement point for timing truth.

It must validate:

```text
composition width/height positive
timeline rate valid
durationFrames positive
clip startFrame non-negative
clip durationFrames positive
clip endFrame <= composition durationFrames
asset IDs exist
track IDs match ownership
media clips reference accepted assets
source ranges are valid for known media duration
keyframes can be resolved to rational/subframe time
FX declarations are accepted by the current HyperFrame FX schema
```

UnitedGate must output:

```text
accepted project revision
canonical Timeline Truth
diagnostics
rejection reasons
```

UnitedGate must not:

```text
silently clamp invalid clips
silently invent clip duration
silently accept unknown assets
silently accept invalid FX schema
```

## 7. Commands

All editor commands must be frame based.

Allowed command shape:

```text
OpenProject(path)
ImportAsset(path)
AddClip(assetId, trackId, startFrame)
AddText(trackId, startFrame, durationFrames)
AddShape(trackId, startFrame, durationFrames)
SetPlayhead(frameIndex)
BeginPlayback
StopPlayback
BeginScrub(generation)
ScrubTo(frameIndex, generation)
EndScrub(generation)
RequestPreviewFrame(frameIndex)
RequestExport(profile)
```

Forbidden command shape:

```text
ScrubTimeline(seconds)
AddClip(seconds)
SetPlayhead(seconds)
RequestPreviewFrame(seconds)
```

Seconds may exist in UI labels only.

## 8. TimelineCoordinator

Introduce one scheduler/coordinator for all interactive frame truth.

State:

```cpp
struct TimelineCoordinatorState {
  FrameIndex desiredFrame;
  FrameIndex requestedFrame;
  FrameIndex acceptedFrame;
  ProjectRevision acceptedRevision;
  bool playing;
  uint64_t requestGeneration;
};
```

Rules:

```text
Wall clock may propose the next desired frame.
Wall clock never directly becomes acceptedFrame.
UI displays acceptedFrame only.
Preview requests use requestedFrame.
Only accepted render results update acceptedFrame.
Rejected/preserved results do not advance the visible playhead.
```

Playback flow:

```text
BeginPlayback
-> TimelineCoordinator computes desired frame from host clock
-> RequestPreviewFrame(desiredFrame)
-> renderer returns accepted/preserved/rejected
-> accepted updates acceptedFrame
-> UI displays acceptedFrame
```

Scrub flow:

```text
BeginScrub(generation)
-> ScrubTo(frameIndex, generation)
-> cancel older generations
-> render latest requested frame
-> accepted updates acceptedFrame
-> EndScrub(generation)
```

## 9. FinalFrameSurface Result Contract

Rendering must return an explicit result, not only a texture pointer.

```cpp
enum class FinalFrameStatus {
  Accepted,
  Preserved,
  Rejected
};

struct FinalFrameSurfaceResult {
  FinalFrameStatus status;
  ProjectRevision revision;
  uint64_t requestId;
  FrameIndex requestedFrame;
  FrameIndex surfaceFrame;
  int width;
  int height;
  PixelFormat pixelFormat;
  ColorSpace colorSpace;
  GpuTextureHandle texture;
  ResourceLifetimeToken lifetime;
  Diagnostics diagnostics;
};
```

Accepted means:

```text
all required sources exact or explicitly valid for the requested frame
all required render passes completed
all required FX passes completed
GPU command buffer completed or resource lifetime is protected
surfaceFrame == requestedFrame
revision == accepted project revision
```

Preserved means:

```text
preview/live scrub may keep the previous accepted surface
acceptedFrame does not advance
diagnostic explains the blocked requested frame
export cannot use preserved
```

Rejected means:

```text
no surface mutation
no acceptedFrame update
no export frame
diagnostic is mandatory
```

## 10. FrameDescriptor Authority

FrameDescriptor must be evaluated from canonical frame truth.

Input:

```text
ProjectRevision
FrameIndex
RenderProfile
optional subframe sample for temporal FX
```

Output:

```text
activeLayerIds
layer order
evaluated timing
evaluated geometry
evaluated opacity
evaluated transforms
evaluated corner radius
evaluated borders/shadows/glow
normalized effects
motion velocities
diagnostics
```

The platform renderer must consume this descriptor. It must not rebuild HyperFrame semantics independently.

## 11. Pixel-True Canvas Contract

Composition coordinates:

```text
coordinateSpace: composition-pixels
origin: top-left
units: px
rounding: float-until-raster-boundary
alpha: premultiplied
colorSpace: explicit
```

Viewport transform:

```cpp
struct CanvasViewTransform {
  double scale;
  double offsetX;
  double offsetY;
  int compositionWidth;
  int compositionHeight;
  int viewportWidth;
  int viewportHeight;
};
```

Rules:

```text
Preview aspect ratio comes from composition width/height.
9:16 is used only when the project is 9:16.
Device pixel ratio does not change composition coordinates.
Timeline zoom does not change composition coordinates.
viewport -> composition -> viewport round trip error must be < 0.5 px.
```

## 12. Agent Query Contract

The agent must read evaluated truth, not guess from raw JSON.

Required API shape:

```text
queryProjectRevision()
queryTimelineTruth(revision)
queryFrame(revision, frameIndex)
queryLayerAtPixel(revision, frameIndex, x, y)
```

`queryFrame` returns:

```text
revision
frameIndex
timecode
active layers
FrameDescriptor layer geometry
z-order
asset references
text content
shape type
effects
diagnostics
surface metadata when available
```

Acceptance example:

```text
If text starts at frame 90 and duration is 60 frames,
queryFrame(revision, 90) must report the text active.
queryFrame(revision, 149) must report the text active.
queryFrame(revision, 150) must report the text inactive.
```

## 13. Timeline UI Rendering

The UI may draw timeline visuals only from accepted project state.

Timeline viewport:

```cpp
struct TimelineViewport {
  FrameIndex firstVisibleFrame;
  double pixelsPerFrame;
  int width;
};
```

Mapping:

```text
x = (frameIndex - firstVisibleFrame) * pixelsPerFrame
frameIndex = firstVisibleFrame + round(x / pixelsPerFrame)
```

Rules:

```text
Clip visual width reflects frame duration.
Minimum click target may exist as an overlay, not as timing truth.
Ruler ticks derive from FrameRate and zoom.
Playhead uses acceptedFrame.
```

## 14. Live Scrub

Live scrub must prioritize correctness and responsiveness without creating a second clock.

Rules:

```text
BeginScrub creates a generation.
ScrubTo sends frameIndex + generation.
Only newest generation can publish a result.
Old requests are cancelled or ignored.
Preserved keeps previous acceptedFrame.
Rejected keeps previous acceptedFrame.
Accepted updates acceptedFrame.
```

Live scrub must not:

```text
advance the playhead from mouse position before acceptance
display stale frame as requested frame
decode through a UI-owned media path
```

## 15. Export

Export consumes the same frame truth.

Export loop:

```text
for frameIndex in [0, frameCount):
  request FinalFrameSurface(frameIndex, exportProfile)
  if accepted:
    encode exact surface
  else:
    fail export with diagnostics
```

Export must not:

```text
interpret timeline layers
interpret FX
use playback clock
use preserved frames
use approximate frames silently
use UI preview pixels
```

Preview and export may use different quality policies, but must use the same source-of-truth chain and produce the same creative result.

## 16. Implementation Phases

### Phase 0 - Approval Gate

No implementation begins until this plan is approved.

Deliverable:

```text
approved Timeline Truth V2 plan
explicit implementation command from the user
```

### Phase 1 - Contracts And Types

Add cross-platform domain types:

```text
FrameRate
FrameIndex
FrameRange
FrameDuration
TimelinePosition
SourceTimeMap
ProjectRevision
```

Acceptance:

```text
unit tests for 24, 25, 30, 50, 60, 24000/1001, 30000/1001, 60000/1001
no renderer dependency on these tests
```

### Phase 2 - OpenTime Adapter

Add an adapter around `RationalTime`, `TimeRange`, and `TimeTransform`.

Acceptance:

```text
OpenTime conversions are isolated
OpenTime types do not appear in renderer/scheduler headers
round-trip tests pass for fractional frame rates
```

### Phase 3 - UnitedGate Canonicalization

Make project load and project edits produce canonical timeline truth.

Acceptance:

```text
legacy seconds convert once
canonical frame fields are authoritative
invalid timing rejected
no silent duration repair
asset and track validation active
```

### Phase 4 - Frame-Based Commands

Replace second-based commands with frame-based commands.

Acceptance:

```text
UI command payloads carry frameIndex
authoring service writes canonical frame timing
seconds remain display-only
```

### Phase 5 - TimelineCoordinator And Accepted Frame

Introduce one coordinator and explicit render result status.

Acceptance:

```text
playhead updates only on accepted
preserved/rejected do not advance playhead
partial/stale source frames cannot be marked accepted
```

### Phase 6 - Core Descriptor Bridge

Stop platform-specific semantic duplication.

Acceptance:

```text
native adapter consumes Core FrameDescriptor/RenderGraph/FXPassGraph contracts
verifier rejects duplicate local frame math and local HyperFrame semantic compilers
```

### Phase 7 - Pixel-True Canvas And Agent Query

Add evaluated frame query and viewport transform.

Acceptance:

```text
queryFrame matches FrameDescriptor
non-9:16 projects preserve aspect ratio
viewport/composition transform error < 0.5 px
```

### Phase 8 - Live Scrub

Rebuild scrub around frame generations.

Acceptance:

```text
latest generation wins
old scrub requests cannot publish
reverse scrub and forward scrub use the same path
```

### Phase 9 - Export

Connect export to FinalFrameSurface iteration.

Acceptance:

```text
export loops frameIndex
preserved/rejected blocks export
preview/export descriptor hash parity exists
```

### Phase 10 - Verifiers And Golden Tests

Add hard architecture checks.

Acceptance:

```text
verifier rejects UI clock truth
verifier rejects seconds-based runtime commands
verifier rejects duplicate frame math
verifier rejects fake preview fallback
golden frame tests compare preview/export/agent truth
```

## 17. Required Tests

Timing:

```text
frame 0 start
clip [90, 150)
clip boundary at fractional frame rates
trim and split at exact frames
source time transform
timecode display from frame index
```

Playback:

```text
accepted advances playhead
preserved does not advance playhead
rejected does not advance playhead
stale video texture cannot be accepted
```

Canvas:

```text
composition pixel mapping
non-9:16 aspect ratio
animated text position at frame
shape bounds at frame
layer picking by pixel
```

Parity:

```text
agent query == FrameDescriptor
timeline visible clip range == Timeline Truth
preview descriptor hash == export descriptor hash
preview pixel hash == export pixel hash for supported deterministic profiles
```

## 18. Stop Conditions

Stop implementation and report diagnostics if any of these occur:

```text
HyperFrame Core must be modified outside approved scope
OpenTime leaks into renderer/scheduler
UI requires a timing workaround
preview needs MediaPlayer/WebView/Canvas fallback
export needs a separate layer interpreter
partial frame is required to appear as ready
project files cannot be canonicalized by UnitedGate
```

## 19. Definition Of Done

Timeline Truth V2 is complete only when:

```text
UI sends frame-based commands only
one TimelineCoordinator owns desired/requested/accepted frame state
UnitedGate canonicalizes all project timing
FinalFrameSurface has accepted/preserved/rejected status
playhead follows acceptedFrame only
FrameDescriptor is the evaluated canvas truth
Agent query uses accepted revision + evaluated FrameDescriptor
Live scrub cannot publish old generations
Export consumes FinalFrameSurface frames only
architecture verifiers reject forbidden paths
golden tests prove timeline/preview/live scrub/export/agent parity
```

Until then, any working preview is considered transitional, not professionally complete.
