#include "ui/EditorShell.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <sstream>

#include "imgui.h"

namespace makelab::imgui {
namespace {

struct Color {
  float r;
  float g;
  float b;
  float a;
};

constexpr Color kBg{0.027f, 0.043f, 0.047f, 1.0f};
constexpr Color kPanel{0.051f, 0.071f, 0.078f, 1.0f};
constexpr Color kPanel2{0.063f, 0.086f, 0.094f, 1.0f};
constexpr Color kLane{0.055f, 0.094f, 0.090f, 1.0f};
constexpr Color kBorder{0.106f, 0.137f, 0.157f, 1.0f};
constexpr Color kDivider{0.145f, 0.174f, 0.196f, 1.0f};
constexpr Color kText{0.847f, 0.871f, 0.902f, 1.0f};
constexpr Color kMuted{0.596f, 0.643f, 0.686f, 1.0f};
constexpr Color kGreen{0.482f, 0.906f, 0.678f, 1.0f};
constexpr Color kBlue{0.400f, 0.780f, 1.000f, 1.0f};
constexpr Color kPurple{0.545f, 0.420f, 0.941f, 1.0f};
constexpr Color kDeepPurple{0.176f, 0.129f, 0.298f, 1.0f};

ImU32 U32(Color color) {
  return IM_COL32(static_cast<int>(color.r * 255.0f),
                  static_cast<int>(color.g * 255.0f),
                  static_cast<int>(color.b * 255.0f),
                  static_cast<int>(color.a * 255.0f));
}

void ConfigureStyle() {
  ImGuiStyle& style = ImGui::GetStyle();
  style.WindowPadding = ImVec2(0.0f, 0.0f);
  style.FramePadding = ImVec2(11.0f, 7.0f);
  style.ItemSpacing = ImVec2(7.0f, 7.0f);
  style.WindowRounding = 0.0f;
  style.ChildRounding = 0.0f;
  style.FrameRounding = 8.0f;
  style.GrabRounding = 8.0f;
  style.ScrollbarRounding = 6.0f;
  style.WindowBorderSize = 0.0f;
  style.FrameBorderSize = 1.0f;

  ImVec4* colors = style.Colors;
  colors[ImGuiCol_WindowBg] = ImVec4(kBg.r, kBg.g, kBg.b, kBg.a);
  colors[ImGuiCol_ChildBg] = ImVec4(kBg.r, kBg.g, kBg.b, kBg.a);
  colors[ImGuiCol_Text] = ImVec4(kText.r, kText.g, kText.b, kText.a);
  colors[ImGuiCol_TextDisabled] = ImVec4(kMuted.r, kMuted.g, kMuted.b, 0.7f);
  colors[ImGuiCol_Button] = ImVec4(kPanel2.r, kPanel2.g, kPanel2.b, 1.0f);
  colors[ImGuiCol_ButtonHovered] = ImVec4(0.090f, 0.110f, 0.125f, 1.0f);
  colors[ImGuiCol_ButtonActive] = ImVec4(0.110f, 0.135f, 0.155f, 1.0f);
  colors[ImGuiCol_Border] = ImVec4(kBorder.r, kBorder.g, kBorder.b, 1.0f);
}

std::string Elide(const std::string& value, size_t maxLength) {
  if (value.size() <= maxLength) {
    return value;
  }
  if (maxLength <= 3) {
    return value.substr(0, maxLength);
  }
  return value.substr(0, maxLength - 3) + "...";
}

std::string FormatAssetMeta(const AssetItem& asset) {
  std::ostringstream out;
  out << (asset.type.empty() ? "ASSET" : asset.type);
  if (asset.width > 0 && asset.height > 0) {
    out << " - " << asset.width << "x" << asset.height;
  }
  if (asset.durationSeconds > 0.0) {
    char duration[32];
    std::snprintf(duration, sizeof(duration), " - %.2fs", asset.durationSeconds);
    out << duration;
  }
  return out.str();
}

bool ButtonCommand(const char* label, const ImVec2& size, EditorShellResult& result, const char* command) {
  if (ImGui::Button(label, size)) {
    result.command = command;
    return true;
  }
  return false;
}

bool DrawCommandButton(ImDrawList* draw, const char* id, const char* label, ImVec2 pos, ImVec2 size, EditorShellResult& result, const char* command) {
  ImGui::SetCursorScreenPos(pos);
  ImGui::PushID(id);
  const bool pressed = ImGui::InvisibleButton("hit", size);
  const bool hovered = ImGui::IsItemHovered();
  ImGui::PopID();

  draw->AddRectFilled(pos, ImVec2(pos.x + size.x, pos.y + size.y),
                      hovered ? IM_COL32(28, 34, 39, 255) : U32(kPanel2), 8.0f);
  draw->AddRect(pos, ImVec2(pos.x + size.x, pos.y + size.y), U32(kBorder), 8.0f, 0, 1.0f);
  ImVec2 text = ImGui::CalcTextSize(label);
  draw->AddText(ImVec2(pos.x + size.x * 0.5f - text.x * 0.5f, pos.y + size.y * 0.5f - text.y * 0.5f),
                U32(kText), label);

  if (pressed) {
    result.command = command;
    return true;
  }
  return false;
}

void DrawIconGlyph(ImDrawList* draw, ImVec2 center, const char* label, bool selected = false) {
  if (selected) {
    draw->AddRectFilled(ImVec2(center.x - 20.0f, center.y - 20.0f), ImVec2(center.x + 20.0f, center.y + 20.0f), U32(kPanel2), 7.0f);
    draw->AddRect(ImVec2(center.x - 20.0f, center.y - 20.0f), ImVec2(center.x + 20.0f, center.y + 20.0f), U32(kBorder), 7.0f, 0, 1.2f);
  }
  ImVec2 textSize = ImGui::CalcTextSize(label);
  draw->AddText(ImVec2(center.x - textSize.x * 0.5f, center.y - textSize.y * 0.5f), selected ? U32(kText) : U32(kMuted), label);
}

void DrawToolbarGlyph(ImDrawList* draw, ImVec2 center, int kind) {
  const ImU32 color = U32(kMuted);
  if (kind == 0) {
    for (int i = 0; i < 3; ++i) {
      const float y = center.y - 7.0f + i * 7.0f;
      draw->AddLine(ImVec2(center.x - 9.0f, y), ImVec2(center.x + 9.0f, y), color, 1.8f);
    }
    return;
  }
  if (kind == 1) {
    draw->AddTriangle(ImVec2(center.x - 6.0f, center.y - 10.0f), ImVec2(center.x + 9.0f, center.y - 1.0f),
                      ImVec2(center.x - 1.0f, center.y + 2.0f), color, 1.8f);
    draw->AddLine(ImVec2(center.x - 1.0f, center.y + 2.0f), ImVec2(center.x + 5.0f, center.y + 10.0f), color, 1.8f);
    return;
  }
  if (kind == 2) {
    draw->AddRect(ImVec2(center.x - 8.0f, center.y - 8.0f), ImVec2(center.x + 8.0f, center.y + 8.0f), color, 3.0f, 0, 1.8f);
    return;
  }
  if (kind == 3) {
    draw->AddCircle(ImVec2(center.x - 3.0f, center.y - 1.0f), 7.0f, color, 18, 1.8f);
    draw->AddLine(ImVec2(center.x - 2.0f, center.y + 6.0f), ImVec2(center.x + 8.0f, center.y + 10.0f), color, 1.8f);
    draw->AddLine(ImVec2(center.x - 8.0f, center.y - 1.0f), ImVec2(center.x + 2.0f, center.y - 1.0f), color, 1.6f);
    return;
  }
  if (kind == 4 || kind == 5) {
    draw->AddCircle(ImVec2(center.x - 2.0f, center.y - 2.0f), 7.0f, color, 18, 1.8f);
    draw->AddLine(ImVec2(center.x + 4.0f, center.y + 4.0f), ImVec2(center.x + 10.0f, center.y + 10.0f), color, 1.8f);
    draw->AddLine(ImVec2(center.x - 6.0f, center.y - 2.0f), ImVec2(center.x + 2.0f, center.y - 2.0f), color, 1.5f);
    if (kind == 5) {
      draw->AddLine(ImVec2(center.x - 2.0f, center.y - 6.0f), ImVec2(center.x - 2.0f, center.y + 2.0f), color, 1.5f);
    }
    return;
  }
}

void DrawDashedRect(ImDrawList* draw, ImVec2 min, ImVec2 max, ImU32 color, float radius) {
  const float dash = 6.0f;
  const float gap = 5.0f;
  for (float x = min.x + radius; x < max.x - radius; x += dash + gap) {
    draw->AddLine(ImVec2(x, min.y), ImVec2(std::min(x + dash, max.x - radius), min.y), color, 1.2f);
    draw->AddLine(ImVec2(x, max.y), ImVec2(std::min(x + dash, max.x - radius), max.y), color, 1.2f);
  }
  for (float y = min.y + radius; y < max.y - radius; y += dash + gap) {
    draw->AddLine(ImVec2(min.x, y), ImVec2(min.x, std::min(y + dash, max.y - radius)), color, 1.2f);
    draw->AddLine(ImVec2(max.x, y), ImVec2(max.x, std::min(y + dash, max.y - radius)), color, 1.2f);
  }
  draw->AddLine(ImVec2(min.x + 3.0f, min.y), ImVec2(min.x + radius, min.y), color, 1.2f);
  draw->AddLine(ImVec2(max.x - radius, min.y), ImVec2(max.x - 3.0f, min.y), color, 1.2f);
  draw->AddLine(ImVec2(min.x + 3.0f, max.y), ImVec2(min.x + radius, max.y), color, 1.2f);
  draw->AddLine(ImVec2(max.x - radius, max.y), ImVec2(max.x - 3.0f, max.y), color, 1.2f);
}

void DrawTopToolbar(ImDrawList* draw, ImVec2 origin, ImVec2 size, EditorShellResult& result) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  draw->AddLine(ImVec2(origin.x, origin.y + size.y - 1.0f), ImVec2(origin.x + size.x, origin.y + size.y - 1.0f), U32(kDivider), 1.35f);

