# ImGui Source Layout

This folder is split into shared editor code and platform adapters.

```text
ui/
  Shared Dear ImGui shell. Commands and display only.

model/
  Shared workspace, asset, track, and clip state accepted by Gates.

timeline/
  Shared frame/time helpers for editor timeline truth.

authoring/
  Shared project editing services and accepted project writes.

query/
  Shared frame and layer query services for agent-visible truth.

render/
  Shared FinalFrameSurface request/status contract for platform executors.

platform/
  Native adapters. Platform-specific hardware and OS integration only.
```

Rules:

```text
Shared features belong in shared folders.
Native hardware belongs in platform folders.
The UI never owns render, decode, time, FX, or export truth.
Platforms never change timeline or FX meaning.
Preview, live scope, and export consume FinalFrameSurface.
Shared structs live in model/, not in UI.
Native render status lives in render/, not in a platform-only fork.
```
