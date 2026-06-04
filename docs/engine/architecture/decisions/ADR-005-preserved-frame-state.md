# ADR-005: Preserved Frame State

Status: accepted.

Date: 2026-05-31.

## Decision

During interactive Browser preview, a previous complete frame may remain visible while a newer frame is late.

It must be reported as:

```text
preserved
degraded
reason visible in diagnostics
```

It must never be reported as a newly rendered frame. It is forbidden during deterministic render and export.
