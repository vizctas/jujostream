/**
 * gamepad_plugin_win.h — Gamepad MethodChannel plugin registration.
 */
#pragma once

#include <flutter/plugin_registrar_windows.h>

namespace jujostream {

void GamepadPluginRegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar);

}  // namespace jujostream
