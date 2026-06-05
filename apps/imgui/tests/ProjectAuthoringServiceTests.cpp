#include "authoring/ProjectAuthoringService.hpp"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include <nlohmann/json.hpp>

namespace {

using Json = nlohmann::json;
namespace fs = std::filesystem;

void Require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void RequireAccepted(const makelab::authoring::AuthoringResult& result, const std::string& operation) {
  std::string message = operation + " must be accepted: " + result.message;
  for (const std::string& diagnostic : result.diagnostics) {
    message += " | " + diagnostic;
  }
  Require(result.accepted, message);
}

void WriteJson(const fs::path& path, const Json& value) {
  fs::create_directories(path.parent_path());
  std::ofstream output(path);
  output << value.dump(2) << '\n';
}

Json ReadJson(const fs::path& path) {
  std::ifstream input(path);
  Json value;
  input >> value;
  return value;
}

fs::path CreateWorkspace() {
  const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
  const fs::path workspace = fs::temp_directory_path() / ("makelab-authoring-test-" + std::to_string(suffix));
  fs::create_directories(workspace / "assets/originals");
  WriteJson(workspace / "composition.json", {
      {"width", 1080},
      {"height", 1920},
      {"fps", 30},
      {"durationSeconds", 10.0},
  });
  WriteJson(workspace / "assets/assets.json", {
      {"version", 1},
      {"assets", Json::array()},
  });
  WriteJson(workspace / "timeline.json", {
      {"version", 1},
      {"fps", 30},
      {"durationSeconds", 10.0},
      {"tracks", Json::array()},
  });
  return workspace;
}

void VerifyAllClipsStayInsideComposition(const Json& timeline, double duration) {
  const int64_t durationFrames = timeline.value("durationFrames", static_cast<int64_t>(duration * 30.0));
  for (const Json& track : timeline.at("tracks")) {
    for (const Json& clip : track.at("clips")) {
      Require(clip.contains("startFrame"), "clip must declare canonical startFrame");
      Require(clip.contains("durationFrames"), "clip must declare canonical durationFrames");
      Require(clip.contains("trimInFrame"), "clip must declare canonical trimInFrame");
      Require(clip.at("startFrame").get<int64_t>() >= 0, "clip startFrame must be non-negative");
      Require(clip.at("durationFrames").get<int64_t>() > 0, "clip durationFrames must be positive");
      Require(clip.at("startFrame").get<int64_t>() + clip.at("durationFrames").get<int64_t>() <= durationFrames,
              "clip frame range must end inside composition");
      Require(clip.at("start").get<double>() >= 0.0, "clip start must be non-negative");
      Require(clip.at("duration").get<double>() > 0.0, "clip duration must be positive");
      Require(clip.at("start").get<double>() + clip.at("duration").get<double>() <= duration + 0.000001,
              "clip must end inside composition");
    }
  }
}

}  // namespace

int main() {
  fs::path workspace;
  try {
    workspace = CreateWorkspace();
    const fs::path source = workspace.parent_path() / (workspace.filename().string() + "-source.png");
    {
      std::ofstream output(source, std::ios::binary);
      output << "accepted-test-image";
    }

    makelab::authoring::ProjectAuthoringService service;
    makelab::authoring::ImportedAssetMetadata metadata;
    metadata.type = "image";
    metadata.width = 640;
    metadata.height = 360;

    const auto imported = service.importAsset(workspace, source, metadata);
    Require(imported.accepted, imported.message);
    const Json manifest = ReadJson(workspace / "assets/assets.json");
    Require(manifest.at("assets").size() == 1, "import must append one accepted asset");
    const fs::path copied = workspace / manifest.at("assets").at(0).at("path").get<std::string>();
    Require(fs::exists(copied), "imported asset must be copied into the project");

    RequireAccepted(service.addAssetClip(workspace, imported.createdId, 294), "asset clip");
    RequireAccepted(service.addTextLayer(workspace, "title", 294), "text layer");
    RequireAccepted(service.addBackgroundLayer(workspace, "#101618", 294), "background layer");
    RequireAccepted(service.addShapeLayer(workspace, "circle", 294), "shape layer");

    const Json acceptedTimeline = ReadJson(workspace / "timeline.json");
    Require(acceptedTimeline.at("timebase").at("rate").at("numerator").get<int64_t>() == 30,
            "timeline must declare canonical numerator");
    Require(acceptedTimeline.at("timebase").at("rate").at("denominator").get<int64_t>() == 1,
            "timeline must declare canonical denominator");
    Require(acceptedTimeline.at("durationFrames").get<int64_t>() == 300,
            "timeline must declare canonical durationFrames");
    Require(acceptedTimeline.at("tracks").size() == 4, "authoring commands must append four accepted tracks");
    VerifyAllClipsStayInsideComposition(acceptedTimeline, 10.0);

    const std::string beforeRejectedCommand = acceptedTimeline.dump();
    const auto rejected = service.addShapeLayer(workspace, "unsupported-shape", 0.0);
    Require(!rejected.accepted, "unsupported shape must be rejected");
    Require(ReadJson(workspace / "timeline.json").dump() == beforeRejectedCommand,
            "rejected command must not mutate accepted timeline state");

    fs::remove(source);
    fs::remove_all(workspace);
    std::cout << "ProjectAuthoringService tests passed.\n";
    return 0;
  } catch (const std::exception& error) {
    if (!workspace.empty()) {
      fs::remove_all(workspace);
    }
    std::cerr << error.what() << '\n';
    return 1;
  }
}
