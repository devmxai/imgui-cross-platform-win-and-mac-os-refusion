#include "ui/EditorShell.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <sstream>

#include "imgui.h"
#include "ui/IconGlyphs.hpp"

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
  style.FramePadding = ImVec2(7.0f, 4.0f);
  style.ItemSpacing = ImVec2(4.0f, 4.0f);
  style.WindowRounding = 0.0f;
  style.ChildRounding = 0.0f;
  style.FrameRounding = 5.0f;
  style.GrabRounding = 5.0f;
  style.ScrollbarRounding = 4.0f;
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

ImFont* ResolveIconFont(void* iconFont) {
  return iconFont ? static_cast<ImFont*>(iconFont) : ImGui::GetFont();
}

ImVec2 IconTextSize(ImFont* font, float fontSize, const char* icon) {
  return font->CalcTextSizeA(fontSize, 1000.0f, 0.0f, icon);
}

void DrawCenteredIcon(ImDrawList* draw, ImFont* font, ImVec2 center, const char* icon, ImU32 color, float fontSize = 17.0f) {
  const ImVec2 glyphSize = IconTextSize(font, fontSize, icon);
  draw->AddText(font, fontSize, ImVec2(center.x - glyphSize.x * 0.5f, center.y - glyphSize.y * 0.5f), color, icon);
}

void DrawTextAt(ImDrawList* draw, ImVec2 pos, ImU32 color, const char* text, float fontSize) {
  draw->AddText(ImGui::GetFont(), fontSize, pos, color, text);
}

bool DrawCommandButton(ImDrawList* draw,
                       const char* id,
                       const char* label,
                       ImVec2 pos,
                       ImVec2 size,
                       EditorShellResult& result,
                       const char* command,
                       ImFont* iconFont = nullptr,
                       const char* icon = nullptr) {
  ImGui::SetCursorScreenPos(pos);
  ImGui::PushID(id);
  const bool pressed = ImGui::InvisibleButton("hit", size);
  const bool hovered = ImGui::IsItemHovered();
  ImGui::PopID();

  draw->AddRectFilled(pos, ImVec2(pos.x + size.x, pos.y + size.y),
                      hovered ? IM_COL32(28, 34, 39, 255) : U32(kPanel2), 5.0f);
  draw->AddRect(pos, ImVec2(pos.x + size.x, pos.y + size.y), U32(kBorder), 5.0f, 0, 1.0f);
  const ImVec2 text = ImGui::CalcTextSize(label);
  const float iconSize = 12.0f;
  const ImVec2 glyph = (iconFont && icon) ? IconTextSize(iconFont, iconSize, icon) : ImVec2(0.0f, 0.0f);
  const float gap = (iconFont && icon && label[0] != '\0') ? 6.0f : 0.0f;
  const float contentWidth = glyph.x + gap + text.x;
  const float contentX = pos.x + size.x * 0.5f - contentWidth * 0.5f;
  if (iconFont && icon) {
    draw->AddText(iconFont, iconSize,
                  ImVec2(contentX, pos.y + size.y * 0.5f - glyph.y * 0.5f),
                  U32(kText), icon);
  }
  if (label[0] != '\0') {
    draw->AddText(ImVec2(contentX + glyph.x + gap, pos.y + size.y * 0.5f - text.y * 0.5f), U32(kText), label);
  }

  if (pressed) {
    result.command = command;
    return true;
  }
  return false;
}

void DrawIconGlyph(ImDrawList* draw, ImFont* iconFont, ImVec2 center, const char* icon, bool selected = false) {
  if (selected) {
    draw->AddRectFilled(ImVec2(center.x - 14.0f, center.y - 14.0f), ImVec2(center.x + 14.0f, center.y + 14.0f), U32(kPanel2), 5.0f);
    draw->AddRect(ImVec2(center.x - 14.0f, center.y - 14.0f), ImVec2(center.x + 14.0f, center.y + 14.0f), U32(kBorder), 5.0f, 0, 1.0f);
  }
  DrawCenteredIcon(draw, iconFont, center, icon, selected ? U32(kText) : U32(kMuted), 12.0f);
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

void DrawTopToolbar(ImDrawList* draw, ImVec2 origin, ImVec2 size, ImFont* iconFont, EditorShellResult& result) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  draw->AddLine(ImVec2(origin.x, origin.y + size.y - 1.0f), ImVec2(origin.x + size.x, origin.y + size.y - 1.0f), U32(kDivider), 1.35f);

  const float cy = origin.y + size.y * 0.5f;
  const std::array<const char*, 6> tools{
      icons::kBars,
      icons::kArrowPointer,
      icons::kSquare,
      icons::kHand,
      icons::kMagnifyingGlassMinus,
      icons::kMagnifyingGlassPlus,
  };
  for (int i = 0; i < static_cast<int>(tools.size()); ++i) {
    DrawIconGlyph(draw, iconFont, ImVec2(origin.x + 20.0f + i * 36.0f, cy), tools[i]);
  }

  const std::array<const char*, 9> center{
      icons::kSliders,
      icons::kLayerGroup,
      icons::kAlignLeft,
      icons::kAlignCenter,
      icons::kAlignRight,
      icons::kArrowsLeftRight,
      icons::kArrowsUpDown,
      icons::kShuffle,
      icons::kRotateRight,
  };
  const float centerStart = origin.x + size.x * 0.42f;
  for (int i = 0; i < static_cast<int>(center.size()); ++i) {
    DrawIconGlyph(draw, iconFont, ImVec2(centerStart + i * 36.0f, cy), center[i]);
  }

  const float right = origin.x + size.x - 8.0f;
  DrawCommandButton(draw, "open-folder-top-right", "Open Folder", ImVec2(right - 288.0f, origin.y + 7.0f),
                    ImVec2(116.0f, 30.0f), result, "OpenProject", iconFont, icons::kFolderOpen);
  DrawCommandButton(draw, "render-top-right", "Render", ImVec2(right - 164.0f, origin.y + 7.0f),
                    ImVec2(76.0f, 30.0f), result, "RequestRender", iconFont, icons::kClapperboard);
  DrawCommandButton(draw, "export-top-right", "Export", ImVec2(right - 80.0f, origin.y + 7.0f),
                    ImVec2(80.0f, 30.0f), result, "RequestExport", iconFont, icons::kDownload);
}

