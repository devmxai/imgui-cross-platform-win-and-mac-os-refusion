#include "query/FrameQueryService.hpp"

#include <cassert>
#include <cmath>

using makelab::imgui::ClipItem;
using makelab::imgui::TrackItem;
using makelab::imgui::WorkspaceViewState;
using makelab::query::CompositionToViewport;
using makelab::query::CreateCanvasViewTransform;
using makelab::query::QueryFrame;
using makelab::query::QueryLayerAtPixel;
using makelab::query::ViewportToComposition;

int main() {
  WorkspaceViewState workspace;
  workspace.opened = true;
  workspace.width = 1080;
  workspace.height = 1920;
  workspace.fps = 30.0;
  workspace.frameRate = makelab::timeline::FrameRateFromFps(30.0);
  workspace.durationFrames = 300;
  workspace.durationSeconds = makelab::timeline::FrameToSeconds({workspace.durationFrames}, workspace.frameRate);

  ClipItem text;
  text.id = "text_title";
  text.name = "Title";
  text.type = "text";
  text.trackId = "track_text";
  text.startFrame = 90;
  text.durationFrames = 60;
  text.startSeconds = 3.0;
  text.durationSeconds = 2.0;
  text.x = 100.0;
  text.y = 200.0;
  text.width = 400.0;
  text.height = 120.0;
  text.anchorX = 0.0;
  text.anchorY = 0.0;
  text.textContent = "Scene title";
  text.animationFrames.push_back({"opacity", 0.0, 0.0, "linear"});
  text.animationFrames.push_back({"opacity", 1.0, 1.0, "linear"});

  TrackItem track;
  track.id = "track_text";
  track.name = "Text";
  track.kind = "text";
  track.clips.push_back(text);
  workspace.tracks.push_back(track);

  const auto before = QueryFrame(workspace, 89);
  assert(before.layers.empty());

  const auto first = QueryFrame(workspace, 90);
  assert(first.layers.size() == 1);
  assert(first.layers.front().clipId == "text_title");
  assert(first.layers.front().textContent == "Scene title");
  assert(std::abs(first.layers.front().opacity - 0.0) < 0.000001);

  const auto middle = QueryFrame(workspace, 105);
  assert(middle.layers.size() == 1);
  assert(middle.layers.front().opacity > 0.49 && middle.layers.front().opacity < 0.51);
  const auto* hit = QueryLayerAtPixel(middle, 120.0, 220.0);
  assert(hit != nullptr);
  assert(hit->clipId == "text_title");

  const auto last = QueryFrame(workspace, 149);
  assert(last.layers.size() == 1);
  const auto after = QueryFrame(workspace, 150);
  assert(after.layers.empty());

  int activeDuringExportIteration = 0;
  for (int64_t frame = 0; frame < workspace.durationFrames; ++frame) {
    const auto exportTruth = QueryFrame(workspace, frame);
    if (!exportTruth.layers.empty()) {
      activeDuringExportIteration += 1;
      assert(exportTruth.layers.front().clipId == "text_title");
    }
  }
  assert(activeDuringExportIteration == text.durationFrames);

  const auto transform = CreateCanvasViewTransform(1080, 1920, 540, 960);
  const auto viewport = CompositionToViewport(transform, {100.0, 200.0});
  const auto composition = ViewportToComposition(transform, viewport);
  assert(std::abs(composition.x - 100.0) < 0.5);
  assert(std::abs(composition.y - 200.0) < 0.5);

  return 0;
}