  const float cy = origin.y + size.y * 0.5f;
  for (int i = 0; i < 6; ++i) {
    DrawToolbarGlyph(draw, ImVec2(origin.x + 28.0f + i * 48.0f, cy), i);
  }

  const std::array<const char*, 9> center{"=", "AC", "=", "|-", "-|-", "-|", "<>", "UD", "><"};
  const float centerStart = origin.x + size.x * 0.415f;
  for (int i = 0; i < static_cast<int>(center.size()); ++i) {
    DrawIconGlyph(draw, ImVec2(centerStart + i * 48.0f, cy), center[i]);
  }

  const float right = origin.x + size.x - 12.0f;
  DrawCommandButton(draw, "open-folder-top-right", "Open Folder", ImVec2(right - 386.0f, origin.y + 8.0f), ImVec2(148.0f, 42.0f), result, "OpenProject");
  DrawCommandButton(draw, "render-top-right", "Render", ImVec2(right - 226.0f, origin.y + 8.0f), ImVec2(102.0f, 42.0f), result, "RequestRender");
  DrawCommandButton(draw, "export-top-right", "Export", ImVec2(right - 112.0f, origin.y + 8.0f), ImVec2(100.0f, 42.0f), result, "RequestExport");
}

void DrawRailIcon(ImDrawList* draw, ImVec2 center, int kind, bool selected) {
  if (selected) {
    draw->AddRectFilled(ImVec2(center.x - 17.0f, center.y - 17.0f), ImVec2(center.x + 17.0f, center.y + 17.0f), U32(kPanel2), 6.0f);
    draw->AddRect(ImVec2(center.x - 17.0f, center.y - 17.0f), ImVec2(center.x + 17.0f, center.y + 17.0f), U32(kDivider), 6.0f, 0, 1.25f);
  }
  const ImU32 color = selected ? U32(kText) : U32(kMuted);
  if (kind == 0) {
    draw->AddRect(ImVec2(center.x - 8.0f, center.y - 7.0f), ImVec2(center.x + 5.0f, center.y + 8.0f), color, 3.0f, 0, 1.65f);
    draw->AddRect(ImVec2(center.x - 3.0f, center.y - 11.0f), ImVec2(center.x + 10.0f, center.y + 4.0f), color, 3.0f, 0, 1.65f);
    draw->AddCircle(ImVec2(center.x + 4.0f, center.y - 4.0f), 1.6f, color, 10, 1.3f);
    draw->AddLine(ImVec2(center.x - 6.0f, center.y + 5.0f), ImVec2(center.x - 1.0f, center.y), color, 1.5f);
    draw->AddLine(ImVec2(center.x - 1.0f, center.y), ImVec2(center.x + 4.0f, center.y + 4.0f), color, 1.5f);
    return;
  }
  if (kind == 1) {
    draw->AddLine(ImVec2(center.x - 10.0f, center.y - 10.0f), ImVec2(center.x + 10.0f, center.y - 10.0f), color, 1.8f);
    draw->AddLine(ImVec2(center.x, center.y - 10.0f), ImVec2(center.x, center.y + 12.0f), color, 1.8f);
    draw->AddLine(ImVec2(center.x - 6.0f, center.y + 12.0f), ImVec2(center.x + 6.0f, center.y + 12.0f), color, 1.8f);
    return;
  }
  if (kind == 2) {
    for (int i = -2; i <= 2; ++i) {
      const float h = 6.0f + (2 - std::abs(i)) * 4.0f;
      const float x = center.x + i * 4.2f;
      draw->AddLine(ImVec2(x, center.y - h * 0.5f), ImVec2(x, center.y + h * 0.5f), color, 1.7f);
    }
    return;
  }
  if (kind == 3) {
    draw->AddCircle(center, 10.5f, color, 18, 1.8f);
    draw->AddCircle(ImVec2(center.x - 4.0f, center.y - 4.0f), 1.6f, color, 10, 1.25f);
    draw->AddCircle(ImVec2(center.x + 3.0f, center.y - 5.0f), 1.6f, color, 10, 1.25f);
    draw->AddCircle(ImVec2(center.x - 5.0f, center.y + 3.0f), 1.6f, color, 10, 1.25f);
    draw->AddCircleFilled(ImVec2(center.x + 6.0f, center.y + 4.0f), 3.5f, U32(kBg), 12);
    return;
  }
  draw->AddTriangle(ImVec2(center.x, center.y - 11.0f), ImVec2(center.x - 6.0f, center.y - 1.0f),
                    ImVec2(center.x + 6.0f, center.y - 1.0f), color, 1.7f);
  draw->AddRect(ImVec2(center.x - 11.0f, center.y + 4.0f), ImVec2(center.x - 3.0f, center.y + 12.0f), color, 2.0f);
  draw->AddRect(ImVec2(center.x + 4.0f, center.y + 4.0f), ImVec2(center.x + 12.0f, center.y + 12.0f), color, 2.0f);
}

void DrawLeftRail(ImDrawList* draw, ImVec2 origin, ImVec2 size) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  draw->AddLine(ImVec2(origin.x + size.x - 1.0f, origin.y), ImVec2(origin.x + size.x - 1.0f, origin.y + size.y), U32(kDivider), 1.25f);
  for (int i = 0; i < 5; ++i) {
    ImVec2 center(origin.x + size.x * 0.5f, origin.y + 34.0f + i * 49.0f);
    DrawRailIcon(draw, center, i, i == 0);
  }
}

