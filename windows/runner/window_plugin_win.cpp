/**
 * window_plugin_win.cpp
 *
 * Handles 'com.jujostream/window' MethodChannel:
 *   setFullscreen({enabled: bool}) — enter/exit borderless fullscreen
 *   F11 WM_KEYDOWN → invoke 'onF11' back to Dart.
 *
 * Borderless fullscreen strategy:
 *   - Save window style + RECT before going fullscreen.
 *   - Remove WS_OVERLAPPEDWINDOW, resize to cover monitor.
 *   - On exit: restore saved style + RECT.
 */
#include "window_plugin_win.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <optional>

namespace jujostream {

static flutter::MethodChannel<flutter::EncodableValue> *g_channel = nullptr;

// Saved state for restoring from fullscreen
static LONG              g_savedStyle   = 0;
static LONG              g_savedExStyle = 0;
static WINDOWPLACEMENT   g_savedPlacement = { sizeof(WINDOWPLACEMENT) };
static bool              g_isFullscreen = false;

// Top-level HWND (the runner window, not the Flutter child)
static HWND   g_hwnd           = nullptr;

// ─────────────────────────────────────────────────────────────
static bool getBool(const flutter::EncodableMap &m, const std::string &key, bool def = false) {
    auto it = m.find(flutter::EncodableValue(key));
    if (it == m.end()) return def;
    if (auto *v = std::get_if<bool>(&it->second)) return *v;
    return def;
}

// ─────────────────────────────────────────────────────────────
static bool applyFullscreen(bool enabled) {
    if (!g_hwnd) return g_isFullscreen;

    if (enabled && !g_isFullscreen) {
        // Save full window placement (position, size, show-state)
        g_savedStyle    = GetWindowLong(g_hwnd, GWL_STYLE);
        g_savedExStyle  = GetWindowLong(g_hwnd, GWL_EXSTYLE);
        GetWindowPlacement(g_hwnd, &g_savedPlacement);

        // Get the monitor the window currently lives on
        HMONITOR mon = MonitorFromWindow(g_hwnd, MONITOR_DEFAULTTONEAREST);
        MONITORINFO mi = { sizeof(mi) };
        GetMonitorInfo(mon, &mi);
        const RECT &r = mi.rcMonitor;   // full monitor rect incl. taskbar

        // WS_POPUP = zero-decoration window — only style that truly removes
        // the title bar and DWM non-client frame on Win32.
        SetWindowLongPtrW(g_hwnd, GWL_STYLE,   WS_POPUP | WS_VISIBLE);
        SetWindowLongPtrW(g_hwnd, GWL_EXSTYLE, WS_EX_APPWINDOW);

        // HWND_TOPMOST keeps OS chrome (taskbar) from painting over us.
        // SWP_FRAMECHANGED forces the non-client area to be recomputed.
        SetWindowPos(g_hwnd, HWND_TOPMOST,
                     r.left, r.top,
                     r.right  - r.left,
                     r.bottom - r.top,
                     SWP_FRAMECHANGED | SWP_SHOWWINDOW);
        g_isFullscreen = true;

    } else if (!enabled && g_isFullscreen) {
        // Restore original style before repositioning
        SetWindowLongPtrW(g_hwnd, GWL_STYLE,   g_savedStyle);
        SetWindowLongPtrW(g_hwnd, GWL_EXSTYLE, g_savedExStyle);

        // Drop topmost, force frame recalc, then restore placement
        SetWindowPos(g_hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);

        SetWindowPlacement(g_hwnd, &g_savedPlacement);
        g_isFullscreen = false;
    }
    return g_isFullscreen;
}

// ─────────────────────────────────────────────────────────────
// WndProc hook — intercepts F11 before Flutter sees it
// ─────────────────────────────────────────────────────────────
void WindowPluginRegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar) {
    g_hwnd = registrar->GetView()->GetNativeWindow();
    // The registrar gives us the Flutter child HWND; we need the parent Win32 window.
    if (g_hwnd) g_hwnd = GetAncestor(g_hwnd, GA_ROOT);

    registrar->RegisterTopLevelWindowProcDelegate(
        [](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) -> std::optional<LRESULT> {
            if (message != WM_KEYDOWN || wparam != VK_F11) {
                return std::nullopt;
            }

            if (!g_hwnd) {
                g_hwnd = GetAncestor(hwnd, GA_ROOT);
            }

            const bool newState = applyFullscreen(!g_isFullscreen);
            if (g_channel) {
                g_channel->InvokeMethod(
                    "onF11",
                    std::make_unique<flutter::EncodableValue>(newState));
            }
            return 0;
        });

    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(),
        "com.jujostream/window",
        &flutter::StandardMethodCodec::GetInstance());

    g_channel = channel.get();

    channel->SetMethodCallHandler(
        [](const flutter::MethodCall<flutter::EncodableValue> &call,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            if (call.method_name() == "setFullscreen") {
                const auto *pArgs = call.arguments();
                const flutter::EncodableMap *args =
                    pArgs ? std::get_if<flutter::EncodableMap>(pArgs) : nullptr;
                bool enabled = args ? getBool(*args, "enabled", false) : false;
                result->Success(flutter::EncodableValue(applyFullscreen(enabled)));
            } else {
                result->NotImplemented();
            }
        });

    // Keep channel alive
    registrar->AddPlugin(std::make_unique<flutter::Plugin>());
    // Transfer ownership to a static so g_channel stays valid
    static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> s_channel =
        std::move(channel);
    g_channel = s_channel.get();
}

}  // namespace jujostream
