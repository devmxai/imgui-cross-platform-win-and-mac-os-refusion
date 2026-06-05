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

Native editor icons:

```text
Inter 4.1 Regular for all editor text
Font Awesome Free 7.2.0 Solid
apps/imgui/assets/fonts/Inter-Regular.ttf
apps/imgui/assets/fonts/fa-solid-900.otf
apps/imgui/third_party/inter/LICENSE.txt
apps/imgui/third_party/font-awesome/LICENSE.txt
```

The fonts are vendored so macOS and Windows use the same visual sources.
Inter Regular is the single editor text face. Font Awesome is loaded only for
icon glyphs. Both remain display-only UI assets.

Project authoring boundary:

```text
ImGui library controls
-> command + payload only
-> ProjectAuthoringService
-> candidate project validation
-> atomic assets/assets.json or timeline.json replacement
-> accepted workspace reload
-> existing HyperFrame render path
```

The top-right `Open Folder` command binds a project workspace. The media and
audio library add tiles import accepted files into `assets/originals` and
`assets/assets.json`; they never open a project folder. Double-clicking an
accepted media or audio asset sends `AddAssetClip`. Text, background, and shape
library sections send their own authoring commands. ImGui never writes project
files directly.

Open Folder uses native asynchronous `NSOpenPanel` sheet presentation. The
folder picker must appear before any project load, watcher setup, or
FinalFrameSurface request begins; project ingestion starts only after the user
accepts a folder URL.

Native project refresh:

```text
macOS FSEventStream observes the opened project folder
-> source signature checks canonical project paths
-> UnitedGate-compatible accepted workspace reload
-> stale native source caches invalidated
-> Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph
-> refreshed FinalFrameSurface
```

The watcher observes `project.json`, `composition.json`, `timeline.json`,
`assets/assets.json`, `assets/originals`, and `native-scenes/main`. Changes are
debounced. Invalid or partially written JSON never replaces the previous
accepted project state. The top-right `Render` command performs the same
accepted reload and FinalFrameSurface refresh immediately.

Native export boundary:

```text
RequestExport
-> for frameIndex in [0, durationFrames)
-> MacMetalRenderFrameExecutor.render(..., waitForCompletion=true)
-> FinalFrameSurfaceResult must be Accepted
-> AVAssetWriter MP4 frame append
```

Export does not interpret layers, FX, timing, or media independently. It fails
on preserved or rejected FinalFrameSurface frames.

Native performance and parity proof:

```text
MacMetalRenderFrameExecutor / scheduler
-> render submit timing
-> asynchronous Live Scope readback timing
-> requested frame / accepted frame / generation
-> display-only ImGui telemetry panel
```

The telemetry panel is observational only. It does not own clock truth, frame
truth, render state, or FX behavior.

Scrub commands are frame-only. The editor shell may format seconds for display,
but command payloads do not carry timeline seconds and the native command bridge
rejects reintroducing a `timelineTimeSeconds` path.
Transport timecode is also formatted from accepted frame indices through
`makelab::timeline::FrameToClockTimecode`; UI-owned floating-second formatting
is not used for the playhead display.

`FrameTruthFingerprint` gives tests a deterministic evaluated-frame identity.
`frame-truth-parity-tests` verifies that agent query, preview truth, and export
iteration consume the same evaluated frame meaning for mixed layer projects.

Native pixel parity smoke:

```bash
"apps/imgui/build/Makelab IMGUI Professional.app/Contents/MacOS/Makelab IMGUI Professional" \
  --pixel-parity-smoke /absolute/path/to/workspace
```

This headless smoke uses the same `MacMetalRenderFrameExecutor`, renders an
accepted `FinalFrameSurface` frame for preview and export-frame iteration, reads
both through the native Metal readback helper, and fails when their BGRA8 pixel
hashes differ.

CTest also runs the deterministic fixture:

```bash
ctest --test-dir apps/imgui/build -R final-frame-surface-pixel-parity-smoke --output-on-failure
```

Native performance smoke:

```bash
"apps/imgui/build/Makelab IMGUI Professional.app/Contents/MacOS/Makelab IMGUI Professional" \
  --performance-smoke /absolute/path/to/workspace \
  --frames 30
```

This headless smoke uses the same `MacMetalRenderFrameExecutor` and measures
accepted `FinalFrameSurface` render timing against the workspace frame budget.
It does not run UI clock logic and does not add any preview fallback.

CTest also runs the deterministic performance fixture:

```bash
ctest --test-dir apps/imgui/build -R final-frame-surface-performance-smoke --output-on-failure
```

Heavy FX parity and performance fixtures:

```bash
ctest --test-dir apps/imgui/build -R final-frame-surface-heavy-fx --output-on-failure
```

The heavy fixture is fully portable and contains background, shape, and text
layers with rounded corners, borders, shadows, gaussian blur, motionTile mirror,
and transform-motion-blur through the same accepted `FinalFrameSurface` path.

Build:

```bash
cmake -S apps/imgui -B apps/imgui/build
cmake --build apps/imgui/build
```

Run production shell:

```bash
open "apps/imgui/build/Makelab IMGUI Professional.app"
```

Install the current build as a normal user application:

```bash
cmake --install apps/imgui/build --prefix "$HOME/Applications"
```

Run visual fixture shell for screenshot parity work only:

```bash
open "apps/imgui/build/Makelab IMGUI Professional.app" --args --design-fixture
```

`--design-fixture` is not a preview path. It only fills the asset and timeline panels with visual state so the native UI can be compared against the locked 3360x1824 reference screenshot.

Run with a workspace path for Open Folder smoke testing:

```bash
open "apps/imgui/build/Makelab IMGUI Professional.app" --args --open-workspace /absolute/path/to/workspace
```
