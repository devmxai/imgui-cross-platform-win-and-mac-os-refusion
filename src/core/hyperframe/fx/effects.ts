import type { VisualLayerStyle } from "../contracts/projectTypes";

type LayerWithStyle = {
  style: VisualLayerStyle;
};

const isObject = (value: unknown): value is Record<string, unknown> => (
  Boolean(value) && typeof value === "object" && !Array.isArray(value)
);

const isPositiveNumber = (value: unknown) => (
  typeof value === "number" && Number.isFinite(value) && value > 0
);

const isEnabledEffect = (value: unknown) => {
  if (value === true) return true;
  if (value === false || value == null) return false;
  if (!isObject(value)) return false;
  if (value.enabled === true) return true;
  if (isPositiveNumber(value.radius)) return true;
  if (isPositiveNumber(value.angleSpread)) return true;
  if (isPositiveNumber(value.zoomSpread)) return true;
  if (isPositiveNumber(value.radialSpread)) return true;
  if (isPositiveNumber(value.distance)) return true;
  if (isPositiveNumber(value.amount)) return true;
  if (typeof value.shader === "string" && value.shader.length > 0) return true;
  return false;
};

export const layerHasActiveEffectIntent = (layer: LayerWithStyle) => {
  const effects = layer.style.effects ?? {};
  return (
    isEnabledEffect(effects.motionBlur)
    || isEnabledEffect(effects.motionTrail)
    || isEnabledEffect(effects.motionTile)
    || isEnabledEffect(effects.gaussianBlur)
    || isEnabledEffect(effects.radialBlur)
    || isEnabledEffect(effects.zoomBlur)
    || isEnabledEffect(effects.spiralEchoBlur)
    || isEnabledEffect(effects.glowStreak)
    || isEnabledEffect(effects.chromaticSplit)
    || isEnabledEffect(effects.shaderTransition)
  );
};

export const getActiveEffectIntentNames = (layer: LayerWithStyle) => {
  const effects = layer.style.effects ?? {};
  return ([
    ["motionBlur", effects.motionBlur],
    ["motionTrail", effects.motionTrail],
    ["motionTile", effects.motionTile],
    ["gaussianBlur", effects.gaussianBlur],
    ["radialBlur", effects.radialBlur],
    ["zoomBlur", effects.zoomBlur],
    ["spiralEchoBlur", effects.spiralEchoBlur],
    ["glowStreak", effects.glowStreak],
    ["chromaticSplit", effects.chromaticSplit],
    ["shaderTransition", effects.shaderTransition],
  ] as const)
    .filter(([, value]) => isEnabledEffect(value))
    .map(([name]) => name);
};

export const getActiveFilterNames = (layer: LayerWithStyle) => {
  const filters = layer.style.filters;
  if (!filters) return [];
  return ([
    ["blur", filters.blur > 0],
    ["exposure", filters.exposure !== 0],
    ["brightness", filters.brightness !== 1],
    ["contrast", filters.contrast !== 1],
    ["saturation", filters.saturation !== 1],
    ["hue", filters.hue !== 0],
    ["grayscale", filters.grayscale > 0],
    ["sepia", filters.sepia > 0],
    ["invert", filters.invert > 0],
  ] as const)
    .filter(([, active]) => active)
    .map(([name]) => name);
};

export const layerHasActiveFilter = (layer: LayerWithStyle) => (
  getActiveFilterNames(layer).length > 0
);

export const layerHasActiveEffects = (layer: LayerWithStyle) => (
  layerHasActiveEffectIntent(layer) || layerHasActiveFilter(layer)
);
