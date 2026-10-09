#include "nvprofile.h"

// 3DMigoto MinGW / Wine / DXVK Compatibility: NVProfile Stubs
// NVIDIA Driver Profile management is disabled in Wine / DXVK environments.

ProfileSettings profile_settings;

void log_nv_driver_version()
{
}

void log_check_and_update_nv_profiles()
{
}

int parse_ini_profile_line(std::wstring *lhs, std::wstring *rhs)
{
	return 0;
}

extern "C" void CALLBACK Install3DMigotoDriverProfileW(HWND hwnd, HINSTANCE hinst, LPWSTR lpszCmdLine, int nCmdShow)
{
}
