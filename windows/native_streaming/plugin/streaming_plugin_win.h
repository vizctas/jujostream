/**
 * streaming_plugin_win.h
 *
 * Flutter plugin registration for Windows streaming.
 * Registers MethodChannel + EventChannel matching Dart contracts.
 */
#pragma once

#include <flutter/plugin_registrar_windows.h>

namespace jujostream {

void StreamingPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar);

}  // namespace jujostream
