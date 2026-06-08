cmake_minimum_required(VERSION 3.13)
project(deepfilter_livekit VERSION 0.1.0)

set(PLUGIN_NAME "deepfilter_livekit_plugin")

add_library(${PLUGIN_NAME} SHARED
  "src/deepfilter_plugin.cc"
)

target_include_directories(${PLUGIN_NAME} PUBLIC
  "include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter_linux)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN 1
)

# Prebuilt DeepFilterNet library
set(DEEP_FILTER_SO "${CMAKE_CURRENT_SOURCE_DIR}/lib/libdeep_filter_lib.so")
if(EXISTS "${DEEP_FILTER_SO}")
  target_link_libraries(${PLUGIN_NAME} PRIVATE
    "${DEEP_FILTER_SO}"
  )
endif()
