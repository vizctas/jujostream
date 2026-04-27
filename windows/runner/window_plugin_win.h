/**
 * window_plugin_win.h
 *
 * Native plugin for window management (fullscreen toggle, F11 handling).
 * Registered via flutter::PluginRegistrarWindows in flutter_window.cpp.
 */
#pragma once

#include <flutter/plugin_registrar_windows.h>

namespace jujostream {

void WindowPluginRegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

}  // namespace jujostream
