import sys

content = open("windows/native_streaming/input/wgi_handler.cpp", "r").read()

old_code = """                ComPtr<IGamepad> gp;
                if (statics_ && SUCCEEDED(statics_->FromGameController(gc.Get(), &gp)) && gp) {
                    continue; // Skip XInput / standard WGI gamepad
                }"""

new_code = """                ComPtr<IGamepadStatics2> statics2;
                if (statics_ && SUCCEEDED(statics_.As(&statics2))) {
                    ComPtr<IGamepad> gp;
                    if (SUCCEEDED(statics2->FromGameController(gc.Get(), &gp)) && gp) {
                        continue; // Skip XInput / standard WGI gamepad
                    }
                }"""

content = content.replace(old_code, new_code)

old_code2 = """        ComPtr<IGamepad> gp;
        if (statics_ && SUCCEEDED(statics_->FromGameController(gc.Get(), &gp)) && gp) {
            continue; 
        }"""

new_code2 = """        ComPtr<IGamepadStatics2> statics2;
        if (statics_ && SUCCEEDED(statics_.As(&statics2))) {
            ComPtr<IGamepad> gp;
            if (SUCCEEDED(statics2->FromGameController(gc.Get(), &gp)) && gp) {
                continue; 
            }
        }"""

content = content.replace(old_code2, new_code2)

open("windows/native_streaming/input/wgi_handler.cpp", "w").write(content)