void DrawAssetCard(ImDrawList* draw, ImVec2 pos, ImVec2 size, const char* name, const char* meta, bool selectedVisual) {
  draw->AddRectFilled(pos, ImVec2(pos.x + size.x, pos.y + size.y), U32(kPanel), 12.0f);
  draw->AddRect(pos, ImVec2(pos.x + size.x, pos.y + size.y), U32(kBorder), 12.0f, 0, 1.5f);

  ImVec2 preview(pos.x + 12.0f, pos.y + 12.0f);
  const float previewW = size.x - 24.0f;
  const float previewH = 72.0f;
  draw->AddRectFilled(preview, ImVec2(preview.x + previewW, preview.y + previewH), IM_COL32(7, 11, 12, 255), 7.0f);
  if (selectedVisual) {
    const float pillW = (previewW - 28.0f) * 0.5f;
    const float pillY = preview.y + 8.0f;
    draw->AddRectFilled(ImVec2(preview.x + 8.0f, pillY), ImVec2(preview.x + 8.0f + pillW, pillY + 24.0f), IM_COL32(46, 86, 122, 255), 6.0f);
    draw->AddRectFilled(ImVec2(preview.x + 20.0f + pillW, pillY), ImVec2(preview.x + 20.0f + pillW * 2.0f, pillY + 24.0f), IM_COL32(65, 137, 105, 255), 6.0f);
    draw->AddText(ImVec2(preview.x + 18.0f, pillY + 4.0f), U32(kText), "Track");
    draw->AddText(ImVec2(preview.x + 30.0f + pillW, pillY + 4.0f), U32(kText), "Layer");
    ImVec2 vidText = ImGui::CalcTextSize("VID");
    draw->AddText(ImVec2(preview.x + previewW * 0.5f - vidText.x * 0.5f, preview.y + 42.0f), IM_COL32(170, 194, 255, 255), "VID");
  }

  draw->AddText(ImVec2(pos.x + 12.0f, pos.y + 94.0f), U32(kText), name);
  draw->AddText(ImVec2(pos.x + 12.0f, pos.y + 116.0f), U32(kMuted), meta);
}