void DrawRailIcon(ImDrawList* draw, ImFont* iconFont, ImVec2 center, const char* icon, bool selected) {
  if (selected) {
    draw->AddRectFilled(ImVec2(center.x - 14.0f, center.y - 14.0f), ImVec2(center.x + 14.0f, center.y + 14.0f), U32(kPanel2), 5.0f);
    draw->AddRect(ImVec2(center.x - 14.0f, center.y - 14.0f), ImVec2(center.x + 14.0f, center.y + 14.0f), U32(kDivider), 5.0f, 0, 1.0f);
  }
  DrawCenteredIcon(draw, iconFont, center, icon, selected ? U32(kText) : U32(kMuted), 13.0f);
}

void DrawLeftRail(ImDrawList* draw,
                  ImVec2 origin,
                  ImVec2 size,
                  ImFont* iconFont,
                  LibrarySection selectedSection,
                  EditorShellResult& result) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  draw->AddLine(ImVec2(origin.x + size.x - 1.0f, origin.y), ImVec2(origin.x + size.x - 1.0f, origin.y + size.y), U32(kDivider), 1.25f);
  const std::array<const char*, 5> railIcons{
      icons::kImages,
      icons::kFont,
      icons::kWaveSquare,
      icons::kPalette,
      icons::kShapes,
  };
  for (int i = 0; i < static_cast<int>(railIcons.size()); ++i) {
    ImVec2 center(origin.x + size.x * 0.5f, origin.y + 24.0f + i * 39.0f);
    ImGui::SetCursorScreenPos(ImVec2(center.x - 17.0f, center.y - 17.0f));
    ImGui::PushID(i);
    const bool pressed = ImGui::InvisibleButton("library-section", ImVec2(34.0f, 34.0f));
    ImGui::PopID();
    DrawRailIcon(draw, iconFont, center, railIcons[i], i == static_cast<int>(selectedSection));
    if (pressed) {
      static constexpr std::array<const char*, 5> sectionNames{"media", "text", "audio", "background", "shapes"};
      result.command = "SelectLibrarySection";
      result.payload = sectionNames[i];
    }
  }
}

bool DrawAssetCard(ImDrawList* draw,
                   const char* id,
                   ImVec2 pos,
                   ImVec2 size,
                   const char* name,
                   const char* meta,
                   bool selectedVisual) {
  ImGui::SetCursorScreenPos(pos);
  ImGui::PushID(id);
  ImGui::InvisibleButton("asset-card", size);
  const bool doubleClicked = ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left);
  const bool hovered = ImGui::IsItemHovered();
  ImGui::PopID();
  draw->AddRectFilled(pos, ImVec2(pos.x + size.x, pos.y + size.y), U32(kPanel), 6.0f);
  draw->AddRect(pos, ImVec2(pos.x + size.x, pos.y + size.y), hovered ? U32(kMuted) : U32(kBorder), 6.0f, 0, 1.0f);

  ImVec2 preview(pos.x + 7.0f, pos.y + 7.0f);
  const float previewW = size.x - 14.0f;
  const float previewH = 56.0f;
  draw->AddRectFilled(preview, ImVec2(preview.x + previewW, preview.y + previewH), IM_COL32(7, 11, 12, 255), 4.0f);
  if (selectedVisual) {
    const float pillW = (previewW - 18.0f) * 0.5f;
    const float pillY = preview.y + 6.0f;
    draw->AddRectFilled(ImVec2(preview.x + 5.0f, pillY), ImVec2(preview.x + 5.0f + pillW, pillY + 17.0f), IM_COL32(46, 86, 122, 255), 4.0f);
    draw->AddRectFilled(ImVec2(preview.x + 13.0f + pillW, pillY), ImVec2(preview.x + 13.0f + pillW * 2.0f, pillY + 17.0f), IM_COL32(65, 137, 105, 255), 4.0f);
    DrawTextAt(draw, ImVec2(preview.x + 10.0f, pillY + 2.0f), U32(kText), "Track", 9.0f);
    DrawTextAt(draw, ImVec2(preview.x + 18.0f + pillW, pillY + 2.0f), U32(kText), "Layer", 9.0f);
    const ImVec2 vidText = ImGui::GetFont()->CalcTextSizeA(9.0f, 1000.0f, 0.0f, "VID");
    DrawTextAt(draw, ImVec2(preview.x + previewW * 0.5f - vidText.x * 0.5f, preview.y + 34.0f),
               IM_COL32(170, 194, 255, 255), "VID", 9.0f);
  }

  draw->AddText(ImVec2(pos.x + 7.0f, pos.y + 70.0f), U32(kText), name);
  DrawTextAt(draw, ImVec2(pos.x + 7.0f, pos.y + 89.0f), U32(kMuted), meta, 10.0f);
  return doubleClicked;
}

