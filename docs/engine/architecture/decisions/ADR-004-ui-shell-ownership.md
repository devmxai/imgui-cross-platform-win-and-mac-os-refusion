# ADR-004: UI Shell Ownership

Status: accepted.

Date: 2026-05-31.

## Decision

Browser React UI and Windows WinUI own layout, interaction intent, command dispatch, state display, and diagnostics display only.

```text
UI command out
adapter/session state in
diagnostics in
```

The UI must not render pixels, interpret timeline meaning, execute FX, choose FX pass ordering, own the frame clock, decode media, or produce export frames.