void DrawAssetsPanel(ImDrawList* draw, ImVec2 origin, ImVec2 size, const EditorShellConfig& config, EditorShellResult& result) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  draw->AddLine(ImVec2(origin.x, origin.y), ImVec2(origin.x, origin.y + size.y), U32(kDivider), 1.25f);
  draw->AddLine(ImVec2(origin.x + size.x - 1.0f, origin.y), ImVec2(origin.x + size.x - 1.0f, origin.y + size.y), U32(kDivider), 1.35f);
  draw->AddLine(origin, ImVec2(origin.x + size.x, origin.y), U32(kDivider), 1.25f);

  const WorkspaceViewState* workspace = config.workspace;
  const float cardW = 128.0f;
  const float cardH = 142.0f;
  const float gap = 18.0f;
  const float startX = origin.x + 22.0f;
  const float startY = origin.y + 20.0f;

  int index = 0;
  if (workspace && workspace->opened) {
    for (const AssetItem& asset : workspace->assets) {
      if (index >= 6) {
        break;
      }
      const int col = index % 2;
      const int row = index / 2;
      const std::string name = Elide(asset.name.empty() ? asset.id : asset.name, 17);
      const std::string meta = Elide(FormatAssetMeta(asset), 22);
      DrawAssetCard(draw, ImVec2(startX + col * (cardW + gap), startY + row * (cardH + gap)),
                    ImVec2(cardW, cardH), name.c_str(), meta.c_str(), asset.type == "video");
      ++index;
    }
  } else if (config.designFixture) {
    DrawAssetCard(draw, ImVec2(startX, startY), ImVec2(cardW, cardH),
                  "WhatsApp Vide...", "VIDEO - 478x850 - 13.87s", true);
    index = 1;
  }

  if (index == 0) {
    draw->AddText(ImVec2(startX, startY), U32(kMuted), "Open Folder to load accepted assets.");
  }

  const int addCol = index % 2;
  const int addRow = index / 2;
  ImVec2 addPos(startX + addCol * (cardW + gap), startY + addRow * (cardH + gap));
  ImVec2 addSize(cardW, cardH);
  ImGui::SetCursorScreenPos(addPos);
  ImGui::PushID("asset-open-folder-plus");
  const bool addPressed = ImGui::InvisibleButton("hit", addSize);
  const bool addHovered = ImGui::IsItemHovered();
  ImGui::PopID();
  const float visualW = 118.0f;
  const float visualH = 118.0f;
  ImVec2 visual(addPos.x + (addSize.x - visualW) * 0.5f, addPos.y + 4.0f);
  DrawDashedRect(draw, visual, ImVec2(visual.x + visualW, visual.y + visualH),
                 addHovered ? U32(kMuted) : U32(kBorder), 10.0f);
  ImVec2 plusMin(visual.x + visualW * 0.5f - 15.0f, visual.y + visualH * 0.5f - 15.0f);
  ImVec2 plusMax(plusMin.x + 30.0f, plusMin.y + 30.0f);
  draw->AddRectFilled(plusMin, plusMax, addHovered ? IM_COL32(31, 38, 43, 255) : U32(kPanel2), 7.0f);
  draw->AddRect(plusMin, plusMax, U32(kDivider), 7.0f, 0, 1.1f);
  draw->AddLine(ImVec2(plusMin.x + 9.0f, plusMin.y + 15.0f), ImVec2(plusMax.x - 9.0f, plusMin.y + 15.0f), U32(kMuted), 2.0f);
  draw->AddLine(ImVec2(plusMin.x + 15.0f, plusMin.y + 9.0f), ImVec2(plusMin.x + 15.0f, plusMax.y - 9.0f), U32(kMuted), 2.0f);
  if (addPressed) {
    result.command = "OpenProject";
  }
}