bool DrawLibraryActionTile(ImDrawList* draw,
                           ImFont* iconFont,
                           const char* id,
                           ImVec2 pos,
                           ImVec2 size,
                           const char* icon,
                           const char* label,
                           ImU32 accent = 0) {
  ImGui::SetCursorScreenPos(pos);
  ImGui::PushID(id);
  const bool pressed = ImGui::InvisibleButton("library-action", size);
  const bool hovered = ImGui::IsItemHovered();
  ImGui::PopID();
  draw->AddRectFilled(pos, ImVec2(pos.x + size.x, pos.y + size.y), hovered ? IM_COL32(20, 27, 30, 255) : U32(kPanel), 6.0f);
  draw->AddRect(pos, ImVec2(pos.x + size.x, pos.y + size.y), hovered ? U32(kMuted) : U32(kBorder), 6.0f, 0, 1.0f);
  const ImU32 iconColor = accent != 0 ? accent : U32(kBlue);
  DrawCenteredIcon(draw, iconFont, ImVec2(pos.x + size.x * 0.5f, pos.y + 31.0f), icon, iconColor, 17.0f);
  const ImVec2 text = ImGui::CalcTextSize(label);
  draw->AddText(ImVec2(pos.x + size.x * 0.5f - text.x * 0.5f, pos.y + size.y - 25.0f), U32(kText), label);
  return pressed;
}

