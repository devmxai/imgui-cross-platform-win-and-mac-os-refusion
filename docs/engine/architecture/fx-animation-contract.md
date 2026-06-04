# FX And Animation Contract

FX and animation behavior is Core-first.

## Required Flow

```text
FX registry / animation contract
  -> normalizer
  -> planner
  -> FrameDescriptor
  -> FXPassGraph
  -> platform capability gate
  -> adapter implementation
  -> diagnostics
  -> golden-frame parity
```

## Supported Status

An FX is not supported just because one platform can draw something.

Supported means:

```text
Core schema exists
normalization exists
sample/planner behavior exists when needed
capability gates exist
at least one adapter implementation exists
fallback diagnostics exist
golden-frame or contract tests exist
```

Cross-platform supported means the same contract passes on each advertised platform.

## Active FX Ledger

The current implementation ledger remains:

```text
docs/Professional HyperFrame FX Development Standard.md
```

Until fully migrated, update that ledger for every FX build percentage, quality percentage, test result, fallback, and known issue.

## Forbidden Shortcuts

```text
platform-only FX names
duplicate UI-only effects
silent fallback to low-quality rendering
duplicate filler layers as a replacement for a real FX contract
declaring support before capability gates pass
```
