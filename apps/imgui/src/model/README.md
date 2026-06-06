# Shared Workspace Model

This folder owns the platform-neutral editor state passed between Gates,
shared UI, frame query, authoring, and platform render executors.

Rules:

- UI may read these structs and send commands from them.
- Platform adapters may consume these structs after Gates accept a project.
- Platform adapters must not reinterpret timing, layer, animation, or FX meaning.
- New shared layer fields are added here first, then consumed by macOS and
  Windows through the same model.