void DrawAssetsPanel(ImDrawList* draw,
                     ImVec2 origin,
                     ImVec2 size,
                     ImFont* iconFont,
                     const EditorShellConfig& config,
                     EditorShellResult& result) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  draw->AddLine(ImVec2(origin.x, origin.y), ImVec2(origin.x, origin.y + size.y), U32(kDivider), 1.25f);
  draw->AddLine(ImVec2(origin.x + size.x - 1.0f, origin.y), ImVec2(origin.x + size.x - 1.0f, origin.y + size.y), U32(kDivider), 1.35f);
  draw->AddLine(origin, ImVec2(origin.x + size.x, origin.y), U32(kDivider), 1.25f);

  const WorkspaceViewState* workspace = config.workspace;
  const float cardW = 108.0f;
  const float cardH = 108.0f;
  const float gap = 9.0f;
  const float startX = origin.x + 10.0f;
  const float startY = origin.y + 10.0f;
  int index = 0;

  auto drawImportTile = [&](const char* command) {
    ImVec2 addPos(startX + (index % 2) * (cardW + gap), startY + (index / 2) * (cardH + gap));
    ImVec2 addSize(cardW, cardH);
    ImGui::SetCursorScreenPos(addPos);
    ImGui::PushID(command);
    const bool addPressed = ImGui::InvisibleButton("asset-import-plus", addSize);
    const bool addHovered = ImGui::IsItemHovered();
    ImGui::PopID();
    const float visualW = 96.0f;
    const float visualH = 96.0f;
    ImVec2 visual(addPos.x + (addSize.x - visualW) * 0.5f, addPos.y + 4.0f);
    DrawDashedRect(draw, visual, ImVec2(visual.x + visualW, visual.y + visualH),
                   addHovered ? U32(kMuted) : U32(kBorder), 10.0f);
    ImVec2 plusMin(visual.x + visualW * 0.5f - 11.0f, visual.y + visualH * 0.5f - 11.0f);
    ImVec2 plusMax(plusMin.x + 22.0f, plusMin.y + 22.0f);
    draw->AddRectFilled(plusMin, plusMax, addHovered ? IM_COL32(31, 38, 43, 255) : U32(kPanel2), 5.0f);
    draw->AddRect(plusMin, plusMax, U32(kDivider), 5.0f, 0, 1.0f);
    DrawCenteredIcon(draw, iconFont, ImVec2(plusMin.x + 11.0f, plusMin.y + 11.0f), icons::kPlus, U32(kMuted), 11.0f);
    if (addPressed) {
      result.command = command;
    }
  };

  if (config.librarySection == LibrarySection::Media || config.librarySection == LibrarySection::Audio) {
    const bool audioSection = config.librarySection == LibrarySection::Audio;
    if (workspace && workspace->opened) {
      for (const AssetItem& asset : workspace->assets) {
        if ((audioSection && asset.type != "audio") || (!audioSection && asset.type == "audio")) {
          continue;
        }
        if (index >= 8) {
          break;
        }
        const int col = index % 2;
        const int row = index / 2;
        const std::string name = Elide(asset.name.empty() ? asset.id : asset.name, 17);
        const std::string meta = Elide(FormatAssetMeta(asset), 22);
        if (DrawAssetCard(draw, asset.id.c_str(), ImVec2(startX + col * (cardW + gap), startY + row * (cardH + gap)),
                          ImVec2(cardW, cardH), name.c_str(), meta.c_str(), asset.type == "video")) {
          result.command = "AddAssetClip";
          result.payload = asset.id;
        }
        ++index;
      }
    } else if (config.designFixture && !audioSection) {
      DrawAssetCard(draw, "fixture-video", ImVec2(startX, startY), ImVec2(cardW, cardH),
                    "WhatsApp Vide...", "VIDEO - 478x850 - 13.87s", true);
      index = 1;
    }
    drawImportTile(audioSection ? "ImportAudio" : "ImportMedia");
    return;
  }

  const auto tilePosition = [&](int tileIndex) {
    return ImVec2(startX + (tileIndex % 2) * (cardW + gap), startY + (tileIndex / 2) * (cardH + gap));
  };
  if (config.librarySection == LibrarySection::Text) {
    const std::array<std::pair<const char*, const char*>, 3> presets{{
        {"body", "Text"}, {"title", "Title"}, {"caption", "Caption"},
    }};
    for (int i = 0; i < static_cast<int>(presets.size()); ++i) {
      if (DrawLibraryActionTile(draw, iconFont, presets[i].first, tilePosition(i), ImVec2(cardW, cardH),
                                icons::kFont, presets[i].second)) {
        result.command = "AddTextLayer";
        result.payload = presets[i].first;
      }
    }
    return;
  }
  if (config.librarySection == LibrarySection::Background) {
    const std::array<std::pair<const char*, ImU32>, 3> colors{{
        {"#00000000", IM_COL32(120, 130, 138, 255)},
        {"#101618", IM_COL32(16, 22, 24, 255)},
        {"#FFFFFF", IM_COL32(240, 243, 246, 255)},
    }};
    const std::array<const char*, 3> labels{"Blank", "Dark", "White"};
    for (int i = 0; i < static_cast<int>(colors.size()); ++i) {
      if (DrawLibraryActionTile(draw, iconFont, colors[i].first, tilePosition(i), ImVec2(cardW, cardH),
                                icons::kSquare, labels[i], colors[i].second)) {
        result.command = "AddBackgroundLayer";
        result.payload = colors[i].first;
      }
    }
    return;
  }
  if (config.librarySection == LibrarySection::Shapes) {
    const std::array<const char*, 4> kinds{"rectangle", "circle", "line", "arrow"};
    const std::array<const char*, 4> labels{"Rectangle", "Circle", "Line", "Arrow"};
    for (int i = 0; i < static_cast<int>(kinds.size()); ++i) {
      if (DrawLibraryActionTile(draw, iconFont, kinds[i], tilePosition(i), ImVec2(cardW, cardH),
                                icons::kShapes, labels[i])) {
        result.command = "AddShapeLayer";
        result.payload = kinds[i];
      }
    }
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

void DrawLiveScope(ImDrawList* draw, ImVec2 stageOrigin, ImVec2 stageSize, const EditorShellConfig& config) {
  if (!config.liveScope.ready) {
    return;
  }
  const float panelW = 148.0f;
  const float panelH = 84.0f;
  ImVec2 pos(stageOrigin.x + stageSize.x - panelW - 18.0f, stageOrigin.y + 18.0f);
  ImVec2 max(pos.x + panelW, pos.y + panelH);
  draw->AddRectFilled(pos, max, IM_COL32(8, 14, 16, 230), 6.0f);
  draw->AddRect(pos, max, U32(kBorder), 6.0f, 0, 1.0f);

  char label[48];
  std::snprintf(label, sizeof(label), "Scope F%lld", static_cast<long long>(config.liveScope.frameIndex));
  DrawTextAt(draw, ImVec2(pos.x + 8.0f, pos.y + 6.0f), U32(kMuted), label, 9.0f);

  const float barBase = max.y - 12.0f;
  const float barTop = pos.y + 28.0f;
  const float barW = (panelW - 18.0f) / static_cast<float>(config.liveScope.lumaBuckets.size());
  for (int i = 0; i < static_cast<int>(config.liveScope.lumaBuckets.size()); ++i) {
    const float value = std::clamp(config.liveScope.lumaBuckets[i], 0.0f, 1.0f);
    const float x = pos.x + 8.0f + i * barW;
    const float h = (barBase - barTop) * value;
    draw->AddRectFilled(ImVec2(x, barBase - h), ImVec2(x + std::max(1.0f, barW - 1.0f), barBase),
                        IM_COL32(113, 226, 170, 210), 1.0f);
  }
  const float chipY = pos.y + 18.0f;
  draw->AddRectFilled(ImVec2(max.x - 48.0f, chipY), ImVec2(max.x - 38.0f, chipY + 5.0f),
                      IM_COL32(static_cast<int>(config.liveScope.averageR * 255.0f), 58, 58, 255), 2.0f);
  draw->AddRectFilled(ImVec2(max.x - 33.0f, chipY), ImVec2(max.x - 23.0f, chipY + 5.0f),
                      IM_COL32(58, static_cast<int>(config.liveScope.averageG * 255.0f), 58, 255), 2.0f);
  draw->AddRectFilled(ImVec2(max.x - 18.0f, chipY), ImVec2(max.x - 8.0f, chipY + 5.0f),
                      IM_COL32(58, 58, static_cast<int>(config.liveScope.averageB * 255.0f), 255), 2.0f);
}

void DrawPerformanceTelemetry(ImDrawList* draw, ImVec2 stageOrigin, ImVec2 stageSize, const EditorShellConfig& config) {
  if (!config.telemetry.ready) {
    return;
  }
  const float panelW = 236.0f;
  const float panelH = 70.0f;
  ImVec2 pos(stageOrigin.x + 16.0f, stageOrigin.y + stageSize.y - panelH - 16.0f);
  ImVec2 max(pos.x + panelW, pos.y + panelH);
  draw->AddRectFilled(pos, max, IM_COL32(8, 14, 16, 220), 6.0f);
  draw->AddRect(pos, max, U32(kBorder), 6.0f, 0, 1.0f);

  char line[128];
  std::snprintf(line, sizeof(line), "Render %.2fms / budget %.2fms",
                config.telemetry.renderSubmitMs,
                config.telemetry.frameBudgetMs);
  DrawTextAt(draw, ImVec2(pos.x + 8.0f, pos.y + 7.0f), U32(kMuted), line, 9.5f);
  std::snprintf(line, sizeof(line), "Scope %.2fms  Surface %.2fMB",
                config.telemetry.liveScopeReadbackMs,
                config.telemetry.finalSurfaceMegabytes);
  DrawTextAt(draw, ImVec2(pos.x + 8.0f, pos.y + 26.0f), U32(kMuted), line, 9.5f);
  std::snprintf(line, sizeof(line), "Frame req %lld / acc %lld  gen %llu",
                static_cast<long long>(config.telemetry.requestedFrameIndex),
                static_cast<long long>(config.telemetry.acceptedFrameIndex),
                static_cast<unsigned long long>(config.telemetry.requestGeneration));
  DrawTextAt(draw, ImVec2(pos.x + 8.0f, pos.y + 45.0f), U32(kMuted), line, 9.5f);
}

void DrawExportProgress(ImDrawList* draw, ImVec2 stageOrigin, ImVec2 stageSize, const EditorShellConfig& config) {
  if (!config.exportProgress.inFlight) {
    return;
  }
  const float panelW = std::min(420.0f, stageSize.x - 48.0f);
  const float panelH = 92.0f;
  ImVec2 pos(stageOrigin.x + stageSize.x * 0.5f - panelW * 0.5f, stageOrigin.y + stageSize.y - panelH - 26.0f);
  ImVec2 max(pos.x + panelW, pos.y + panelH);
  draw->AddRectFilled(pos, max, IM_COL32(8, 14, 16, 238), 8.0f);
  draw->AddRect(pos, max, U32(kBorder), 8.0f, 0, 1.2f);

  const double normalized = std::clamp(config.exportProgress.progress, 0.0, 1.0);
  char title[96];
  std::snprintf(title, sizeof(title), "Export %.0f%%", normalized * 100.0);
  DrawTextAt(draw, ImVec2(pos.x + 16.0f, pos.y + 13.0f), U32(kText), title, 12.0f);
  DrawTextAt(draw, ImVec2(pos.x + 16.0f, pos.y + 34.0f), U32(kMuted),
             config.exportProgress.phase && config.exportProgress.phase[0] != '\0'
                 ? config.exportProgress.phase
                 : "FinalFrameSurface export is running",
             10.5f);

  ImVec2 bar(pos.x + 16.0f, pos.y + 58.0f);
  ImVec2 barMax(max.x - 16.0f, pos.y + 68.0f);
  draw->AddRectFilled(bar, barMax, IM_COL32(18, 28, 31, 255), 5.0f);
  draw->AddRectFilled(bar, ImVec2(bar.x + (barMax.x - bar.x) * static_cast<float>(normalized), barMax.y),
                      IM_COL32(113, 226, 170, 235), 5.0f);
  draw->AddRect(bar, barMax, U32(kDivider), 5.0f, 0, 1.0f);

  if (config.exportProgress.destination && config.exportProgress.destination[0] != '\0') {
    DrawTextAt(draw, ImVec2(pos.x + 16.0f, pos.y + 74.0f), U32(kMuted), config.exportProgress.destination, 8.5f);
  }
}

void DrawStage(ImDrawList* draw, ImVec2 origin, ImVec2 size, const EditorShellConfig& config) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  DrawPreviewViewport(draw, origin, size, config);
  DrawPerformanceTelemetry(draw, origin, size, config);
  DrawLiveScope(draw, origin, size, config);
  DrawExportProgress(draw, origin, size, config);
}

