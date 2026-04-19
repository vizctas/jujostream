# ===========================================================================
# native_streaming — Windows native layer for JujoStream
#
# Builds:
#   1. moonlight_common_c  (STATIC) — protocol library
#   2. native_streaming    (STATIC) — bridge + video + audio + input + plugin
#
# Links against: ws2_32, winmm, d3d11, dxgi, mfplat, mfuuid, mf,
#                xinput, ole32, oleaut32, openssl, opus
# ===========================================================================
cmake_minimum_required(VERSION 3.14)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
set(MOONLIGHT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/moonlight-common-c")
set(DEPS_DIR      "${CMAKE_CURRENT_SOURCE_DIR}/deps")

# ---------------------------------------------------------------------------
# 1. moonlight-common-c (STATIC library)
# ---------------------------------------------------------------------------
set(MOONLIGHT_SOURCES
    # Core protocol
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
    ${MOONLIGHT_DIR}/src/RecorderCallbacks.c
    ${MOONLIGHT_DIR}/src/RtpAudioQueue.c
    ${MOONLIGHT_DIR}/src/RtpVideoQueue.c
    ${MOONLIGHT_DIR}/src/RtspConnection.c
    ${MOONLIGHT_DIR}/src/RtspParser.c
    ${MOONLIGHT_DIR}/src/SdpGenerator.c
    ${MOONLIGHT_DIR}/src/SimpleStun.c
    ${MOONLIGHT_DIR}/src/VideoDepacketizer.c
    ${MOONLIGHT_DIR}/src/VideoStream.c
    ${MOONLIGHT_DIR}/src/rswrapper.c
    # enet — Windows implementation
    ${MOONLIGHT_DIR}/enet/callbacks.c
    ${MOONLIGHT_DIR}/enet/compress.c
    ${MOONLIGHT_DIR}/enet/host.c
    ${MOONLIGHT_DIR}/enet/list.c
    ${MOONLIGHT_DIR}/enet/packet.c
    ${MOONLIGHT_DIR}/enet/peer.c
    ${MOONLIGHT_DIR}/enet/protocol.c
    ${MOONLIGHT_DIR}/enet/win32.c
)

add_library(moonlight_common_c STATIC ${MOONLIGHT_SOURCES})

target_include_directories(moonlight_common_c PUBLIC
    ${MOONLIGHT_DIR}/src
    ${MOONLIGHT_DIR}/enet/include
    ${MOONLIGHT_DIR}/reedsolomon
)

# nanors Reed-Solomon include paths (required by rswrapper.c → rs.c → oblas_lite.c)
target_include_directories(moonlight_common_c PRIVATE
    ${MOONLIGHT_DIR}/nanors
    ${MOONLIGHT_DIR}/nanors/deps
    ${MOONLIGHT_DIR}/nanors/deps/obl
)

target_compile_definitions(moonlight_common_c PRIVATE
    LC_WINDOWS=1
    HAS_SOCKLEN_T=1
    _CRT_SECURE_NO_WARNINGS
    _WINSOCK_DEPRECATED_NO_WARNINGS
)

# Suppress warnings in third-party code
target_compile_options(moonlight_common_c PRIVATE
    /W0
)

# OpenSSL — try manual deps/ path first, then find_package, then known install locations
if(EXISTS "${DEPS_DIR}/openssl/include")
    target_include_directories(moonlight_common_c PRIVATE "${DEPS_DIR}/openssl/include")
else()
    find_package(OpenSSL QUIET)
    if(OPENSSL_FOUND)
        target_include_directories(moonlight_common_c PRIVATE ${OPENSSL_INCLUDE_DIR})
    elseif(EXISTS "C:/Program Files/FireDaemon OpenSSL 3/include")
        target_include_directories(moonlight_common_c PRIVATE "C:/Program Files/FireDaemon OpenSSL 3/include")
        set(OPENSSL_CHOCO_ROOT "C:/Program Files/FireDaemon OpenSSL 3")
    elseif(EXISTS "C:/Program Files/OpenSSL-Win64/include")
        target_include_directories(moonlight_common_c PRIVATE "C:/Program Files/OpenSSL-Win64/include")
        set(OPENSSL_CHOCO_ROOT "C:/Program Files/OpenSSL-Win64")
    elseif(EXISTS "C:/Program Files/OpenSSL/include")
        target_include_directories(moonlight_common_c PRIVATE "C:/Program Files/OpenSSL/include")
        set(OPENSSL_CHOCO_ROOT "C:/Program Files/OpenSSL")
    endif()
endif()

if(EXISTS "${DEPS_DIR}/opus/include")
    target_include_directories(moonlight_common_c PRIVATE
        "${DEPS_DIR}/opus/include"
        "${DEPS_DIR}/opus/include/opus"
    )
endif()

# System libraries for moonlight-common-c
target_link_libraries(moonlight_common_c PRIVATE
    ws2_32
    winmm
)

# Link OpenSSL + Opus static libs if present
if(EXISTS "${DEPS_DIR}/openssl/lib/libssl.lib")
    target_link_libraries(moonlight_common_c PRIVATE
        "${DEPS_DIR}/openssl/lib/libssl.lib"
        "${DEPS_DIR}/openssl/lib/libcrypto.lib"
    )
elseif(EXISTS "${DEPS_DIR}/openssl/lib/ssl.lib")
    target_link_libraries(moonlight_common_c PRIVATE
        "${DEPS_DIR}/openssl/lib/ssl.lib"
        "${DEPS_DIR}/openssl/lib/crypto.lib"
    )
elseif(OPENSSL_FOUND)
    target_link_libraries(moonlight_common_c PRIVATE
        ${OPENSSL_SSL_LIBRARY}
        ${OPENSSL_CRYPTO_LIBRARY}
    )
elseif(DEFINED OPENSSL_CHOCO_ROOT)
    target_link_libraries(moonlight_common_c PRIVATE
        "${OPENSSL_CHOCO_ROOT}/lib/libssl.lib"
        "${OPENSSL_CHOCO_ROOT}/lib/libcrypto.lib"
    )
endif()

if(EXISTS "${DEPS_DIR}/opus/lib/opus.lib")
    target_link_libraries(moonlight_common_c PRIVATE
        "${DEPS_DIR}/opus/lib/opus.lib"
    )
endif()

# ---------------------------------------------------------------------------
# 2. native_streaming (STATIC library — our code)
# ---------------------------------------------------------------------------
set(NATIVE_STREAMING_SOURCES
    # C bridge layer
    bridge/moonlight_bridge_win.c
    bridge/callbacks_win.c
    # C++ plugin layer
    plugin/streaming_plugin_win.cpp
    plugin/method_handler.cpp
    plugin/event_emitter.cpp
    plugin/streaming_bridge_win.cpp
    # C++ video decoder
    video/mft_decoder.cpp
    video/d3d11_device.cpp
    video/nalu_parser.cpp
    video/codec_probe_win.cpp
    video/texture_bridge.cpp
    # C++ audio renderer
    audio/wasapi_renderer.cpp
    audio/audio_ring_buffer.cpp
    audio/audio_format_helper.cpp
    # C++ gamepad input
    input/gamepad_plugin_win.cpp
    input/xinput_handler.cpp
    input/wgi_handler.cpp
    input/combo_detector.cpp
    input/gamepad_method_handler.cpp
)

add_library(native_streaming STATIC ${NATIVE_STREAMING_SOURCES})

target_include_directories(native_streaming PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/bridge
    ${CMAKE_CURRENT_SOURCE_DIR}/video
    ${CMAKE_CURRENT_SOURCE_DIR}/audio
    ${CMAKE_CURRENT_SOURCE_DIR}/input
    ${CMAKE_CURRENT_SOURCE_DIR}/plugin
)

target_include_directories(native_streaming PRIVATE
    ${MOONLIGHT_DIR}/src
    ${MOONLIGHT_DIR}/enet/include
)

if(EXISTS "${DEPS_DIR}/opus/include")
    target_include_directories(native_streaming PRIVATE
        "${DEPS_DIR}/opus/include"
        "${DEPS_DIR}/opus/include/opus"
    )
endif()

target_compile_features(native_streaming PUBLIC cxx_std_17)

target_compile_definitions(native_streaming PRIVATE
    _CRT_SECURE_NO_WARNINGS
    _WINSOCK_DEPRECATED_NO_WARNINGS
    NOMINMAX
    WIN32_LEAN_AND_MEAN
)

# Suppress /WX for our code during development (re-enable for release)
target_compile_options(native_streaming PRIVATE
    /W3
    /wd4100  # unreferenced formal parameter
    /wd4189  # local variable initialized but not referenced
    /EHsc
)

target_link_libraries(native_streaming PUBLIC
    moonlight_common_c
    # Direct3D 11
    d3d11
    dxgi
    # Media Foundation
    mfplat
    mfuuid
    mf
    # XInput
    xinput
    # WASAPI / MMCSS (Pro Audio thread characteristics)
    avrt
    # COM / WinRT
    ole32
    oleaut32
    runtimeobject
    # Networking (inherited from moonlight_common_c, but explicit)
    ws2_32
    winmm
)

# Flutter wrapper — needed for MethodChannel/EventChannel/TextureRegistrar
# This is provided by the Flutter build system
if(TARGET flutter_wrapper_plugin)
    target_link_libraries(native_streaming PUBLIC flutter_wrapper_plugin)
endif()