void DrawPreviewViewport(ImDrawList* draw, ImVec2 stageOrigin, ImVec2 stageSize, const EditorShellConfig& config) {
  const float previewHeight = std::min(stageSize.y * 0.90f, stageSize.x * 0.60f);
  const float previewWidth = previewHeight * 9.0f / 16.0f;
  ImVec2 preview(stageOrigin.x + stageSize.x * 0.5f - previewWidth * 0.5f,
                 stageOrigin.y + stageSize.y * 0.5f - previewHeight * 0.5f - 4.0f);
  ImVec2 previewMax(preview.x + previewWidth, preview.y + previewHeight);

  draw->AddRectFilled(preview, previewMax, IM_COL32(2, 4, 5, 255), 12.0f);
  draw->AddRect(preview, previewMax, U32(kBorder), 12.0f, 0, 2.0f);

  if (config.finalFrameSurfaceReady && config.finalFrameSurfaceTexture) {
    draw->AddImage(config.finalFrameSurfaceTexture, preview, previewMax);
    return;
  }

  if (config.workspace && config.workspace->opened) {
    draw->AddRectFilled(ImVec2(preview.x + 22.0f, preview.y + 22.0f),
                        ImVec2(previewMax.x - 22.0f, preview.y + 98.0f),
                        IM_COL32(10, 18, 20, 235), 8.0f);
    draw->AddText(ImVec2(preview.x + 38.0f, preview.y + 40.0f), U32(kText), "Frame 0 requested");
    draw->AddText(ImVec2(preview.x + 38.0f, preview.y + 66.0f), U32(kMuted), "Waiting for FinalFrameSurface");
  }

  const char* message = config.diagnostic ? config.diagnostic : "Preview blocked: FinalFrameSurface is not connected.";
  ImVec2 textSize = ImGui::CalcTextSize(message, nullptr, false, previewWidth - 64.0f);
  draw->AddText(ImGui::GetFont(), ImGui::GetFontSize(), ImVec2(preview.x + 34.0f, preview.y + previewHeight * 0.5f - textSize.y * 0.5f),
                U32(kMuted), message, nullptr, previewWidth - 64.0f);
}

