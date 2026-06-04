import type { WorkspaceComposition, WorkspaceTimelineClip, WorkspaceTimelineTrack } from "../contracts/projectTypes";
import type {
  HyperFrameGateIssue,
  HyperFrameIR,
  HyperFrameIRLayer,
  HyperFrameMotionFxCapability,
  HyperFrameMotionFxCapabilityReport,
  HyperFrameTransactionIntent,
} from "../contracts/types";
import {
  canonicalEffectNames,
  duplicateProneEffectNames,
  getHyperFrameEffectEntries,
  getHyperFrameEffectParamIssues,
  getHyperFrameEnabledEffectNames,
  isHyperFrameEffectEnabled,
} from "./effectNormalizer";

type ClipWithTrack = {
  clip: WorkspaceTimelineClip;
  track: WorkspaceTimelineTrack;
};

const shaderEffectNames = new Set([
  "motionBlur",
  "radialBlur",
  "zoomBlur",
  "spiralEchoBlur",
  "glowStreak",
  "chromaticSplit",
  "shaderTransition",
]);

const blockedEffectNames = new Set<string>();

const fakeEchoClipNamePattern = /(?:motion\s*blur|vortex|spiral|fx).{0,32}echo|echo.{0,32}(?:motion\s*blur|vortex|spiral|fx)/i;

const getEnabledEffectNames = (clip: WorkspaceTimelineClip) => (
  getHyperFrameEnabledEffectNames(clip.style)
);

const hasDuplicateProneEffect = (clip: WorkspaceTimelineClip) => (
  getEnabledEffectNames(clip).some((name) => duplicateProneEffectNames.has(name))
);

const isLargeVisualClip = (clip: WorkspaceTimelineClip, composition: WorkspaceComposition) => {
  const width = Number(clip.style?.width) || 0;
  const height = Number(clip.style?.height) || 0;
  const compositionArea = Math.max(1, composition.width * composition.height);
  return (width * height) / compositionArea >= 0.25;
};

const maxOverlap = (clips: WorkspaceTimelineClip[]) => {
  const events = clips.flatMap((clip) => {
    const start = Number(clip.start) || 0;
    const end = start + Math.max(0, Number(clip.duration) || 0);
    return [
      { time: start, delta: 1 },
      { time: end, delta: -1 },
    ];
  }).sort((a, b) => a.time === b.time ? a.delta - b.delta : a.time - b.time);

  let active = 0;
  let peak = 0;
  for (const event of events) {
    active += event.delta;
    peak = Math.max(peak, active);
  }
  return peak;
};

const issueSeverityForIntent = (intent: HyperFrameTransactionIntent): HyperFrameGateIssue["severity"] => (
  intent === "export" || intent === "preview" ? "error" : "warning"
);

const getMotionFxExecutionRequirement = (kind: string): HyperFrameMotionFxCapability["executionRequirement"] => (
  kind === "motionBlur"
    ? "temporal"
    : shaderEffectNames.has(kind)
      ? "shader"
      : blockedEffectNames.has(kind)
        ? "unsupported"
        : "raster"
);

const getMotionFxStatus = (kind: string): HyperFrameMotionFxCapability["status"] => (
  blockedEffectNames.has(kind) ? "blocked" : "active"
);

const getMotionFxReason = (kind: string) => {
  if (kind === "motionBlur") {
    return "motionBlur is handled by the renderer-owned temporal transform accumulation pass.";
  }
  if (shaderEffectNames.has(kind)) {
    return `${kind} requires a platform shader Motion FX pass.`;
  }
  if (blockedEffectNames.has(kind)) {
    return `${kind} is registered as a first-class Motion FX intent, but its transition-layer shader pass is not active yet.`;
  }
  return `${kind} is handled by the current cached Canvas/FX runtime policy.`;
};

const maxLayerOverlap = (layers: HyperFrameIRLayer[]) => {
  const events = layers.flatMap((layer) => ([
    { time: layer.timing.start, delta: 1 },
    { time: layer.timing.end, delta: -1 },
  ])).sort((a, b) => a.time === b.time ? a.delta - b.delta : a.time - b.time);

  let active = 0;
  let peak = 0;
  for (const event of events) {
    active += event.delta;
    peak = Math.max(peak, active);
  }
  return peak;
};

