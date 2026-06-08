cmake_minimum_required(VERSION 3.15)
project(deepfilter_livekit VERSION 0.1.0)

set(PLUGIN_NAME "deepfilter_livekit_plugin")

add_library(${PLUGIN_NAME} SHARED
  "src/deepfilter_plugin.cpp"
  "src/deepfilter_adapter.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN 1
)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

# Include flutter_webrtc libwebrtc headers for the APM hook
set(FLUTTER_WEBRTC_LIBWEBRTC_INCLUDE
  "${CMAKE_CURRENT_SOURCE_DIR}/../example/windows/flutter/ephemeral/.plugin_symlinks/flutter_webrtc/third_party/libwebrtc/include"
)
if(EXISTS "${FLUTTER_WEBRTC_LIBWEBRTC_INCLUDE}")
  target_include_directories(${PLUGIN_NAME} PRIVATE "${FLUTTER_WEBRTC_LIBWEBRTC_INCLUDE}")
  set(FLUTTER_WEBRTC_CPP_INCLUDE
    "${CMAKE_CURRENT_SOURCE_DIR}/../example/windows/flutter/ephemeral/.plugin_symlinks/flutter_webrtc/common/cpp/include"
  )
  if(EXISTS "${FLUTTER_WEBRTC_CPP_INCLUDE}")
    target_include_directories(${PLUGIN_NAME} PRIVATE "${FLUTTER_WEBRTC_CPP_INCLUDE}")
  endif()
  set(FLUTTER_WEBRTC_WINDOWS_INCLUDE
    "${CMAKE_CURRENT_SOURCE_DIR}/../example/windows/flutter/ephemeral/.plugin_symlinks/flutter_webrtc/windows"
  )
  if(EXISTS "${FLUTTER_WEBRTC_WINDOWS_INCLUDE}")
    target_include_directories(${PLUGIN_NAME} PRIVATE "${FLUTTER_WEBRTC_WINDOWS_INCLUDE}")
  endif()
  target_compile_definitions(${PLUGIN_NAME} PRIVATE DF_APM_HOOK_AVAILABLE LIB_WEBRTC_API_DLL)
endif()
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
)

# Copy deep_filter_lib.dll next to the plugin DLL so the adapter can load it
set(DEEP_FILTER_DLL "${CMAKE_CURRENT_SOURCE_DIR}/lib/deep_filter_lib.dll")
if(EXISTS "${DEEP_FILTER_DLL}")
  add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${DEEP_FILTER_DLL}"
      "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/deep_filter_lib.dll"
    COMMENT "deepfilter_adapter: copying deep_filter_lib.dll to output"
  )
  set(${PROJECT_NAME}_bundled_libraries "${DEEP_FILTER_DLL}" PARENT_SCOPE)
endif()

# Copy deepfilter.dll (Rust runtime) next to the plugin DLL — capi depends on it
set(DEEP_FILTER_RUNTIME "${CMAKE_CURRENT_SOURCE_DIR}/lib/deepfilter.dll")
if(EXISTS "${DEEP_FILTER_RUNTIME}")
  add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${DEEP_FILTER_RUNTIME}"
      "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/deepfilter.dll"
    COMMENT "deepfilter_adapter: copying deepfilter.dll (Rust runtime) to output"
  )
endif()

# Bundle model files next to the plugin DLL.
# Check windows/lib/models/ first (download_prebuilt script destination),
# then fall back to ../assets/models/ (alternative placement).
set(MODELS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib/models")
if(NOT EXISTS "${MODELS_DIR}")
  set(MODELS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../assets/models")
endif()
file(GLOB _MODEL_FILES "${MODELS_DIR}/*.tar.gz" "${MODELS_DIR}/*.tar")
if(_MODEL_FILES)
  add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${MODELS_DIR}"
      "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/models"
    COMMENT "deepfilter_adapter: copying models to output"
  )
endif()