void DrawStage(ImDrawList* draw, ImVec2 origin, ImVec2 size, const EditorShellConfig& config) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  DrawPreviewViewport(draw, origin, size, config);
}

void DrawTransport(ImDrawList* draw, ImVec2 origin, ImVec2 size, const EditorShellConfig& config, EditorShellResult& result) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  draw->AddLine(origin, ImVec2(origin.x + size.x, origin.y), U32(kBorder));
  draw->AddLine(ImVec2(origin.x, origin.y + size.y), ImVec2(origin.x + size.x, origin.y + size.y), U32(kBorder));

  char timecode[64];
  std::snprintf(timecode, sizeof(timecode), "0:%05.2f / 0:%05.2f", config.playbackTimeSeconds, config.durationSeconds);
  ImVec2 textSize = ImGui::CalcTextSize(timecode);
  draw->AddText(ImVec2(origin.x + size.x * 0.5f - textSize.x * 0.5f - 34.0f, origin.y + 13.0f), U32(kText), timecode);

  DrawCommandButton(draw, "transport-play", "PLAY", ImVec2(origin.x + size.x * 0.5f + 76.0f, origin.y + 8.0f),
                    ImVec2(64.0f, 30.0f), result, "BeginPlayback");

  const std::array<const char*, 5> tools{"X", "L", "R", "D", "T"};
  for (int i = 0; i < static_cast<int>(tools.size()); ++i) {
    draw->AddText(ImVec2(origin.x + 44.0f + i * 64.0f, origin.y + 13.0f), U32(kMuted), tools[i]);
  }
  draw->AddText(ImVec2(origin.x + size.x - 182.0f, origin.y + 13.0f), U32(kMuted), "U");
  draw->AddText(ImVec2(origin.x + size.x - 82.0f, origin.y + 13.0f), U32(kMuted), "Y");
}

void DrawTrackRow(ImDrawList* draw, ImVec2 pos, ImVec2 size, const char* label, const char* icon) {
  draw->AddRectFilled(pos, ImVec2(pos.x + size.x, pos.y + size.y), U32(kPanel2), 8.0f);
  draw->AddRect(pos, ImVec2(pos.x + size.x, pos.y + size.y), U32(kBorder), 8.0f, 0, 1.0f);
  const float textY = pos.y + size.y * 0.5f - ImGui::GetFontSize() * 0.5f;
  draw->AddText(ImVec2(pos.x + 18.0f, textY), U32(kMuted), "::");
  draw->AddRectFilled(ImVec2(pos.x + 48.0f, pos.y + 9.0f), ImVec2(pos.x + 76.0f, pos.y + size.y - 9.0f),
                      IM_COL32(4, 10, 16, 255), 7.0f);
  draw->AddText(ImVec2(pos.x + 57.0f, textY), U32(kBlue), icon);
  draw->AddText(ImVec2(pos.x + 96.0f, textY), U32(kText), label);
  draw->AddText(ImVec2(pos.x + size.x - 58.0f, textY), U32(kMuted), "O");
  draw->AddText(ImVec2(pos.x + size.x - 26.0f, textY), U32(kMuted), "S");
}

void DrawClip(ImDrawList* draw, ImVec2 pos, ImVec2 size, const char* label, bool blue) {
  draw->AddRectFilled(pos, ImVec2(pos.x + size.x, pos.y + size.y), blue ? IM_COL32(23, 75, 105, 255) : U32(kDeepPurple), 8.0f);
  const float handle = std::min(18.0f, size.x * 0.28f);
  draw->AddRectFilled(pos, ImVec2(pos.x + handle, pos.y + size.y), blue ? U32(kBlue) : U32(kPurple), 8.0f, ImDrawFlags_RoundCornersLeft);
  draw->AddRectFilled(ImVec2(pos.x + size.x - handle, pos.y), ImVec2(pos.x + size.x, pos.y + size.y), blue ? U32(kBlue) : U32(kPurple), 8.0f, ImDrawFlags_RoundCornersRight);
  ImVec2 text = ImGui::CalcTextSize(label);
  draw->AddText(ImVec2(pos.x + size.x * 0.5f - text.x * 0.5f, pos.y + size.y * 0.5f - text.y * 0.5f), U32(kText), label);
}