void DrawTransport(ImDrawList* draw,
                   ImVec2 origin,
                   ImVec2 size,
                   ImFont* iconFont,
                   const EditorShellConfig& config,
                   EditorShellResult& result) {
  draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), U32(kBg));
  draw->AddLine(origin, ImVec2(origin.x + size.x, origin.y), U32(kBorder));
  draw->AddLine(ImVec2(origin.x, origin.y + size.y), ImVec2(origin.x + size.x, origin.y + size.y), U32(kBorder));

  const auto rate = config.workspace ? config.workspace->frameRate : config.frameRate;
  const int64_t durationFrames = std::max<int64_t>(
      0,
      config.workspace && config.workspace->durationFrames > 0 ? config.workspace->durationFrames : config.durationFrames);
  const int64_t requestedFrame = makelab::timeline::ClampFrame(config.requestedFrameIndex, std::max<int64_t>(0, durationFrames));
  const std::string timecode = makelab::timeline::FrameToClockTimecode({requestedFrame}, rate) + " / " +
                               makelab::timeline::FrameToClockTimecode({std::max<int64_t>(0, durationFrames)}, rate);
  ImVec2 textSize = ImGui::CalcTextSize(timecode.c_str());
  draw->AddText(ImVec2(origin.x + size.x * 0.5f - textSize.x * 0.5f - 24.0f,
                       origin.y + size.y * 0.5f - textSize.y * 0.5f),
                U32(kText), timecode.c_str());

  DrawCommandButton(draw, "transport-play", "", ImVec2(origin.x + size.x * 0.5f + 66.0f, origin.y + 5.0f),
                    ImVec2(30.0f, 24.0f), result, "BeginPlayback", iconFont, icons::kPlay);

  const std::array<const char*, 5> tools{
      icons::kScissors,
      icons::kBackwardStep,
      icons::kForwardStep,
      icons::kCopy,
      icons::kTrash,
  };
  for (int i = 0; i < static_cast<int>(tools.size()); ++i) {
    DrawCenteredIcon(draw, iconFont, ImVec2(origin.x + 32.0f + i * 40.0f, origin.y + size.y * 0.5f),
                     tools[i], U32(kMuted), 11.0f);
  }
  DrawCenteredIcon(draw, iconFont, ImVec2(origin.x + size.x - 72.0f, origin.y + size.y * 0.5f),
                   icons::kRotateLeft, U32(kMuted), 11.0f);
  DrawCenteredIcon(draw, iconFont, ImVec2(origin.x + size.x - 30.0f, origin.y + size.y * 0.5f),
                   icons::kRotateRight, U32(kMuted), 11.0f);
}

