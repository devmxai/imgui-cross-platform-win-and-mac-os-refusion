import type { HyperFrameAuthoringClip, HyperFrameAuthoringModel, HyperFrameTransactionGateResult, HyperFrameTransactionInput } from "../contracts/types";

export const createHyperFrameAuthoringModel = (
  input: HyperFrameTransactionInput,
  gate: HyperFrameTransactionGateResult,
): HyperFrameAuthoringModel => {
  const clips: HyperFrameAuthoringClip[] = input.timeline.tracks.flatMap((track) => (
    track.clips.map((clip) => ({
      id: clip.id,
      name: clip.name,
      type: clip.type,
      trackId: clip.trackId || track.id,
      trackKind: track.kind,
      start: clip.start,
      duration: clip.duration,
      trimIn: clip.trimIn,
      assetId: clip.assetId,
      renderCompositor: clip.render?.compositor,
      style: clip.style,
      text: clip.text,
      shape: clip.shape,
      hidden: Boolean(track.isHidden),
      muted: Boolean(track.isMuted),
    }))
  ));

  return {
    version: 1,
    revision: gate.revision,
    composition: input.composition,
    assets: input.assets,
    scene: input.scene,
    clips,
    issues: gate.issues,
  };
};