void DrawTimeline(ImDrawList* draw, ImVec2 origin, ImVec2 size, float trackWidth, const EditorShellConfig& config, EditorShellResult& result) {
  const float rulerHeight = 30.0f;
  const float rowHeight = 40.0f;
  const float rowGap = 8.0f;
  const float sidePad = 8.0f;
  const float lanePad = 8.0f;
  const float rowStartY = origin.y + rulerHeight;

  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), IM_COL32(3, 8, 9, 255));
  draw->AddLine(ImVec2(origin.x + trackWidth, origin.y), ImVec2(origin.x + trackWidth, origin.y + size.y), U32(kBorder));
  draw->AddLine(origin, ImVec2(origin.x + size.x, origin.y), U32(kBorder));
  draw->AddLine(ImVec2(origin.x, origin.y + size.y - 1.0f), ImVec2(origin.x + size.x, origin.y + size.y - 1.0f), U32(kBorder));

  std::vector<TrackItem> tracks;
  if (config.workspace && config.workspace->opened) {
    tracks = config.workspace->tracks;
  } else if (config.designFixture) {
    tracks = {
        {"track_video", "Video", "video", false, false, {{"clip_video", "Video", "video", "track_video", "", 2.0, 13.0}}},
        {"track_shape", "Shape", "shape", false, false, {{"clip_shape", "Shape", "shape", "track_shape", "", 3.0, 1.5}}},
        {"track_shape_2", "Shape 2", "shape", false, false, {{"clip_shape_2", "Shap...", "shape", "track_shape_2", "", 5.0, 1.4}}},
        {"track_shape_3", "Shape 3", "shape", false, false, {{"clip_shape_3", "Shap...", "shape", "track_shape_3", "", 1.4, 1.3}}},
        {"track_shape_4", "Shape 4", "shape", false, false, {{"clip_shape_4", "Shap...", "shape", "track_shape_4", "", 3.1, 1.3}}},
    };
  }

  const int visibleTrackCount = std::min<int>(static_cast<int>(tracks.size()), 6);
  for (int i = 0; i < visibleTrackCount; ++i) {
    const TrackItem& track = tracks[i];
    const char* icon = track.kind == "video" ? "[]" : track.kind == "audio" ? "A" : track.kind == "text" ? "T" : "<>";
    const std::string label = Elide(track.name.empty() ? track.kind : track.name, 24);
    DrawTrackRow(draw, ImVec2(origin.x + sidePad, rowStartY + i * (rowHeight + rowGap)),
                 ImVec2(trackWidth - sidePad * 2.0f - 8.0f, rowHeight), label.c_str(), icon);
  }

  draw->AddRectFilled(ImVec2(origin.x + trackWidth, origin.y), ImVec2(origin.x + size.x, origin.y + rulerHeight), U32(kBg));
  for (int i = 0; i <= 60; ++i) {
    float x = origin.x + trackWidth + i * 30.0f;
    char label[8];
    std::snprintf(label, sizeof(label), "%d", i);
    draw->AddText(ImVec2(x + 4.0f, origin.y + 6.0f), U32(kMuted), label);
  }
  for (int i = 0; i < std::max(visibleTrackCount, 3); ++i) {
    float y = rowStartY + i * (rowHeight + rowGap);
    draw->AddRectFilled(ImVec2(origin.x + trackWidth + lanePad, y), ImVec2(origin.x + size.x - lanePad, y + rowHeight), U32(kLane), 6.0f);
  }

  if (tracks.empty()) {
    draw->AddText(ImVec2(origin.x + trackWidth + 34.0f, origin.y + rulerHeight + 44.0f), U32(kMuted),
                  "Timeline is waiting for accepted OpenProject state.");
    return;
  }

  const double duration = (config.workspace && config.workspace->durationSeconds > 0.0)
                              ? config.workspace->durationSeconds
                              : std::max(1.0, config.durationSeconds);
  const float secondsToPixels = std::max(28.0f, (size.x - trackWidth - 48.0f) / static_cast<float>(std::max(8.0, duration)));
  const float timelineLeft = origin.x + trackWidth + lanePad;
  const float timelineRight = origin.x + size.x - lanePad;
  ImGui::SetCursorScreenPos(ImVec2(timelineLeft, origin.y));
  ImGui::PushID("timeline-live-scrub-zone");
  const bool scrubHit = ImGui::InvisibleButton("hit", ImVec2(std::max(1.0f, timelineRight - timelineLeft), size.y));
  const bool scrubActive = ImGui::IsItemActive();
  ImGui::PopID();
  if (scrubHit || scrubActive) {
    const float mouseX = ImGui::GetIO().MousePos.x;
    const double requested = static_cast<double>((std::clamp(mouseX, timelineLeft, timelineRight) - timelineLeft) / secondsToPixels);
    const double nextTime = std::clamp(requested, 0.0, duration);
    const double frameStep = (config.workspace && config.workspace->fps > 0.0) ? (1.0 / config.workspace->fps) : (1.0 / 30.0);
    if (scrubHit || std::abs(nextTime - config.playbackTimeSeconds) >= frameStep * 0.35) {
      result.command = "ScrubTimeline";
      result.timelineTimeSeconds = nextTime;
    }
  }

  const float playheadX = std::clamp(
      timelineLeft + static_cast<float>(std::clamp(config.playbackTimeSeconds, 0.0, duration)) * secondsToPixels,
      timelineLeft,
      timelineRight);
  for (int i = 0; i < visibleTrackCount; ++i) {
    const TrackItem& track = tracks[i];
    for (const ClipItem& clip : track.clips) {
      const float x = timelineLeft + static_cast<float>(clip.startSeconds) * secondsToPixels;
      const float w = std::max(42.0f, static_cast<float>(clip.durationSeconds) * secondsToPixels);
      const float y = rowStartY + 5.0f + i * (rowHeight + rowGap);
      const std::string label = Elide(clip.name.empty() ? clip.type : clip.name, 16);
      DrawClip(draw, ImVec2(x, y), ImVec2(w, rowHeight - 10.0f), label.c_str(), clip.type != "video");
    }
  }

  draw->AddRectFilled(ImVec2(playheadX, origin.y), ImVec2(playheadX + 4.0f, origin.y + size.y), U32(kGreen));
  draw->AddTriangleFilled(ImVec2(playheadX - 6.0f, origin.y + rulerHeight - 4.0f),
                          ImVec2(playheadX + 10.0f, origin.y + rulerHeight - 4.0f),
                          ImVec2(playheadX + 2.0f, origin.y + rulerHeight + 7.0f),
                          U32(kGreen));
}

}  // namespace

