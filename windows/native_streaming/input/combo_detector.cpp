/**
 * combo_detector.cpp
 *
 * Button combo detection with configurable button mask + hold time.
 * Called each poll tick from XInputHandler::pollLoop.
 */
#include "combo_detector.h"
#include <windows.h>
#include <cstdio>

namespace jujostream {
namespace input {

ComboDetector &ComboDetector::instance() {
    static ComboDetector inst;
    return inst;
}

void ComboDetector::setOverlayCombo(int combo, int holdMs) {
    overlay_combo_   = combo;
    overlay_hold_ms_ = holdMs;
    overlay_start_   = 0;
    overlay_fired_   = false;
}

void ComboDetector::setMouseModeCombo(int combo, int holdMs) {
    mouse_combo_   = combo;
    mouse_hold_ms_ = holdMs;
    mouse_start_   = 0;
    mouse_fired_   = false;
}

void ComboDetector::update(uint32_t buttonFlags) {
    DWORD now = GetTickCount();

    // --- Overlay combo ---
    if (overlay_combo_ != 0) {
        bool held = (buttonFlags & static_cast<uint32_t>(overlay_combo_)) ==
                     static_cast<uint32_t>(overlay_combo_);
        if (held) {
            if (overlay_start_ == 0) overlay_start_ = now;
            if (!overlay_fired_ &&
                (int)(now - overlay_start_) >= overlay_hold_ms_) {
                overlay_fired_ = true;
                fprintf(stderr, "ComboDetector: overlay combo fired\n");
                if (onComboDetected) onComboDetected();
            }
        } else {
            overlay_start_ = 0;
            overlay_fired_ = false;
        }
    }

    // --- Mouse mode combo ---
    if (mouse_combo_ != 0) {
        bool held = (buttonFlags & static_cast<uint32_t>(mouse_combo_)) ==
                     static_cast<uint32_t>(mouse_combo_);
        if (held) {
            if (mouse_start_ == 0) mouse_start_ = now;
            if (!mouse_fired_ &&
                (int)(now - mouse_start_) >= mouse_hold_ms_) {
                mouse_fired_ = true;
                fprintf(stderr, "ComboDetector: mouse mode toggle\n");
                if (onMouseModeToggle) onMouseModeToggle();
            }
        } else {
            mouse_start_ = 0;
            mouse_fired_ = false;
        }
    }
}

}  // namespace input
}  // namespace jujostream
