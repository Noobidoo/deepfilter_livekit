cmake_minimum_required(VERSION 3.22)
project(deep_filter_jni VERSION 1.0)

add_library(deep_filter_jni SHARED
  src/main/cpp/deep_filter_jni.cpp
)

target_include_directories(deep_filter_jni PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp
)

find_library(log-lib log)
target_link_libraries(deep_filter_jni PRIVATE ${log-lib})

# Prebuilt DeepFilterNet library
set(DEEP_FILTER_SO "${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/libdeep_filter_lib.so")
if(EXISTS "${DEEP_FILTER_SO}")
  target_link_libraries(deep_filter_jni PRIVATE "${DEEP_FILTER_SO}")
endif()