void DrawTrackRow(ImDrawList* draw, ImVec2 pos, ImVec2 size, ImFont* iconFont, const char* label, const char* icon) {
  draw->AddRectFilled(pos, ImVec2(pos.x + size.x, pos.y + size.y), U32(kPanel2), 5.0f);
  draw->AddRect(pos, ImVec2(pos.x + size.x, pos.y + size.y), U32(kBorder), 5.0f, 0, 1.0f);
  const float textY = pos.y + size.y * 0.5f - ImGui::GetFontSize() * 0.5f;
  DrawCenteredIcon(draw, iconFont, ImVec2(pos.x + 14.0f, pos.y + size.y * 0.5f), icons::kGripVertical, U32(kMuted), 10.0f);
  draw->AddRectFilled(ImVec2(pos.x + 28.0f, pos.y + 4.0f), ImVec2(pos.x + 50.0f, pos.y + size.y - 4.0f),
                      IM_COL32(4, 10, 16, 255), 4.0f);
  DrawCenteredIcon(draw, iconFont, ImVec2(pos.x + 39.0f, pos.y + size.y * 0.5f), icon, U32(kBlue), 10.0f);
  draw->AddText(ImVec2(pos.x + 60.0f, textY), U32(kText), label);
  DrawCenteredIcon(draw, iconFont, ImVec2(pos.x + size.x - 38.0f, pos.y + size.y * 0.5f), icons::kEye, U32(kMuted), 10.0f);
  DrawCenteredIcon(draw, iconFont, ImVec2(pos.x + size.x - 16.0f, pos.y + size.y * 0.5f), icons::kVolumeHigh, U32(kMuted), 10.0f);
}

void DrawClip(ImDrawList* draw, ImVec2 pos, ImVec2 size, const char* label, bool blue) {
  draw->AddRectFilled(pos, ImVec2(pos.x + size.x, pos.y + size.y), blue ? IM_COL32(23, 75, 105, 255) : U32(kDeepPurple), 5.0f);
  const float handle = std::min(12.0f, size.x * 0.25f);
  draw->AddRectFilled(pos, ImVec2(pos.x + handle, pos.y + size.y), blue ? U32(kBlue) : U32(kPurple), 5.0f, ImDrawFlags_RoundCornersLeft);
  draw->AddRectFilled(ImVec2(pos.x + size.x - handle, pos.y), ImVec2(pos.x + size.x, pos.y + size.y), blue ? U32(kBlue) : U32(kPurple), 5.0f, ImDrawFlags_RoundCornersRight);
  ImVec2 text = ImGui::CalcTextSize(label);
  draw->AddText(ImVec2(pos.x + size.x * 0.5f - text.x * 0.5f, pos.y + size.y * 0.5f - text.y * 0.5f), U32(kText), label);
}

