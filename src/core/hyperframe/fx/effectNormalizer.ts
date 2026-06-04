import type { VisualLayerStyle } from "../contracts/projectTypes";
import type { HyperFrameEffectInstance, HyperFrameEffectKind } from "../contracts/types";

export const canonicalEffectNames = new Set([
  "motionBlur",
  "motionTrail",
  "motionTile",
  "gaussianBlur",
  "radialBlur",
  "zoomBlur",
  "spiralEchoBlur",
  "glowStreak",
  "chromaticSplit",
  "shaderTransition",
]);

export const allowedEffectParams: Record<string, Set<string>> = {
  motionBlur: new Set([
    "enabled",
    "algorithm",
    "strength",
    "samples",
    "shutter",
    "shutterAngle",
    "shutterPhase",
    "sampleCurve",
    "blur",
    "opacity",
    "edgeMode",
    "quality",
  ]),
  motionTrail: new Set([
    "enabled",
    "algorithm",
    "strength",
    "samples",
    "shutter",
    "shutterAngle",
    "shutterPhase",
    "sampleCurve",
    "blur",
    "opacity",
    "edgeMode",
    "quality",
  ]),
  motionTile: new Set([
    "enabled",
    "mode",
    "expansion",
    "outputWidth",
    "outputHeight",
    "mirrorEdges",
    "strength",
    "samples",
    "spacing",
    "opacity",
    "quality",
  ]),
  gaussianBlur: new Set(["enabled", "radius", "blur", "quality"]),
  radialBlur: new Set(["enabled", "center", "angleSpread", "samples", "decay", "opacity", "quality"]),
  zoomBlur: new Set(["enabled", "center", "zoomSpread", "samples", "decay", "opacity", "chromaticFringe", "quality"]),
  spiralEchoBlur: new Set([
    "enabled",
    "center",
    "angleSpread",
    "zoomSpread",
    "radialSpread",
    "samples",
    "decay",
    "shutter",
    "opacity",
    "blendMode",
    "chromaticFringe",
    "quality",
  ]),
  glowStreak: new Set(["enabled", "angle", "distance", "samples", "decay", "opacity", "threshold", "quality"]),
  chromaticSplit: new Set(["enabled", "amount", "angle", "opacity", "quality"]),
  shaderTransition: new Set(["enabled", "shader", "progress", "duration", "opacity", "chromaticFringe", "quality"]),
};

export const legacyEffectParamAliases: Record<string, Record<string, string>> = {
  spiralEchoBlur: {
    radius: "zoomSpread",
    twist: "angleSpread",
    rings: "samples",
    echoOpacity: "opacity",
    vortexSmear: "radialSpread",
  },
};

export const duplicateProneEffectNames = new Set([
  "motionBlur",
  "motionTrail",
  "motionTile",
  "radialBlur",
  "zoomBlur",
  "spiralEchoBlur",
  "glowStreak",
  "chromaticSplit",
  "shaderTransition",
]);

const canonicalKindBySource: Record<string, HyperFrameEffectKind> = {
  motionBlur: "transformMotionBlur",
  motionTrail: "motionTrail",
  motionTile: "motionTile",
  gaussianBlur: "gaussianBlur",
  radialBlur: "radialBlur",
  zoomBlur: "zoomBlur",
  spiralEchoBlur: "spiralEchoBlur",
  glowStreak: "glowStreak",
  chromaticSplit: "chromaticSplit",
  shaderTransition: "shaderTransition",
};

const isRecord = (value: unknown): value is Record<string, unknown> => (
  Boolean(value) && typeof value === "object" && !Array.isArray(value)
);

const isPositiveNumber = (value: unknown) => (
  typeof value === "number" && Number.isFinite(value) && value > 0
);

const hasActiveParam = (value: Record<string, unknown>) => (
  isPositiveNumber(value.radius)
  || isPositiveNumber(value.angleSpread)
  || isPositiveNumber(value.zoomSpread)
  || isPositiveNumber(value.radialSpread)
  || isPositiveNumber(value.distance)
  || isPositiveNumber(value.amount)
  || typeof value.shader === "string" && value.shader.length > 0
);

export const isHyperFrameEffectEnabled = (value: unknown) => {
  if (value === true) return true;
  if (value === false || value == null) return false;
  if (!isRecord(value)) return false;
  if (value.enabled === true) return true;
  return hasActiveParam(value);
};

export const normalizeHyperFrameEffectValue = (name: string, value: unknown): Record<string, unknown> => {
  if (value === true) return { enabled: true };
  if (value === false || value == null || !isRecord(value)) return { enabled: false };
  const next: Record<string, unknown> = { ...value };
  const aliases = legacyEffectParamAliases[name] ?? {};
  for (const [legacyKey, canonicalKey] of Object.entries(aliases)) {
    if (next[canonicalKey] === undefined && next[legacyKey] !== undefined) {
      if (name === "spiralEchoBlur" && legacyKey === "twist") {
        next[canonicalKey] = Math.max(0, Math.abs(Number(next[legacyKey]) || 0) * 360);
      } else if (name === "spiralEchoBlur" && legacyKey === "radius") {
        next[canonicalKey] = Math.max(0, (Number(next[legacyKey]) || 0) / 100);
      } else if (name === "spiralEchoBlur" && legacyKey === "rings") {
        next[canonicalKey] = Math.max(1, Math.round(Number(next[legacyKey]) || 0) * 2 + 1);
      } else {
        next[canonicalKey] = next[legacyKey];
      }
    }
  }
  if (next.enabled !== false && next.enabled !== true && hasActiveParam(next)) next.enabled = true;
  return next;
};

export const getHyperFrameEffectEntries = (style: { effects?: unknown } | undefined) => {
  const effects = isRecord(style?.effects) ? style.effects : {};
  return Object.entries(effects);
};

export const getHyperFrameEnabledEffectNames = (style: { effects?: unknown } | undefined) => (
  getHyperFrameEffectEntries(style)
    .filter(([, value]) => isHyperFrameEffectEnabled(value))
    .map(([name]) => name)
);

export const getHyperFrameEffectParamIssues = (name: string, value: unknown) => {
  if (!isRecord(value)) return [];
  const allowedParams = allowedEffectParams[name];
  if (!allowedParams) return [];
  const aliases = legacyEffectParamAliases[name] ?? {};
  return Object.keys(value)
    .map((param) => {
      if (allowedParams.has(param)) return null;
      if (aliases[param]) return { param, alias: aliases[param], legacy: true };
      return { param, alias: "", legacy: false };
    })
    .filter((issue): issue is { param: string; alias: string; legacy: boolean } => Boolean(issue));
};

const normalizeQuality = (value: unknown): HyperFrameEffectInstance["quality"] => (
  value === "interactive" || value === "preview" || value === "export" ? value : "auto"
);

export const normalizeHyperFrameEffects = (
  style: Pick<VisualLayerStyle, "effects"> | undefined,
  layerId = "layer",
): HyperFrameEffectInstance[] => (
  getHyperFrameEffectEntries(style)
    .filter(([name]) => canonicalEffectNames.has(name))
    .map(([name, value]) => {
      const params = normalizeHyperFrameEffectValue(name, value);
      return {
        id: `${layerId}:${name}`,
        source: name,
        kind: canonicalKindBySource[name],
        enabled: isHyperFrameEffectEnabled(params),
        params,
        quality: normalizeQuality(params.quality),
        scope: "node" as const,
      };
    })
    .filter((effect) => effect.enabled)
);
