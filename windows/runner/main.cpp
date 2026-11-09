#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Ensure working directory is always the executable's directory so relative
  // paths (data\assets, data\icudtl.dat, data\app.so) resolve reliably.
  wchar_t exe_path[MAX_PATH];
  DWORD exe_len = ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (exe_len > 0 && exe_len < MAX_PATH) {
    wchar_t* last_slash = wcsrchr(exe_path, L'\\');
    if (last_slash != nullptr) {
      *last_slash = L'\0';
      ::SetCurrentDirectoryW(exe_path);
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  InitializeBetaNativeLogging();

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  DWORD assets_attr = ::GetFileAttributesW(L"data\\assets");
  bool use_stripped_assets = (assets_attr != INVALID_FILE_ATTRIBUTES) &&
                             (assets_attr & FILE_ATTRIBUTE_DIRECTORY);
  flutter::DartProject project(
      use_stripped_assets ? L"data\\assets" : L"data\\flutter_assets",
      L"data\\icudtl.dat",
      L"data\\app.so");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"jujostream", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
