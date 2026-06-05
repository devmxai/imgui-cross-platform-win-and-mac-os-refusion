# Current macOS Status

Status date: 2026-06-04.

Portable source branch:

```text
main
```

Initial checkpoint tag:

```text
macos-working-v0.1.0
```

## Validated

```text
Native macOS application builds successfully.
Dear ImGui remains command/display only.
Metal displays FinalFrameSurface.
Open Folder loads accepted project state.
Playback and scrub are driven by the native scheduler.
Video, image, text, shape, and background nodes reach the native render path.
motionTile executes as a pre-transform Metal pass.
gaussianBlur executes as a native Metal pass.
transformMotionBlur uses adaptive temporal transform samples.
Large rotation blur uses up to 64 paused-preview samples and 24 playback samples.
Transform motion blur reuses the accepted source texture across temporal samples.
The corrected smooth spiral transform-motion-blur result is included.
FrameDescriptor rounded corners clip shape, image, video, and other visual layer textures in Metal.
RenderGraph border composite executes after the layer texture.
RenderGraph drop shadow composite executes before the layer texture.
Font Awesome Free 7.2.0 Solid is vendored and loaded as the native editor icon font.
Inter 4.1 Regular is the single native editor text face.
The editor shell uses compact dimensions with a 13px base font and a 9.5px timeline ruler.
Top toolbar, left rail, command buttons, transport controls, and track controls use one consistent icon system.
The icon font is a UI display asset only and has no rendering, playback, clock, or timeline authority.
The asset-library add tile now sends native ImportMedia or ImportAudio commands and is independent from Open Folder.
Open Folder presents the native NSOpenPanel asynchronously as a sheet before project loading begins, avoiding a blocking `runModal` picker path.
Text, background, and shape library sections send command payloads through the shared C++ ProjectAuthoringService.
Accepted imports are copied into assets/originals and recorded in assets/assets.json.
Accepted layer commands atomically replace timeline.json, reload accepted workspace state, and then use the existing FinalFrameSurface path.
Focused ProjectAuthoringService tests verify accepted media/text/background/shape authoring and prove rejected commands do not mutate timeline.json.
The opened project is monitored recursively by native macOS FSEventStream using the same source paths as the UnitedGate reference full signature.
External changes are debounced, re-ingested as candidate accepted state, and preserve the previous accepted state when JSON is incomplete or invalid.
Accepted external changes invalidate stale image/generated/video source caches before requesting the refreshed FinalFrameSurface.
The top-right Render command explicitly reloads accepted project files and requests the same native render path.
The top-right Export command iterates FinalFrameSurfaceResult frames and writes MP4 through AVAssetWriter.
Export rejects preserved/rejected FinalFrameSurface frames and does not interpret timeline layers or FX independently.
NativeAudioGraph now accepts readable audio tracks from video and audio assets using the same accepted project state, respecting hidden/muted tracks and frame-based clip timing.
Native playback audio uses AVAudioEngine/AVAudioPlayerNode PCM segments scheduled from the accepted AudioGraph and commanded by TimelineCoordinator; it is not a video player, preview renderer, or clock authority.
Export muxes accepted AudioGraph tracks into the MP4 after the FinalFrameSurface video stream is written, so embedded video audio and imported audio assets are preserved in exported files without giving the encoder visual render authority.
Live Scope consumes the accepted FinalFrameSurface snapshot and displays luma/RGB scope data without owning render or clock truth.
Live Scope readback is asynchronous and guarded so playback and scrub do not block on GPU readback.
Native performance telemetry displays render submit time, Live Scope readback time, frame budget, FinalFrameSurface memory size, requested frame, accepted frame, and request generation.
FrameQueryService exposes evaluated queryFrame, queryLayerAtPixel, and pixel-true canvas transforms for agent-visible truth.
Focused FrameQueryService tests verify half-open frame ranges, layer pixel hit testing, viewport round trips, and export-frame iteration parity.
FrameTruthFingerprint provides deterministic evaluated-frame parity proof for preview/export/agent truth inputs.
FrameTruthParityTests prove agent query, preview truth, and export iteration use the same evaluated frame fingerprint across mixed video/text/shape/background layers.
Timeline scrub commands are frame-only; the ImGui shell no longer emits timeline seconds through command payloads.
The verifier rejects UI clock ownership and rejects any reintroduced `timelineTimeSeconds` command bridge.
Transport timecode is formatted from accepted frame indices through `makelab::timeline::FrameToClockTimecode`.
The app binary includes a headless --pixel-parity-smoke mode that renders preview/export FinalFrameSurface frames, reads BGRA8 pixels through the native Metal readback helper, and compares pixel hashes.
The repository includes a deterministic pixel-parity workspace fixture and CTest target `final-frame-surface-pixel-parity-smoke`.
The app binary includes a headless --performance-smoke mode that measures accepted FinalFrameSurface render timing through MacMetalRenderFrameExecutor against the workspace frame budget.
SVG image assets are accepted through the same image layer contract: the native adapter rasterizes SVG through pinned LunaSVG into a Metal texture, prewarms static image/SVG textures after an accepted workspace load, then RenderGraph/FXPassGraph composites them into the single FinalFrameSurface used by preview, Live Scope, and export.
Generated text/shape/background source textures are prewarmed after an accepted workspace load so dense text layers do not pay first-rasterization cost during live scrub.
Video assets remain AVFoundation/VideoToolbox texture sources only. The native executor now prewarms a bounded set of video CVMetalTexture frames after an accepted workspace load so first playback frames do not synchronously pay decoder setup on the preview path.
Live scrub requests remain frame-index commands only. The native executor now prewarms a bounded forward/reverse video texture window around the requested frame before submitting the same FinalFrameSurface request.
Preview rendering is scheduled on a native serial FinalFrameSurface render queue. The ImGui draw loop displays the latest accepted surface and never owns render execution or clock truth.
The repository includes a deterministic performance workspace fixture and CTest target `final-frame-surface-performance-smoke`.
The repository includes a portable heavy-FX workspace fixture and CTest targets `final-frame-surface-heavy-fx-pixel-parity-smoke`, `final-frame-surface-heavy-fx-performance-smoke`, and `final-frame-surface-heavy-fx-scrub-performance-smoke`.
The CMake install target installs the app bundle into a persistent Applications location selected by the install prefix.
Objective-C++ ARC is enabled.
Video texture cache is bounded.
Idle rendering is event-driven and measured at approximately 0% CPU.
The complete current source path from Gates through FinalFrameSurface and ImGui is preserved on main.
```

## Verification

The checkpoint was validated with:

```bash
cmake -S apps/imgui -B apps/imgui/build
cmake --build apps/imgui/build
npm run verify
```

`npm run verify` checks the ImGui architecture, portable source manifest,
HyperFrame Core-relative imports, and FX registry manifest.

## Remaining Work

```text
Windows Direct3D / Media Foundation platform adapter
expanded golden pixel-hash fixtures for real media projects
additional Core-declared FX adapter execution
```

This status does not claim that all future editor features are complete. It records that the current native macOS checkpoint builds, runs, previews accepted projects, and preserves the required architecture boundaries.
