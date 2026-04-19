cmake_minimum_required(VERSION 3.22.1)
project("jujostream_native" C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ============================================================================
# Oboe — low-latency audio library for Android (P1-B)
# ============================================================================
include(FetchContent)
FetchContent_Declare(
    oboe
    GIT_REPOSITORY https://github.com/google/oboe.git
    GIT_TAG        1.9.0
)
FetchContent_MakeAvailable(oboe)

set(MOONLIGHT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/moonlight-common-c)

# ============================================================================
# moonlight-common-c source files
# ============================================================================
set(MOONLIGHT_SOURCES
    ${MOONLIGHT_DIR}/src/AudioStream.c
    ${MOONLIGHT_DIR}/src/ByteBuffer.c
    ${MOONLIGHT_DIR}/src/Connection.c
    ${MOONLIGHT_DIR}/src/ConnectionTester.c
    ${MOONLIGHT_DIR}/src/ControlStream.c
    ${MOONLIGHT_DIR}/src/FakeCallbacks.c
    ${MOONLIGHT_DIR}/src/InputStream.c
    ${MOONLIGHT_DIR}/src/LinkedBlockingQueue.c
    ${MOONLIGHT_DIR}/src/Misc.c
    ${MOONLIGHT_DIR}/src/Platform.c
    ${MOONLIGHT_DIR}/src/PlatformCrypto.c
    ${MOONLIGHT_DIR}/src/PlatformSockets.c
    ${MOONLIGHT_DIR}/src/RtpAudioQueue.c
    ${MOONLIGHT_DIR}/src/RtpVideoQueue.c
    ${MOONLIGHT_DIR}/src/RtspConnection.c
    ${MOONLIGHT_DIR}/src/RtspParser.c
    ${MOONLIGHT_DIR}/src/SdpGenerator.c
    ${MOONLIGHT_DIR}/src/SimpleStun.c
    ${MOONLIGHT_DIR}/src/VideoDepacketizer.c
    ${MOONLIGHT_DIR}/src/VideoStream.c
    ${MOONLIGHT_DIR}/src/RecorderCallbacks.c
    ${MOONLIGHT_DIR}/reedsolomon/rs.c
    ${MOONLIGHT_DIR}/enet/callbacks.c
    ${MOONLIGHT_DIR}/enet/compress.c
    ${MOONLIGHT_DIR}/enet/host.c
    ${MOONLIGHT_DIR}/enet/list.c
    ${MOONLIGHT_DIR}/enet/packet.c
    ${MOONLIGHT_DIR}/enet/peer.c
    ${MOONLIGHT_DIR}/enet/protocol.c
    ${MOONLIGHT_DIR}/enet/unix.c
)

# ============================================================================
# JNI Bridge source files
# ============================================================================
set(BRIDGE_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/bridge/moonlight_bridge.c
    ${CMAKE_CURRENT_SOURCE_DIR}/bridge/callbacks.c
    ${CMAKE_CURRENT_SOURCE_DIR}/bridge/OboeAudioRenderer.cpp
)

# ============================================================================
# Build the shared library
# ============================================================================
add_library(jujostream_native SHARED
    ${MOONLIGHT_SOURCES}
    ${BRIDGE_SOURCES}
)

target_include_directories(jujostream_native PRIVATE
    ${MOONLIGHT_DIR}/src
    ${MOONLIGHT_DIR}/enet/include
    ${MOONLIGHT_DIR}/reedsolomon
    ${CMAKE_CURRENT_SOURCE_DIR}/bridge
)

# reedsolomon: enable vectorization for FEC performance
set_source_files_properties(
    ${MOONLIGHT_DIR}/reedsolomon/rs.c
    PROPERTIES COMPILE_FLAGS "-ftree-vectorize -funroll-loops"
)

target_compile_definitions(jujostream_native PRIVATE
    HAS_SOCKLEN_T=1
    LC_ANDROID=1
    HAVE_CLOCK_GETTIME=1
    NDEBUG=1
)

# ============================================================================
# OpenSSL - Required by moonlight-common-c for TLS/crypto
# ============================================================================
# Option 1: Use pre-built OpenSSL (recommended for speed)
# Place pre-built libs in: deps/openssl/${ANDROID_ABI}/
set(OPENSSL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/deps/openssl)
if(EXISTS "${OPENSSL_DIR}/${ANDROID_ABI}/libssl.a")
    message(STATUS "Using pre-built OpenSSL from ${OPENSSL_DIR}/${ANDROID_ABI}")

    add_library(ssl STATIC IMPORTED)
    set_target_properties(ssl PROPERTIES
        IMPORTED_LOCATION ${OPENSSL_DIR}/${ANDROID_ABI}/libssl.a)

    add_library(crypto STATIC IMPORTED)
    set_target_properties(crypto PROPERTIES
        IMPORTED_LOCATION ${OPENSSL_DIR}/${ANDROID_ABI}/libcrypto.a)

    target_include_directories(jujostream_native PRIVATE ${OPENSSL_DIR}/include)
    target_link_libraries(jujostream_native ssl crypto)
else()
    message(WARNING "Pre-built OpenSSL not found at ${OPENSSL_DIR}/${ANDROID_ABI}")
    message(WARNING "Build will likely fail. See README for OpenSSL setup instructions.")
    message(WARNING "Quick fix: Use the build-openssl.sh script from the original project")
endif()

# ============================================================================
# libopus - Required for audio decoding
# ============================================================================
set(OPUS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/deps/opus)
if(EXISTS "${OPUS_DIR}/${ANDROID_ABI}/libopus.a")
    message(STATUS "Using pre-built libopus from ${OPUS_DIR}/${ANDROID_ABI}")

    add_library(opus STATIC IMPORTED)
    set_target_properties(opus PROPERTIES
        IMPORTED_LOCATION ${OPUS_DIR}/${ANDROID_ABI}/libopus.a)

    target_include_directories(jujostream_native PRIVATE ${OPUS_DIR}/include)
    target_link_libraries(jujostream_native opus)
else()
    message(WARNING "Pre-built libopus not found at ${OPUS_DIR}/${ANDROID_ABI}")
    message(WARNING "Audio decoding will not work without libopus.")
endif()

# ============================================================================
# Android system libraries
# ============================================================================
target_link_libraries(jujostream_native
    android
    log
    oboe
)