void DrawTimeline(ImDrawList* draw,
                  ImVec2 origin,
                  ImVec2 size,
                  float trackWidth,
                  ImFont* iconFont,
                  const EditorShellConfig& config,
                  EditorShellResult& result) {
  const float rulerHeight = 18.0f;
  const float rowHeight = 30.0f;
  const float rowGap = 3.0f;
  const float sidePad = 5.0f;
  const float lanePad = 5.0f;
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
        {"track_video", "Video", "video", false, false, {{"clip_video", "Video", "video", "track_video", "", 0, 0, 2.0, 13.0}}},
        {"track_shape", "Shape", "shape", false, false, {{"clip_shape", "Shape", "shape", "track_shape", "", 0, 0, 3.0, 1.5}}},
        {"track_shape_2", "Shape 2", "shape", false, false, {{"clip_shape_2", "Shap...", "shape", "track_shape_2", "", 0, 0, 5.0, 1.4}}},
        {"track_shape_3", "Shape 3", "shape", false, false, {{"clip_shape_3", "Shap...", "shape", "track_shape_3", "", 0, 0, 1.4, 1.3}}},
        {"track_shape_4", "Shape 4", "shape", false, false, {{"clip_shape_4", "Shap...", "shape", "track_shape_4", "", 0, 0, 3.1, 1.3}}},
    };
  }

  const int visibleTrackCount = std::min<int>(static_cast<int>(tracks.size()), 6);
  for (int i = 0; i < visibleTrackCount; ++i) {
    const TrackItem& track = tracks[i];
    const char* icon = track.kind == "video"   ? icons::kVideo
                       : track.kind == "audio" ? icons::kMusic
                       : track.kind == "text"  ? icons::kFont
                       : track.kind == "image" ? icons::kImage
                                                : icons::kShapes;
    const std::string label = Elide(track.name.empty() ? track.kind : track.name, 24);
    DrawTrackRow(draw, ImVec2(origin.x + sidePad, rowStartY + i * (rowHeight + rowGap)),
                 ImVec2(trackWidth - sidePad * 2.0f - 5.0f, rowHeight), iconFont, label.c_str(), icon);
  }

  draw->AddRectFilled(ImVec2(origin.x + trackWidth, origin.y), ImVec2(origin.x + size.x, origin.y + rulerHeight), U32(kBg));
  for (int i = 0; i < std::max(visibleTrackCount, 3); ++i) {
    float y = rowStartY + i * (rowHeight + rowGap);
    draw->AddRectFilled(ImVec2(origin.x + trackWidth + lanePad, y), ImVec2(origin.x + size.x - lanePad, y + rowHeight), U32(kLane), 4.0f);
  }

  if (tracks.empty()) {
    draw->AddText(ImVec2(origin.x + trackWidth + 34.0f, origin.y + rulerHeight + 44.0f), U32(kMuted),
                  "Timeline is waiting for accepted OpenProject state.");
    return;
  }

  const float timelineLeft = origin.x + trackWidth + lanePad;
  const float timelineRight = origin.x + size.x - lanePad;
  const auto rate = config.workspace ? config.workspace->frameRate : config.frameRate;
  const int64_t durationFrames = std::max<int64_t>(
      1,
      config.workspace && config.workspace->durationFrames > 0
          ? config.workspace->durationFrames
          : (config.durationFrames > 0
                 ? config.durationFrames
                 : makelab::timeline::SecondsToFrameRound(std::max(1.0, config.durationSeconds), rate)));
  const float pixelsPerFrame = std::max(
      0.25f,
      (timelineRight - timelineLeft) / static_cast<float>(std::max<int64_t>(1, durationFrames)));
  const double timelineSeconds = makelab::timeline::FrameToSeconds({durationFrames}, rate);
  const double pixelsPerSecond = pixelsPerFrame * static_cast<float>(makelab::timeline::Fps(rate));
  const std::array<double, 10> rulerSteps{0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0};
  double rulerStepSeconds = 1.0;
  for (double candidate : rulerSteps) {
    rulerStepSeconds = candidate;
    if (candidate * pixelsPerSecond >= 46.0) {
      break;
    }
  }
  const int majorTickCount = static_cast<int>(std::floor(timelineSeconds / rulerStepSeconds));
  for (int tick = 0; tick <= majorTickCount; ++tick) {
    const double seconds = static_cast<double>(tick) * rulerStepSeconds;
    const int64_t tickFrame = makelab::timeline::SecondsToFrameRound(seconds, rate);
    const float x = timelineLeft + static_cast<float>(tickFrame) * pixelsPerFrame;
    if (x < timelineLeft - 1.0f || x > timelineRight + 1.0f) {
      continue;
    }
    char label[16];
    if (rulerStepSeconds < 1.0) {
      std::snprintf(label, sizeof(label), "%.2g", seconds);
    } else {
      std::snprintf(label, sizeof(label), "%d", static_cast<int>(std::llround(seconds)));
    }
    DrawTextAt(draw, ImVec2(x + 3.0f, origin.y + 3.0f), U32(kMuted), label, 9.0f);
  }
  ImGui::SetCursorScreenPos(ImVec2(timelineLeft, origin.y));
  ImGui::PushID("timeline-live-scrub-zone");
  const bool scrubHit = ImGui::InvisibleButton("hit", ImVec2(std::max(1.0f, timelineRight - timelineLeft), size.y));
  const bool scrubActive = ImGui::IsItemActive();
  ImGui::PopID();
  if (scrubHit || scrubActive) {
    const float mouseX = ImGui::GetIO().MousePos.x;
    const auto requested = static_cast<int64_t>(std::llround((std::clamp(mouseX, timelineLeft, timelineRight) - timelineLeft) / pixelsPerFrame));
    const int64_t nextFrame = makelab::timeline::ClampFrame(requested, durationFrames);
    if (scrubHit || nextFrame != config.requestedFrameIndex) {
      result.command = "ScrubTimeline";
      result.timelineFrameIndex = nextFrame;
    }
  }

  const float playheadX = std::clamp(
      timelineLeft + static_cast<float>(makelab::timeline::ClampFrame(config.requestedFrameIndex, durationFrames)) * pixelsPerFrame,
      timelineLeft,
      timelineRight);
  for (int i = 0; i < visibleTrackCount; ++i) {
    const TrackItem& track = tracks[i];
    for (const ClipItem& clip : track.clips) {
      const int64_t durationFrameCount = clip.durationFrames > 0
                                             ? clip.durationFrames
                                             : std::max<int64_t>(1, makelab::timeline::SecondsToFrameRound(clip.durationSeconds, rate));
      const int64_t startFrame = clip.durationFrames > 0
                                     ? std::max<int64_t>(0, clip.startFrame)
                                     : makelab::timeline::SecondsToFrameRound(clip.startSeconds, rate);
      const float x = timelineLeft + static_cast<float>(startFrame) * pixelsPerFrame;
      const float w = std::max(1.0f, static_cast<float>(durationFrameCount) * pixelsPerFrame);
      const float y = rowStartY + 3.0f + i * (rowHeight + rowGap);
      const std::string label = Elide(clip.name.empty() ? clip.type : clip.name, 16);
      DrawClip(draw, ImVec2(x, y), ImVec2(w, rowHeight - 6.0f), label.c_str(), clip.type != "video");
    }
  }

  draw->AddRectFilled(ImVec2(playheadX, origin.y), ImVec2(playheadX + 2.0f, origin.y + size.y), U32(kGreen));
  draw->AddTriangleFilled(ImVec2(playheadX - 4.0f, origin.y + rulerHeight - 3.0f),
                          ImVec2(playheadX + 6.0f, origin.y + rulerHeight - 3.0f),
                          ImVec2(playheadX + 1.0f, origin.y + rulerHeight + 4.0f),
                          U32(kGreen));
}

}  // namespace

