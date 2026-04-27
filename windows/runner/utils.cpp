#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>
#include <string>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout) == 0) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr) == 0) {
      _dup2(_fileno(stderr), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

void InitializeBetaNativeLogging() {
  wchar_t local_app_data[MAX_PATH];
  DWORD len = ::GetEnvironmentVariableW(
      L"LOCALAPPDATA", local_app_data, static_cast<DWORD>(MAX_PATH));
  if (len == 0 || len >= MAX_PATH) {
    return;
  }

  std::wstring base(local_app_data);
  std::wstring app_dir = base + L"\\JujoStream";
  std::wstring log_dir = app_dir + L"\\logs";
  ::CreateDirectoryW(app_dir.c_str(), nullptr);
  ::CreateDirectoryW(log_dir.c_str(), nullptr);

  SYSTEMTIME st;
  ::GetLocalTime(&st);
  wchar_t file_name[128];
  swprintf_s(file_name, L"jujo_native_%04u%02u%02u_%02u%02u%02u.log",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
  std::wstring log_path = log_dir + L"\\" + file_name;

  FILE* out = nullptr;
  if (_wfreopen_s(&out, log_path.c_str(), L"a", stderr) == 0) {
    _dup2(_fileno(stderr), 2);
  }
  if (_wfreopen_s(&out, log_path.c_str(), L"a", stdout) == 0) {
    _dup2(_fileno(stdout), 1);
  }
  std::ios::sync_with_stdio();
  FlutterDesktopResyncOutputStreams();

  fprintf(stderr, "[native] beta log initialized\n");
  fflush(stderr);
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
