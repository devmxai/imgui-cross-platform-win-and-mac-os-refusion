export type CanonicalFrameProfile = "interactive" | "playback" | "pausedPreview" | "render" | "export";

export type FrameQualityPolicy = {
  profile: CanonicalFrameProfile;
  textureScale: number;
  allowProxyTextures: boolean;
  requireGpuForHeavyVideo: boolean;
  maxSamples: Record<string, number>;
  defaultSamples: Record<string, number>;
};

const sampleBudgets = {
  interactive: { textureScale: 0.75, motion: 8, tile: 2, shader: 12 },
  playback: { textureScale: 0.75, motion: 24, tile: 2, shader: 24 },
  pausedPreview: { textureScale: 1, motion: 64, tile: 4, shader: 64 },
  render: { textureScale: 1, motion: 96, tile: 8, shader: 96 },
  export: { textureScale: 1, motion: 192, tile: 12, shader: 160 },
} satisfies Record<CanonicalFrameProfile, { textureScale: number; motion: number; tile: number; shader: number }>;

export const createFrameQualityPolicy = (profile: CanonicalFrameProfile): FrameQualityPolicy => {
  const budget = sampleBudgets[profile];
  return {
    profile,
    textureScale: budget.textureScale,
    allowProxyTextures: profile === "interactive" || profile === "playback",
    requireGpuForHeavyVideo: profile !== "export",
    maxSamples: {
      motionBlur: budget.motion,
      motionTrail: budget.motion,
      motionTile: budget.tile,
      radialBlur: budget.shader,
      zoomBlur: budget.shader,
      spiralEchoBlur: budget.shader,
      glowStreak: budget.shader,
      chromaticSplit: 1,
      shaderTransition: budget.shader,
    },
    defaultSamples: {
      motionBlur: Math.max(3, Math.round(budget.motion * 0.66)),
      motionTrail: Math.max(3, Math.round(budget.motion * 0.5)),
      motionTile: Math.max(1, Math.round(budget.tile * 0.66)),
      radialBlur: Math.max(3, Math.round(budget.shader * 0.66)),
      zoomBlur: Math.max(3, Math.round(budget.shader * 0.66)),
      spiralEchoBlur: Math.max(3, Math.round(budget.shader * 0.66)),
      glowStreak: Math.max(3, Math.round(budget.shader * 0.5)),
      chromaticSplit: 1,
      shaderTransition: Math.max(3, Math.round(budget.shader * 0.5)),
    },
  };
};
