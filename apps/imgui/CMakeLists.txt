cmake_minimum_required(VERSION 3.24)

project(MakelabImGuiProfessional LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

include(FetchContent)

FetchContent_Declare(
  imgui
  GIT_REPOSITORY https://github.com/ocornut/imgui.git
  GIT_TAG fc5e2f28fedf6bbe0d20885a5a144d1206a3474e
  GIT_SHALLOW TRUE
)

FetchContent_Declare(
  nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
  URL_HASH SHA256=42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa
)

set(LUNASVG_BUILD_EXAMPLES OFF CACHE BOOL "Disable LunaSVG examples" FORCE)
set(LUNASVG_DISABLE_LOAD_SYSTEM_FONTS ON CACHE BOOL "Keep SVG rasterization deterministic" FORCE)
FetchContent_Declare(
  lunasvg
  GIT_REPOSITORY https://github.com/sammycage/lunasvg.git
  GIT_TAG 83c58df8103dc7dca423dfd824992af94d49bed6
  GIT_SHALLOW TRUE
)

FetchContent_MakeAvailable(imgui)
FetchContent_MakeAvailable(nlohmann_json)
FetchContent_MakeAvailable(lunasvg)

add_library(makelab_project_authoring STATIC
  src/authoring/ProjectAuthoringService.cpp
)

target_include_directories(makelab_project_authoring PUBLIC
  src
)

target_link_libraries(makelab_project_authoring PUBLIC
  nlohmann_json::nlohmann_json
)

add_library(makelab_frame_query STATIC
  src/query/FrameQueryService.cpp
)

target_include_directories(makelab_frame_query PUBLIC
  src
)

set(MAKELAB_ICON_FONT
  ${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts/fa-solid-900.otf
)

set(MAKELAB_UI_FONT
  ${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts/Inter-Regular.ttf
)

set_source_files_properties(${MAKELAB_ICON_FONT} ${MAKELAB_UI_FONT} PROPERTIES
  MACOSX_PACKAGE_LOCATION "Resources/fonts"
)

add_library(makelab_imgui_backend STATIC
  ${imgui_SOURCE_DIR}/imgui.cpp
  ${imgui_SOURCE_DIR}/imgui_demo.cpp
  ${imgui_SOURCE_DIR}/imgui_draw.cpp
  ${imgui_SOURCE_DIR}/imgui_tables.cpp
  ${imgui_SOURCE_DIR}/imgui_widgets.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_metal.mm
  ${imgui_SOURCE_DIR}/backends/imgui_impl_osx.mm
)

target_compile_options(makelab_imgui_backend PRIVATE
  "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
)

target_include_directories(makelab_imgui_backend PUBLIC
  ${imgui_SOURCE_DIR}
  ${imgui_SOURCE_DIR}/backends
)

target_link_libraries(makelab_imgui_backend PUBLIC
  "-framework AVFoundation"
  "-framework Cocoa"
  "-framework CoreServices"
  "-framework CoreMedia"
  "-framework CoreVideo"
  "-framework GameController"
  "-framework Metal"
  "-framework MetalKit"
  "-framework QuartzCore"
  "-framework UniformTypeIdentifiers"
)

add_executable(makelab-imgui-professional MACOSX_BUNDLE
  ${MAKELAB_ICON_FONT}
  ${MAKELAB_UI_FONT}
  src/platform/macos/MacApp.mm
  src/ui/EditorShell.cpp
)

target_compile_options(makelab-imgui-professional PRIVATE
  "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
)

set_target_properties(makelab-imgui-professional PROPERTIES
  OUTPUT_NAME "Makelab IMGUI Professional"
  MACOSX_BUNDLE_BUNDLE_NAME "Makelab IMGUI Professional"
  MACOSX_BUNDLE_GUI_IDENTIFIER "com.makelab.imgui-professional"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
  MACOSX_BUNDLE_BUNDLE_VERSION "1"
)

install(TARGETS makelab-imgui-professional BUNDLE DESTINATION .)

target_include_directories(makelab-imgui-professional PRIVATE
  src
)

target_link_libraries(makelab-imgui-professional PRIVATE
  makelab_project_authoring
  makelab_frame_query
  makelab_imgui_backend
  lunasvg::lunasvg
  "-framework VideoToolbox"
)

include(CTest)

if(BUILD_TESTING)
  add_executable(project-authoring-service-tests
    tests/ProjectAuthoringServiceTests.cpp
  )
  target_link_libraries(project-authoring-service-tests PRIVATE
    makelab_project_authoring
  )
  add_test(NAME project-authoring-service-tests COMMAND project-authoring-service-tests)

  add_executable(timeline-truth-tests
    tests/TimelineTruthTests.cpp
  )
  target_include_directories(timeline-truth-tests PRIVATE
    src
  )
  add_test(NAME timeline-truth-tests COMMAND timeline-truth-tests)

  add_executable(frame-query-service-tests
    tests/FrameQueryServiceTests.cpp
  )
  target_link_libraries(frame-query-service-tests PRIVATE
    makelab_frame_query
  )
  add_test(NAME frame-query-service-tests COMMAND frame-query-service-tests)

  add_executable(frame-truth-parity-tests
    tests/FrameTruthParityTests.cpp
  )
  target_link_libraries(frame-truth-parity-tests PRIVATE
    makelab_frame_query
  )
  add_test(NAME frame-truth-parity-tests COMMAND frame-truth-parity-tests)

  if(APPLE)
    add_test(
      NAME final-frame-surface-pixel-parity-smoke
      COMMAND $<TARGET_FILE:makelab-imgui-professional>
              --pixel-parity-smoke
              ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/pixel-parity-workspace
              --frame
              15
    )
    add_test(
      NAME final-frame-surface-performance-smoke
      COMMAND $<TARGET_FILE:makelab-imgui-professional>
              --performance-smoke
              ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/pixel-parity-workspace
              --frames
              30
    )
    add_test(
      NAME final-frame-surface-heavy-fx-pixel-parity-smoke
      COMMAND $<TARGET_FILE:makelab-imgui-professional>
              --pixel-parity-smoke
              ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/heavy-fx-workspace
              --frame
              36
    )
    add_test(
      NAME final-frame-surface-heavy-fx-performance-smoke
      COMMAND $<TARGET_FILE:makelab-imgui-professional>
              --performance-smoke
              ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/heavy-fx-workspace
              --frames
              30
    )
    add_test(
      NAME final-frame-surface-heavy-fx-scrub-performance-smoke
      COMMAND $<TARGET_FILE:makelab-imgui-professional>
              --scrub-performance-smoke
              ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/heavy-fx-workspace
              --frames
              18
    )
    add_test(
      NAME final-frame-surface-svg-asset-pixel-parity-smoke
      COMMAND $<TARGET_FILE:makelab-imgui-professional>
              --pixel-parity-smoke
              ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/svg-asset-workspace
              --frame
              12
    )
    add_test(
      NAME final-frame-surface-svg-asset-performance-smoke
      COMMAND $<TARGET_FILE:makelab-imgui-professional>
              --performance-smoke
              ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/svg-asset-workspace
              --frames
              24
    )
  endif()
endif()
