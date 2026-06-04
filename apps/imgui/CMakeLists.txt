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
  GIT_TAG master
  GIT_SHALLOW TRUE
)

FetchContent_MakeAvailable(imgui)

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
  "-framework CoreMedia"
  "-framework CoreVideo"
  "-framework GameController"
  "-framework Metal"
  "-framework MetalKit"
  "-framework QuartzCore"
)

add_executable(makelab-imgui-professional MACOSX_BUNDLE
  src/platform/macos/MacApp.mm
  src/ui/EditorShell.cpp
)

target_compile_options(makelab-imgui-professional PRIVATE
  "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
)

set_target_properties(makelab-imgui-professional PROPERTIES
  MACOSX_BUNDLE_BUNDLE_NAME "Makelab IMGUI Professional"
  MACOSX_BUNDLE_GUI_IDENTIFIER "com.makelab.imgui-professional"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
  MACOSX_BUNDLE_BUNDLE_VERSION "1"
)

target_include_directories(makelab-imgui-professional PRIVATE
  src
)

target_link_libraries(makelab-imgui-professional PRIVATE
  makelab_imgui_backend
)