const isLargeVisualLayer = (layer: HyperFrameIRLayer, composition: WorkspaceComposition) => {
  const width = Number(layer.style?.width) || 0;
  const height = Number(layer.style?.height) || 0;
  const compositionArea = Math.max(1, composition.width * composition.height);
  return (width * height) / compositionArea >= 0.25;
};

export const createMotionFxCapabilityReport = (ir: HyperFrameIR): HyperFrameMotionFxCapabilityReport => {
  const effectsByKind = new Map<string, Set<string>>();
  for (const layer of ir.layers) {
    for (const name of getHyperFrameEnabledEffectNames(layer.style)) {
      const layerIds = effectsByKind.get(name) ?? new Set<string>();
      layerIds.add(layer.id);
      effectsByKind.set(name, layerIds);
    }
  }

  const capabilities: HyperFrameMotionFxCapability[] = Array.from(effectsByKind.entries())
    .map(([kind, layerIds]) => ({
      kind,
      layerIds: Array.from(layerIds),
      executionRequirement: getMotionFxExecutionRequirement(kind),
      status: getMotionFxStatus(kind),
      reason: getMotionFxReason(kind),
    }));

  const effectLayerIds = Array.from(new Set(capabilities.flatMap((capability) => capability.layerIds)));
  const gpuRequiredLayerIds = Array.from(new Set(
    capabilities
      .filter((capability) => capability.executionRequirement === "unsupported")
      .flatMap((capability) => capability.layerIds),
  ));
  const blockedLayerIds = Array.from(new Set(
    capabilities
      .filter((capability) => capability.status === "blocked")
      .flatMap((capability) => capability.layerIds),
  ));

  const duplicateHeavyVideoAssetIds: string[] = [];
  const duplicatedHeavyVideoGroups = new Map<string, HyperFrameIRLayer[]>();
  for (const layer of ir.layers) {
    if (layer.kind !== "video" || !layer.asset?.id) continue;
    if (!isLargeVisualLayer(layer, ir.composition)) continue;
    const enabledEffectNames = getHyperFrameEnabledEffectNames(layer.style);
    if (!enabledEffectNames.some((name) => duplicateProneEffectNames.has(name))) continue;
    const group = duplicatedHeavyVideoGroups.get(layer.asset.id) ?? [];
    group.push(layer);
    duplicatedHeavyVideoGroups.set(layer.asset.id, group);
  }
  for (const [assetId, group] of duplicatedHeavyVideoGroups) {
    if (group.length >= 3 && maxLayerOverlap(group) >= 3) duplicateHeavyVideoAssetIds.push(assetId);
  }

  const messages = [
    capabilities.length > 0 ? `Motion FX planner detected ${capabilities.length} active effect kind(s) across ${effectLayerIds.length} layer(s).` : "",
    gpuRequiredLayerIds.length > 0 ? `${gpuRequiredLayerIds.length} layer(s) require a GPU Motion FX pass that is not active yet.` : "",
    duplicateHeavyVideoAssetIds.length > 0 ? `${duplicateHeavyVideoAssetIds.length} duplicated heavy-video Motion FX asset group(s) were blocked to prevent preview lag.` : "",
    ...capabilities.map((capability) => `${capability.kind}: ${capability.reason}`),
  ].filter((message) => message.length > 0);

  return {
    version: 1,
    activeEffectCount: capabilities.length,
    effectLayerIds,
    gpuRequiredLayerIds,
    blockedLayerIds,
    duplicateHeavyVideoAssetIds,
    capabilities,
    messages,
  };
};

