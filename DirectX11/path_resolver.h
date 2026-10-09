#pragma once

#include <windows.h>
#include <string>

// Resolves a path case-insensitively on Linux filesystems (ext4/btrfs).
// If the path exists as-is, it is returned unchanged immediately.
// Otherwise, it traverses each component with FindFirstFileW to find the
// exact casing on disk. Results are cached in a thread-safe map.
std::wstring ResolvePathCaseInsensitive(const std::wstring &input_path);
std::string ResolvePathCaseInsensitiveA(const std::string &input_path);

// Installs MinHook hooks on CreateFileW and CreateFileA to transparently
// resolve case-insensitive paths across the entire process (including
// CRT fopen/ifstream and DirectXTK asset loaders).
void InstallPathResolverHooks();
