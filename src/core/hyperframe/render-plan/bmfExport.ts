import type { HyperFrameBmfExportJob, HyperFrameBmfExportNode, HyperFrameIR } from "../contracts/types";
import { toHyperFrameRange } from "../frame/pixelFrameContract";

const mediaKinds = new Set(["video", "image", "audio"]);

export const createBmfExportJob = (ir: HyperFrameIR): HyperFrameBmfExportJob => {
  const audibleLayers = ir.layers.filter((layer) => (layer.kind === "audio" || layer.kind === "video") && !layer.muted);
  const layerDescriptors = ir.layers.map((layer) => ({
    id: layer.id,
    clipId: layer.clipId,
    trackId: layer.trackId,
    kind: layer.kind,
    zIndex: layer.zIndex,
    timing: layer.timing,
    frameRange: toHyperFrameRange(layer.timing.start, layer.timing.duration, ir.fps),
    asset: layer.asset,
    style: layer.style,
    muted: layer.muted,
  }));
  const frameCount = Math.max(1, Math.round(ir.durationSeconds * ir.fps));
  const hasAudioPcm = audibleLayers.some((layer) => layer.asset && mediaKinds.has(layer.kind));
  const nodes: HyperFrameBmfExportNode[] = [
    {
      id: "hyperframe-final-frame-stream",
      module: "frame_stream",
      inputs: [],
      layerIds: ir.layers.filter((layer) => layer.kind !== "audio").map((layer) => layer.id),
      options: {
        renderer: "hyperframe",
        stream: "final-composition-pixels",
        seek: "CanonicalFinalFrameStream.seekFrame(frameIndex)",
        rendererContract: "HyperFrame IR -> FrameDescriptor(frameIndex) -> FxPassGraph -> UnifiedFrameRenderer",
        surfaceProvider: "PlatformFinalFrameSurfaceProvider.getFrame(frameIndex)",
        pixelFormat: "rgba8-premultiplied",
        colorSpace: ir.contracts.pixelGeometry.colorSpace,
        alpha: ir.contracts.pixelGeometry.alpha,
        width: ir.composition.width,
        height: ir.composition.height,
        fps: ir.fps,
        frameCount,
        timeBase: ir.contracts.frameTiming.timeBase,
        frameTiming: ir.contracts.frameTiming.seekPolicy,
      },
    },
  ];

  if (hasAudioPcm) {
    nodes.push({
      id: "hyperframe-audio-pcm",
      module: "audio_pcm",
      inputs: [],
      layerIds: audibleLayers.map((layer) => layer.id),
      options: {
        provider: "HyperFrameAudioPcmPlan",
        sampleFormat: "f32-planar",
        sampleRate: 48000,
        channels: 2,
        durationSeconds: ir.durationSeconds,
        source: "renderHyperFrameAudioPcmPlan(plan)",
      },
    });
  }

  nodes.push({
    id: "encode-output",
    module: "encode",
    inputs: hasAudioPcm
      ? ["hyperframe-final-frame-stream", "hyperframe-audio-pcm"]
      : ["hyperframe-final-frame-stream"],
    layerIds: ir.layers.map((layer) => layer.id),
    options: {
      container: "mp4",
      videoCodec: "h264",
      audioCodec: "aac",
      videoSource: "hyperframe-final-frame-stream",
    },
  });

  return {
    version: 1,
    target: "bmf",
    source: "hyperframe-final-frame-stream",
    executionRole: "encode-mux-only",
    visualAuthority: "hyperframe-ir-frame-descriptor-platform-renderer",
    revision: ir.revision,
    composition: ir.composition,
    durationSeconds: ir.durationSeconds,
    fps: ir.fps,
    contracts: ir.contracts,
    layers: layerDescriptors,
    nodes,
    output: {
      container: "mp4",
      videoCodec: "h264",
      audioCodec: "aac",
      videoSource: "hyperframe-final-frame-stream",
      audioSource: "hyperframe-audio-pcm",
      audioPolicy: hasAudioPcm ? "pcm" : "none",
    },
  };
};
