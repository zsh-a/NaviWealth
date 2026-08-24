cmake_minimum_required(VERSION 3.22.1)

project(naviwealth_speech)

add_library(
    naviwealth_speech
    SHARED
    sherpa_streaming_jni.cpp
)

target_compile_features(naviwealth_speech PRIVATE cxx_std_17)

find_library(log-lib log)

target_link_libraries(
    naviwealth_speech
    ${log-lib}
)