export const validateMotionFxCapabilities = ({
  intent,
  composition,
  tracks,
}: {
  intent: HyperFrameTransactionIntent;
  composition: WorkspaceComposition;
  tracks: WorkspaceTimelineTrack[];
}): HyperFrameGateIssue[] => {
  const issues: HyperFrameGateIssue[] = [];
  const clipsWithTrack: ClipWithTrack[] = tracks.flatMap((track) => (
    track.clips.map((clip) => ({ track, clip }))
  ));

  for (const { clip, track } of clipsWithTrack) {
    const effectEntries = getHyperFrameEffectEntries(clip.style);
    const enabledEffectNames = effectEntries
      .filter(([, value]) => isHyperFrameEffectEnabled(value))
      .map(([name]) => name);
    const unknownEffectKey = effectEntries.find(([name]) => !canonicalEffectNames.has(name));
    if (unknownEffectKey) {
      issues.push({
        severity: issueSeverityForIntent(intent),
        code: "unsupported-motion-fx",
        message: `Unsupported Motion FX "${unknownEffectKey[0]}" is present. Add it to the canonical effect registry or normalize it before preview/export instead of letting it pass silently.`,
        clipId: clip.id,
        trackId: track.id,
        assetId: clip.assetId,
      });
    }

    const unknownEffect = enabledEffectNames.find((name) => !canonicalEffectNames.has(name));
    if (unknownEffect) {
      issues.push({
        severity: issueSeverityForIntent(intent),
        code: "unsupported-motion-fx",
        message: `Unsupported Motion FX "${unknownEffect}" is active. Add it to the canonical effect registry before preview/export instead of approximating it in scene code.`,
        clipId: clip.id,
        trackId: track.id,
        assetId: clip.assetId,
      });
    }

    for (const [effectName, effectValue] of effectEntries) {
      if (!canonicalEffectNames.has(effectName)) continue;
      for (const paramIssue of getHyperFrameEffectParamIssues(effectName, effectValue)) {
        if (paramIssue.legacy) {
          issues.push({
            severity: "warning",
            code: "legacy-motion-fx-schema",
            message: `Motion FX "${effectName}.${paramIssue.param}" is legacy schema and is normalized to "${effectName}.${paramIssue.alias}". Prefer the canonical key in timeline.json.`,
            clipId: clip.id,
            trackId: track.id,
            assetId: clip.assetId,
          });
        } else {
          issues.push({
            severity: issueSeverityForIntent(intent),
            code: "unsupported-motion-fx",
            message: `Unsupported Motion FX parameter "${effectName}.${paramIssue.param}" is present. Use only canonical renderer-owned FX schema.`,
            clipId: clip.id,
            trackId: track.id,
            assetId: clip.assetId,
          });
        }
      }
    }

    const blockedEffect = enabledEffectNames.find((name) => blockedEffectNames.has(name));
    if (blockedEffect) {
      issues.push({
        severity: issueSeverityForIntent(intent),
        code: "gpu-motion-fx-not-active",
        message: `${blockedEffect} is a first-class GPU Motion FX intent, but the transition-layer shader pass is not active in this build yet. Do not fake it with duplicated layers.`,
        clipId: clip.id,
        trackId: track.id,
        assetId: clip.assetId,
      });
    }

    if (clip.type === "video" && fakeEchoClipNamePattern.test(String(clip.name || ""))) {
      issues.push({
        severity: issueSeverityForIntent(intent),
        code: "duplicated-heavy-video-motion-fx",
        message: `Video clip "${clip.name}" looks like an Echo/Motion Blur/Vortex duplicate. Use one source clip with style.effects instead of generated echo layers.`,
        clipId: clip.id,
        trackId: track.id,
        assetId: clip.assetId,
      });
    }
  }

  const duplicatedHeavyVideoGroups = new Map<string, ClipWithTrack[]>();
  for (const item of clipsWithTrack) {
    const { clip } = item;
    if (clip.type !== "video" || !clip.assetId) continue;
    if (!hasDuplicateProneEffect(clip)) continue;
    if (!isLargeVisualClip(clip, composition)) continue;
    const group = duplicatedHeavyVideoGroups.get(clip.assetId) ?? [];
    group.push(item);
    duplicatedHeavyVideoGroups.set(clip.assetId, group);
  }

  for (const [assetId, group] of duplicatedHeavyVideoGroups) {
    const peakOverlap = maxOverlap(group.map((item) => item.clip));
    if (group.length < 3 || peakOverlap < 3) continue;
    const first = group[0];
    issues.push({
      severity: issueSeverityForIntent(intent),
      code: "duplicated-heavy-video-motion-fx",
      message: `Detected ${peakOverlap} overlapping large video layers using the same asset with Motion FX. This causes preview lag; use one layer with style.effects motion intent and a renderer-owned GPU/cached effect pass.`,
      clipId: first.clip.id,
      trackId: first.track.id,
      assetId,
    });
  }

  return issues;
};
