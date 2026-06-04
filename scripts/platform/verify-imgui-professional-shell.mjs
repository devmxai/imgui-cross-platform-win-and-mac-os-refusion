import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));
const appRoot = join(root, 'apps/imgui');

const forbiddenTokens = [
  'WebView',
  'WKWebView',
  'QWebEngine',
  'MediaPlayer',
  'AVPlayer',
  'Canvas fallback',
  'HTMLCanvasElement',
];

const requiredTokens = [
  'FinalFrameSurface',
  'Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph',
  '--design-fixture',
  'Preview blocked',
  'OpenProject',
  'RequestExport',
  'BeginPlayback',
];

function collectFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    const stat = statSync(path);
    if (stat.isDirectory()) {
      if (entry === 'build') return [];
      return collectFiles(path);
    }
    return [path];
  });
}

const files = collectFiles(appRoot).filter((path) => /\.(md|txt|cmake|cpp|hpp|h|mm)$/.test(path) || path.endsWith('CMakeLists.txt'));
const corpus = files.map((path) => readFileSync(path, 'utf8')).join('\n');

for (const token of forbiddenTokens) {
  if (corpus.includes(token)) {
    throw new Error(`IMGUI Professional shell contains forbidden token: ${token}`);
  }
}

for (const token of requiredTokens) {
  if (!corpus.includes(token)) {
    throw new Error(`IMGUI Professional shell is missing required token: ${token}`);
  }
}

console.log('IMGUI Professional shell verification passed. UI remains command/display only.');
