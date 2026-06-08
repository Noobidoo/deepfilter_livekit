cmake_minimum_required(VERSION 3.13)
project(deepfilter_livekit VERSION 0.1.0)

set(PLUGIN_NAME "deepfilter_livekit_plugin")

add_library(${PLUGIN_NAME} SHARED
  "src/deepfilter_plugin.cc"
  "src/deepfilter_adapter.cc"
)

target_include_directories(${PLUGIN_NAME} PUBLIC
  "include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter_linux)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN 1
)

# Copy libdeep_filter_lib.so next to the plugin SO so the adapter can load it
set(DEEP_FILTER_SO "${CMAKE_CURRENT_SOURCE_DIR}/lib/libdeep_filter_lib.so")
if(EXISTS "${DEEP_FILTER_SO}")
  add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${DEEP_FILTER_SO}"
      "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/libdeep_filter_lib.so"
    COMMENT "deepfilter_adapter: copying libdeep_filter_lib.so to output"
  )
  set(${PROJECT_NAME}_bundled_libraries "${DEEP_FILTER_SO}" PARENT_SCOPE)
endif()

# Bundle model files next to the plugin SO
set(MODELS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../assets/models")
if(EXISTS "${MODELS_DIR}/DeepFilterNet3_onnx.tar.gz")
  add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${MODELS_DIR}"
      "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/models"
    COMMENT "deepfilter_adapter: copying models to output"
  )
endif()
