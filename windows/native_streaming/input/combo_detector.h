/**
 * combo_detector.h — Button combo detection for overlay trigger + mouse mode.
 */
#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <windows.h>

namespace jujostream {
namespace input {

class ComboDetector {
public:
    static ComboDetector &instance();

    void setOverlayCombo(int combo, int holdMs);
    void setMouseModeCombo(int combo, int holdMs);

    // Called each poll tick with current moonlight button state
    void update(uint32_t buttonFlags);

    // Callbacks (set by GamepadMethodHandler at startup)
    std::function<void()>               onComboDetected;
    std::function<void(const std::string &)> onOverlayDpad;
    std::function<void()>               onMouseModeToggle;

private:
    ComboDetector() = default;
    int   overlay_combo_    = 0;
    int   overlay_hold_ms_  = 1500;
    DWORD overlay_start_    = 0;
    bool  overlay_fired_    = false;

    int   mouse_combo_      = 0;
    int   mouse_hold_ms_    = 1500;
    DWORD mouse_start_      = 0;
    bool  mouse_fired_      = false;
};

}  // namespace input
}  // namespace jujostream