EditorShellResult DrawEditorShell(const EditorShellConfig& config) {
  ConfigureStyle();

  EditorShellResult result;
  ImGuiViewport* viewport = ImGui::GetMainViewport();
  ImVec2 origin = viewport->WorkPos;
  ImVec2 size = viewport->WorkSize;
  ImDrawList* draw = ImGui::GetForegroundDrawList();

  ImGui::SetNextWindowPos(origin);
  ImGui::SetNextWindowSize(size);
  ImGui::Begin("MakelabRoot", nullptr,
               ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize |
                   ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus);

  const float toolbarHeight = 58.0f;
  const float timelineHeight = std::clamp(size.y * 0.285f, 250.0f, 452.0f);
  const float transportHeight = 42.0f;
  const float leftStackWidth = std::clamp(size.x * 0.212f, 356.0f, 420.0f);
  const float railWidth = std::clamp(leftStackWidth * 0.145f, 50.0f, 62.0f);
  const float assetsWidth = leftStackWidth - railWidth;

  ImVec2 top(origin.x, origin.y);
  ImVec2 rail(origin.x, origin.y + toolbarHeight);
  ImVec2 assets(origin.x + railWidth, origin.y + toolbarHeight);
  ImVec2 stage(origin.x + railWidth + assetsWidth, origin.y + toolbarHeight);
  ImVec2 transport(origin.x + leftStackWidth, origin.y + size.y - timelineHeight - transportHeight);
  ImVec2 timeline(origin.x, origin.y + size.y - timelineHeight);

  DrawTopToolbar(draw, top, ImVec2(size.x, toolbarHeight), result);
  DrawLeftRail(draw, rail, ImVec2(railWidth, size.y - toolbarHeight - timelineHeight));
  DrawAssetsPanel(draw, assets, ImVec2(assetsWidth, size.y - toolbarHeight - timelineHeight), config, result);
  DrawStage(draw, stage, ImVec2(size.x - leftStackWidth, size.y - toolbarHeight - timelineHeight - transportHeight), config);
  DrawTransport(draw, transport, ImVec2(size.x - leftStackWidth, transportHeight), config, result);
  DrawTimeline(draw, timeline, ImVec2(size.x, timelineHeight), leftStackWidth, config, result);

  const ImU32 divider = U32(kDivider);
  const float contentBottom = timeline.y;
  draw->AddLine(ImVec2(origin.x, origin.y + toolbarHeight - 1.0f),
                ImVec2(origin.x + size.x, origin.y + toolbarHeight - 1.0f), divider, 1.35f);
  draw->AddLine(ImVec2(origin.x + railWidth - 1.0f, origin.y + toolbarHeight),
                ImVec2(origin.x + railWidth - 1.0f, contentBottom), divider, 1.25f);
  draw->AddLine(ImVec2(origin.x + leftStackWidth - 1.0f, origin.y + toolbarHeight),
                ImVec2(origin.x + leftStackWidth - 1.0f, contentBottom), divider, 1.35f);
  draw->AddLine(ImVec2(origin.x, contentBottom - 1.0f), ImVec2(origin.x + leftStackWidth, contentBottom - 1.0f), divider, 1.25f);

  ImGui::End();
  return result;
}

}  // namespace makelab::imgui
