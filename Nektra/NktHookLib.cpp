#include "NktHookLib.h"
#include "MinHook.h"
#include <stdio.h>
#include <stdarg.h>

CNktHookLib::CNktHookLib()
{
	MH_Initialize();
}

CNktHookLib::~CNktHookLib()
{
	MH_Uninitialize();
}

DWORD CNktHookLib::Hook(SIZE_T *lpnHookId, LPVOID *lplpCallOriginal, LPVOID lpProcToHook, LPVOID lpNewProcAddr, DWORD dwFlags)
{
	if (!lpProcToHook || !lpNewProcAddr)
		return ERROR_INVALID_PARAMETER;

	MH_STATUS status = MH_CreateHook(lpProcToHook, lpNewProcAddr, lplpCallOriginal);
	if (status != MH_OK && status != MH_ERROR_ALREADY_CREATED) {
		return (DWORD)status;
	}

	status = MH_EnableHook(lpProcToHook);
	if (status != MH_OK && status != MH_ERROR_ENABLED) {
		return (DWORD)status;
	}

	if (lpnHookId)
		*lpnHookId = (SIZE_T)lpProcToHook;

	return ERROR_SUCCESS;
}

DWORD CNktHookLib::Unhook(SIZE_T nHookId)
{
	MH_STATUS status = MH_DisableHook((LPVOID)nHookId);
	if (status != MH_OK)
		return (DWORD)status;
	return ERROR_SUCCESS;
}

VOID CNktHookLib::UnhookAll()
{
	MH_DisableHook(MH_ALL_HOOKS);
}

DWORD CNktHookLib::SetEnableDebugOutput(BOOL bEnable)
{
	return ERROR_SUCCESS;
}

BOOL CNktHookLib::GetEnableDebugOutput()
{
	return FALSE;
}

namespace NktHookLibHelpers {

HINSTANCE GetModuleBaseAddress(LPCWSTR szDllNameW)
{
	HINSTANCE h = GetModuleHandleW(szDllNameW);
	if (!h)
		h = LoadLibraryW(szDllNameW);
	return h;
}

LPVOID GetProcedureAddress(HINSTANCE hDll, LPCSTR szProcNameA)
{
	if (!hDll || !szProcNameA)
		return NULL;
	return (LPVOID)GetProcAddress(hDll, szProcNameA);
}

VOID DebugVPrint(LPCSTR szFormatA, va_list argptr)
{
	vfprintf(stderr, szFormatA, argptr);
	fflush(stderr);
}

VOID DebugPrint(LPCSTR szFormatA, ...)
{
	va_list ap;
	va_start(ap, szFormatA);
	DebugVPrint(szFormatA, ap);
	va_end(ap);
}

} // namespace NktHookLibHelpers
