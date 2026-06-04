export type TimelineFrameRange = {
  startFrame: number;
  endFrame: number;
  durationFrames: number;
};

export const frameDurationSeconds = (fps: number): number => (
  1 / Math.max(1, Math.round(Number(fps) || 1))
);

export const snapTimeToFrame = (timeSeconds: number, fps: number): number => {
  const frame = Math.round(Math.max(0, Number(timeSeconds) || 0) * Math.max(1, fps));
  return frame / Math.max(1, fps);
};

export const timeToFrame = (timeSeconds: number, fps: number): number => (
  Math.round(Math.max(0, Number(timeSeconds) || 0) * Math.max(1, fps))
);

export const frameToTime = (frame: number, fps: number): number => (
  Math.max(0, Math.round(Number(frame) || 0)) / Math.max(1, fps)
);

export const clipFrameRange = (
  startSeconds: number,
  durationSeconds: number,
  fps: number,
): TimelineFrameRange => {
  const startFrame = timeToFrame(startSeconds, fps);
  const endFrame = Math.max(startFrame + 1, timeToFrame(startSeconds + durationSeconds, fps));
  return {
    startFrame,
    endFrame,
    durationFrames: endFrame - startFrame,
  };
};

export const clampTimelineTime = (
  timeSeconds: number,
  durationSeconds: number,
  fps: number,
): number => (
  Math.max(0, Math.min(Math.max(0, durationSeconds), snapTimeToFrame(timeSeconds, fps)))
);
