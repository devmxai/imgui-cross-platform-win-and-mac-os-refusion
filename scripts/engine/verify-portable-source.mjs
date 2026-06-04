import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, extname, join, resolve } from "node:path";

const root = fileURLToPath(new URL("../../", import.meta.url));

const requiredFiles = [
  "apps/imgui/CMakeLists.txt",
  "apps/imgui/src/platform/macos/MacApp.mm",
  "apps/imgui/src/ui/EditorShell.cpp",
  "apps/imgui/src/ui/EditorShell.hpp",
  "src/core/hyperframe/project/transactionGate.ts",
  "src/core/hyperframe/project/ir.ts",
  "src/core/hyperframe/frame/frameDescriptor.ts",
  "src/core/hyperframe/fx/fxRegistry.manifest.json",
  "src/core/hyperframe/fx/effectNormalizer.ts",
  "src/core/hyperframe/fx/fxPassGraph.ts",
  "src/core/hyperframe/fx/motionBlurQualityPlanner.ts",
  "src/core/hyperframe/render-plan/canonicalFrameRequest.ts",
  "src/core/hyperframe/render-plan/qualityPolicy.ts",
  "src/core/hyperframe/render-plan/renderPlanner.ts",
  "src/core/hyperframe/render-plan/sourceSurfaceProvider.ts",
  "engine/platform/macos-reference/UnitedGate.swift",
  "engine/platform/macos-reference/CanonicalHyperFrameBridge.swift",
  "engine/platform/macos-reference/RenderGraph.swift",
  "engine/platform/macos-reference/FXPassGraph.swift",
  "engine/platform/macos-reference/FXRegistry.swift",
  "engine/platform/macos-reference/MetalFXRuntime.swift",
  "engine/platform/macos-reference/NativeRenderEngine.swift",
  "engine/platform/macos-reference/NativeRenderSurface.swift",
  "engine/platform/macos-reference/MetalRenderGraphFrameRenderer.swift",
  "engine/platform/macos-reference/MotionBlurQualityPlanner.swift",
  "engine/platform/macos-reference/NativeTimelineExporter.swift",
  "engine/platform/macos/adapter-contract.md",
  "engine/platform/macos/current-native-adapter-map.md",
  "engine/platform/windows/adapter-contract.md",
  "docs/architecture/imgui-professional-plan.md",
  "docs/engine/architecture/render-semantics.md",
  "docs/engine/architecture/fx-animation-contract.md",
  "docs/engine/architecture/platform-adapters.md",
  "docs/Professional HyperFrame FX Development Standard.md",
  "docs/PORTABLE_SOURCE_MANIFEST.md",
];

const missing = requiredFiles.filter((path) => !existsSync(join(root, path)));
if (missing.length > 0) {
  throw new Error(`Portable source is incomplete. Missing:\n${missing.join("\n")}`);
}

const forbiddenPaths = [
  "apps/qt",
  "src/platforms/web",
  "engine/platform/macos-reference/ContentView.swift",
  "engine/platform/macos-reference/MakelabMacApp.swift",
  "engine/platform/macos-reference/EditorState.swift",
];
const presentForbidden = forbiddenPaths.filter((path) => existsSync(join(root, path)));
if (presentForbidden.length > 0) {
  throw new Error(`Portable ImGui repository contains excluded UI path:\n${presentForbidden.join("\n")}`);
}

const app = readFileSync(join(root, "apps/imgui/src/platform/macos/MacApp.mm"), "utf8");
const appTokens = [
  "BuildHyperFrameIR",
  "EvaluateFrameDescriptor",
  "CompileRenderGraph",
  "CompileFXPassGraph",
  "MacMetalRenderFrameExecutor",
  "FinalFrameSurface",
  "renderMotionBlurTexture",
];
for (const token of appTokens) {
  if (!app.includes(token)) {
    throw new Error(`Current ImGui application is missing required engine bridge token: ${token}`);
  }
}

const cmake = readFileSync(join(root, "apps/imgui/CMakeLists.txt"), "utf8");
if (!cmake.includes("GIT_TAG fc5e2f28fedf6bbe0d20885a5a144d1206a3474e")) {
  throw new Error("Dear ImGui dependency must remain pinned to the validated source commit.");
}

const coreTokens = [
  ["src/core/hyperframe/project/transactionGate.ts", "validateHyperFrameTransaction"],
  ["src/core/hyperframe/project/ir.ts", "compileHyperFrameIR"],
  ["src/core/hyperframe/frame/frameDescriptor.ts", "evaluateHyperFrameFrameDescriptor"],
  ["src/core/hyperframe/fx/fxPassGraph.ts", "createHyperFrameFxPassGraph"],
  ["src/core/hyperframe/render-plan/canonicalFrameRequest.ts", "FinalFrameSurface"],
];
for (const [path, token] of coreTokens) {
  const source = readFileSync(join(root, path), "utf8");
  if (!source.includes(token)) {
    throw new Error(`${path} is missing required token: ${token}`);
  }
}

const walkFiles = (directory) => readdirSync(directory).flatMap((entry) => {
  const path = join(directory, entry);
  return statSync(path).isDirectory() ? walkFiles(path) : [path];
});

const resolveRelativeImport = (sourcePath, specifier) => {
  const candidate = resolve(dirname(sourcePath), specifier);
  const candidates = extname(candidate)
    ? [candidate]
    : [`${candidate}.ts`, `${candidate}.json`, join(candidate, "index.ts")];
  return candidates.some((path) => existsSync(path));
};

const coreRoot = join(root, "src/core/hyperframe");
const brokenImports = [];
for (const sourcePath of walkFiles(coreRoot).filter((path) => path.endsWith(".ts"))) {
  const source = readFileSync(sourcePath, "utf8");
  const imports = source.matchAll(/from\s+["'](\.[^"']+)["']/g);
  for (const [, specifier] of imports) {
    if (!resolveRelativeImport(sourcePath, specifier)) {
      brokenImports.push(`${sourcePath.slice(root.length)} -> ${specifier}`);
    }
  }
}
if (brokenImports.length > 0) {
  throw new Error(`Portable HyperFrame Core has broken relative imports:\n${brokenImports.join("\n")}`);
}

JSON.parse(readFileSync(join(root, "src/core/hyperframe/fx/fxRegistry.manifest.json"), "utf8"));

console.log("Portable ImGui + HyperFrame source verified: Gate -> IR -> FrameDescriptor -> RenderGraph/FXPassGraph -> FinalFrameSurface.");
