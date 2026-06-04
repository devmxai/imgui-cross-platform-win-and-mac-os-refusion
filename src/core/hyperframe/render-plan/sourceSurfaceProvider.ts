import type {
  CanonicalFrameProfile,
  SourceSurface,
  SourceSurfaceProvider,
  SourceSurfaceSample,
  TemporalSampleRequest,
} from "./canonicalFrameRequest";
import { hyperFrameIndexToSeconds, secondsToHyperFrameIndex } from "../frame/pixelFrameContract";

export type SourceSurfaceProviderMode = SourceSurfaceProvider["mode"];

const createPlaceholderSurface = (
  providerId: string,
  mode: SourceSurfaceProviderMode,
  layerId: string,
  frameIndex: number,
  fps: number,
  requestedTimeSeconds?: number,
): SourceSurface => ({
  id: `${providerId}:${mode}:${layerId}:${frameIndex}`,
  layerId,
  frameIndex,
  timeSeconds: requestedTimeSeconds ?? hyperFrameIndexToSeconds(frameIndex, fps),
  requestedTimeSeconds,
  frameTimeSeconds: hyperFrameIndexToSeconds(frameIndex, fps),
  approximatedTime: requestedTimeSeconds !== undefined
    ? Math.abs(requestedTimeSeconds - hyperFrameIndexToSeconds(frameIndex, fps)) > 1 / Math.max(1, fps * 1024)
    : false,
  width: 0,
  height: 0,
  surface: null,
  alpha: "premultiplied",
  colorSpace: "srgb",
});

const createProvider = (
  id: string,
  mode: SourceSurfaceProviderMode,
  fps: number,
): SourceSurfaceProvider => ({
  id,
  mode,
  getSurface: async (layerId, frameIndex) => createPlaceholderSurface(id, mode, layerId, frameIndex, fps),
  getTemporalSamples: async (request: TemporalSampleRequest): Promise<SourceSurfaceSample[]> => {
    const sampleCount = Math.max(1, Math.round(request.sampleCount));
    const shutterSeconds = Math.max(0, Number(request.shutterSeconds) || 0);
    const startTime = request.timeSeconds - shutterSeconds / 2;
    const samples: SourceSurfaceSample[] = [];
    for (let index = 0; index < sampleCount; index += 1) {
      const progress = sampleCount === 1 ? 0.5 : index / (sampleCount - 1);
      const sampleTime = Math.max(0, startTime + shutterSeconds * progress);
      const frameIndex = secondsToHyperFrameIndex(sampleTime, fps);
      const frameTimeSeconds = hyperFrameIndexToSeconds(frameIndex, fps);
      const approximatedTime = Math.abs(sampleTime - frameTimeSeconds) > 1 / Math.max(1, fps * 1024);
      samples.push({
        frameIndex,
        timeSeconds: sampleTime,
        requestedTimeSeconds: sampleTime,
        frameTimeSeconds,
        approximatedTime,
        weight: 1 / sampleCount,
        surface: createPlaceholderSurface(id, mode, request.layerId, frameIndex, fps, sampleTime),
      });
    }
    return samples;
  },
});

export const createExactSeekSourceSurfaceProvider = (fps: number): SourceSurfaceProvider => (
  createProvider("exact-seek-source-provider", "exact-seek", fps)
);

export const createStreamingPlaybackSourceSurfaceProvider = (fps: number): SourceSurfaceProvider => (
  createProvider("streaming-playback-source-provider", "streaming-playback", fps)
);

export const createStaticSourceSurfaceProvider = (fps: number): SourceSurfaceProvider => (
  createProvider("static-source-provider", "static", fps)
);

export const createSourceSurfaceProviderForProfile = (
  profile: CanonicalFrameProfile,
  fps: number,
): SourceSurfaceProvider => {
  if (profile === "playback") return createStreamingPlaybackSourceSurfaceProvider(fps);
  if (profile === "interactive" || profile === "pausedPreview" || profile === "render" || profile === "export") {
    return createExactSeekSourceSurfaceProvider(fps);
  }
  return createStaticSourceSurfaceProvider(fps);
};
