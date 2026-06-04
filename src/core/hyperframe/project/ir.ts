import type { WorkspaceAsset, WorkspaceTimelineClip } from "../contracts/projectTypes";
import type { HyperFrameAuthoringModel, HyperFrameIR, HyperFrameIRLayer, HyperFrameIRLayerKind } from "../contracts/types";
import { createHyperFramePixelFrameContract } from "../frame/pixelFrameContract";

const toLayerKind = (type: WorkspaceTimelineClip["type"], fallback: HyperFrameIRLayerKind): HyperFrameIRLayerKind => {
  if (type === "unknown") return fallback;
  return type;
};

export const compileHyperFrameIR = (model: HyperFrameAuthoringModel): HyperFrameIR => {
  const assetsById = new Map(model.assets.map((asset) => [asset.id, asset]));
  const visibleClips = model.clips.filter((clip) => !clip.hidden);
  const layers = visibleClips.map<HyperFrameIRLayer>((clip, index) => {
    const asset = clip.assetId ? assetsById.get(clip.assetId) : undefined;
    const assetRef: HyperFrameIRLayer["asset"] | undefined = asset
      ? {
        id: asset.id,
        type: asset.type,
        path: asset.path,
        runtimeUrl: asset.previewUrl,
        width: asset.width,
        height: asset.height,
        duration: asset.duration,
        fps: asset.fps,
      }
      : undefined;
    const fallbackKind: Exclude<WorkspaceAsset["type"], "unknown"> | "background" | "text" | "shape" | "native-scene" = clip.trackKind === "audio"
      ? "audio"
      : clip.trackKind === "image" || clip.trackKind === "video"
        ? clip.trackKind
      : clip.trackKind;
    const kind = toLayerKind(clip.type, fallbackKind);

    return {
      id: `ir-layer-${clip.id}`,
      clipId: clip.id,
      trackId: clip.trackId,
      kind,
      zIndex: visibleClips.length - index - 1,
      timing: {
        start: clip.start,
        duration: clip.duration,
        end: clip.start + clip.duration,
        trimIn: clip.trimIn,
      },
      asset: assetRef,
      style: clip.style,
      text: clip.text,
      shape: clip.shape,
      muted: clip.muted,
    };
  });

  return {
    version: 1,
    revision: model.revision,
    composition: model.composition,
    durationSeconds: model.composition.durationSeconds,
    fps: model.composition.fps,
    contracts: createHyperFramePixelFrameContract(model.composition),
    layers,
    issues: model.issues,
  };
};
