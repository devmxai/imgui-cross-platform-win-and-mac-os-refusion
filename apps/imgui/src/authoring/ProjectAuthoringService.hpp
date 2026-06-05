#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace makelab::authoring {

struct ImportedAssetMetadata {
  std::string type;
  int width = 0;
  int height = 0;
  double durationSeconds = 0.0;
  double fps = 0.0;
};

struct AuthoringResult {
  bool accepted = false;
  std::string message;
  std::string createdId;
  std::vector<std::string> diagnostics;
};

class ProjectAuthoringService {
 public:
  AuthoringResult importAsset(const std::filesystem::path& workspace,
                              const std::filesystem::path& source,
                              const ImportedAssetMetadata& metadata) const;
  AuthoringResult addAssetClip(const std::filesystem::path& workspace,
                               const std::string& assetId,
                               int64_t startFrame) const;
  AuthoringResult addTextLayer(const std::filesystem::path& workspace,
                               const std::string& preset,
                               int64_t startFrame) const;
  AuthoringResult addBackgroundLayer(const std::filesystem::path& workspace,
                                     const std::string& color,
                                     int64_t startFrame) const;
  AuthoringResult addShapeLayer(const std::filesystem::path& workspace,
                                const std::string& shapeKind,
                                int64_t startFrame) const;
};

}  // namespace makelab::authoring
