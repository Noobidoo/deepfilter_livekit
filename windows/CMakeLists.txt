cmake_minimum_required(VERSION 3.15)
project(deepfilter_livekit VERSION 0.1.0)

set(PLUGIN_NAME "deepfilter_livekit_plugin")

add_library(${PLUGIN_NAME} SHARED
  "src/deepfilter_plugin.cpp"
)

target_include_directories(${PLUGIN_NAME} PUBLIC
  "include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN 1
)

# Prebuilt DeepFilterNet DLL
set(DEEP_FILTER_DLL "${CMAKE_CURRENT_SOURCE_DIR}/lib/deep_filter_lib.dll")
if(EXISTS "${DEEP_FILTER_DLL}")
  target_link_libraries(${PLUGIN_NAME} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/lib/deep_filter_lib.lib"
  )
  set_target_properties(${PLUGIN_NAME} PROPERTIES
    LINK_FLAGS "/DELAYLOAD:deep_filter_lib.dll"
  )
endif()