EditorShellResult DrawEditorShell(const EditorShellConfig& config) {
  ConfigureStyle();

  EditorShellResult result;
  ImFont* iconFont = ResolveIconFont(config.iconFont);
  ImGuiViewport* viewport = ImGui::GetMainViewport();
  ImVec2 origin = viewport->WorkPos;
  ImVec2 size = viewport->WorkSize;
  ImDrawList* draw = ImGui::GetForegroundDrawList();

  ImGui::SetNextWindowPos(origin);
  ImGui::SetNextWindowSize(size);
  ImGui::Begin("MakelabRoot", nullptr,
               ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize |
                   ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus);

  const float toolbarHeight = 44.0f;
  const float timelineHeight = std::clamp(size.y * 0.23f, 205.0f, 330.0f);
  const float transportHeight = 34.0f;
  const float leftStackWidth = std::clamp(size.x * 0.18f, 302.0f, 340.0f);
  const float railWidth = 42.0f;
  const float assetsWidth = leftStackWidth - railWidth;

  ImVec2 top(origin.x, origin.y);
  ImVec2 rail(origin.x, origin.y + toolbarHeight);
  ImVec2 assets(origin.x + railWidth, origin.y + toolbarHeight);
  ImVec2 stage(origin.x + railWidth + assetsWidth, origin.y + toolbarHeight);
  ImVec2 transport(origin.x + leftStackWidth, origin.y + size.y - timelineHeight - transportHeight);
  ImVec2 timeline(origin.x, origin.y + size.y - timelineHeight);

  DrawTopToolbar(draw, top, ImVec2(size.x, toolbarHeight), iconFont, result);
  DrawLeftRail(draw, rail, ImVec2(railWidth, size.y - toolbarHeight - timelineHeight),
               iconFont, config.librarySection, result);
  DrawAssetsPanel(draw, assets, ImVec2(assetsWidth, size.y - toolbarHeight - timelineHeight), iconFont, config, result);
  DrawStage(draw, stage, ImVec2(size.x - leftStackWidth, size.y - toolbarHeight - timelineHeight - transportHeight), config);
  DrawTransport(draw, transport, ImVec2(size.x - leftStackWidth, transportHeight), iconFont, config, result);
  DrawTimeline(draw, timeline, ImVec2(size.x, timelineHeight), leftStackWidth, iconFont, config, result);

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
