#include "path_resolver.h"
#include "MinHook.h"
#include "log.h"

#include <vector>
#include <unordered_map>
#include <algorithm>

static CRITICAL_SECTION s_cacheLock;
static bool s_cacheLockInitialized = false;
static std::unordered_map<std::wstring, std::wstring> s_pathCache;

static void EnsureCacheLock()
{
	if (!s_cacheLockInitialized) {
		InitializeCriticalSection(&s_cacheLock);
		s_cacheLockInitialized = true;
	}
}

std::wstring ResolvePathCaseInsensitive(const std::wstring &input_path)
{
	if (input_path.empty())
		return input_path;

	// Fast path: if the path exists as-is, return immediately
	DWORD attr = GetFileAttributesW(input_path.c_str());
	if (attr != INVALID_FILE_ATTRIBUTES)
		return input_path;

	EnsureCacheLock();

	// Check cache
	EnterCriticalSection(&s_cacheLock);
	auto it = s_pathCache.find(input_path);
	if (it != s_pathCache.end()) {
		std::wstring cached = it->second;
		LeaveCriticalSection(&s_cacheLock);
		return cached;
	}
	LeaveCriticalSection(&s_cacheLock);

	// Normalize separators to backslash
	std::wstring path = input_path;
	for (auto &c : path) {
		if (c == L'/')
			c = L'\\';
	}

	size_t start_idx = 0;
	std::wstring current_dir;

	// Check for Extended-Length Path prefix (\\?\)
	if (path.length() >= 4 && path.substr(0, 4) == L"\\\\?\\") {
		current_dir = path.substr(0, 4);
		start_idx = 4;
	}

	// Check for drive letter (e.g. C:\ or Z:\)
	if (path.length() > start_idx + 1 && path[start_idx + 1] == L':') {
		current_dir += path.substr(start_idx, 2);
		start_idx += 2;
		if (start_idx < path.length() && path[start_idx] == L'\\') {
			current_dir += L'\\';
			start_idx++;
		}
	} else if (start_idx < path.length() && path[start_idx] == L'\\') {
		current_dir += L'\\';
		start_idx++;
	}

	// Split remaining path into segments
	std::vector<std::wstring> segments;
	size_t pos = start_idx;
	while (pos < path.length()) {
		size_t next = path.find(L'\\', pos);
		if (next == std::wstring::npos) {
			if (pos < path.length())
				segments.push_back(path.substr(pos));
			break;
		} else {
			if (next > pos)
				segments.push_back(path.substr(pos, next - pos));
			pos = next + 1;
		}
	}

	// Traverse and resolve each segment
	for (size_t i = 0; i < segments.size(); i++) {
		const std::wstring &seg = segments[i];

		if (seg == L"." || seg == L"..") {
			if (!current_dir.empty() && current_dir.back() != L'\\')
				current_dir += L'\\';
			current_dir += seg;
			continue;
		}

		std::wstring test_path;
		if (current_dir.empty())
			test_path = seg;
		else if (current_dir.back() == L'\\')
			test_path = current_dir + seg;
		else
			test_path = current_dir + L"\\" + seg;

		if (GetFileAttributesW(test_path.c_str()) != INVALID_FILE_ATTRIBUTES) {
			current_dir = test_path;
			continue;
		}

		// Perform case-insensitive directory search
		std::wstring search_pattern;
		if (current_dir.empty())
			search_pattern = L"*";
		else if (current_dir.back() == L'\\')
			search_pattern = current_dir + L"*";
		else
			search_pattern = current_dir + L"\\*";

		WIN32_FIND_DATAW find_data;
		HANDLE hFind = FindFirstFileW(search_pattern.c_str(), &find_data);
		bool found = false;

		if (hFind != INVALID_HANDLE_VALUE) {
			do {
				if (wcscmp(find_data.cFileName, L".") == 0 || wcscmp(find_data.cFileName, L"..") == 0)
					continue;

				if (_wcsicmp(find_data.cFileName, seg.c_str()) == 0) {
					found = true;
					if (!current_dir.empty() && current_dir.back() != L'\\')
						current_dir += L'\\';
					current_dir += find_data.cFileName;
					break;
				}
			} while (FindNextFileW(hFind, &find_data));
			FindClose(hFind);
		}

		if (!found) {
			if (!current_dir.empty() && current_dir.back() != L'\\')
				current_dir += L'\\';
			current_dir += seg;
		}
	}

	// Store in cache
	EnterCriticalSection(&s_cacheLock);
	s_pathCache[input_path] = current_dir;
	LeaveCriticalSection(&s_cacheLock);

	if (current_dir != input_path) {
		LogDebug("Case-resolver: normalized \"%S\" -> \"%S\"\n", input_path.c_str(), current_dir.c_str());
	}

	return current_dir;
}

std::string ResolvePathCaseInsensitiveA(const std::string &input_path)
{
	if (input_path.empty())
		return input_path;

	int wlen = MultiByteToWideChar(CP_UTF8, 0, input_path.c_str(), -1, NULL, 0);
	if (wlen <= 0)
		return input_path;

	std::wstring wide_in(wlen - 1, L'\0');
	MultiByteToWideChar(CP_UTF8, 0, input_path.c_str(), -1, &wide_in[0], wlen);

	std::wstring wide_out = ResolvePathCaseInsensitive(wide_in);

	int mlen = WideCharToMultiByte(CP_UTF8, 0, wide_out.c_str(), -1, NULL, 0, NULL, NULL);
	if (mlen <= 0)
		return input_path;

	std::string multi_out(mlen - 1, '\0');
	WideCharToMultiByte(CP_UTF8, 0, wide_out.c_str(), -1, &multi_out[0], mlen, NULL, NULL);

	return multi_out;
}

// -----------------------------------------------------------------------------
// WinAPI CreateFile Hooking for transparent normalization
// -----------------------------------------------------------------------------

typedef HANDLE(WINAPI *tCreateFileW)(
	LPCWSTR lpFileName,
	DWORD dwDesiredAccess,
	DWORD dwShareMode,
	LPSECURITY_ATTRIBUTES lpSecurityAttributes,
	DWORD dwCreationDisposition,
	DWORD dwFlagsAndAttributes,
	HANDLE hTemplateFile
);

typedef HANDLE(WINAPI *tCreateFileA)(
	LPCSTR lpFileName,
	DWORD dwDesiredAccess,
	DWORD dwShareMode,
	LPSECURITY_ATTRIBUTES lpSecurityAttributes,
	DWORD dwCreationDisposition,
	DWORD dwFlagsAndAttributes,
	HANDLE hTemplateFile
);

static tCreateFileW s_origCreateFileW = NULL;
static tCreateFileA s_origCreateFileA = NULL;

static HANDLE WINAPI Hook_CreateFileW(
	LPCWSTR lpFileName,
	DWORD dwDesiredAccess,
	DWORD dwShareMode,
	LPSECURITY_ATTRIBUTES lpSecurityAttributes,
	DWORD dwCreationDisposition,
	DWORD dwFlagsAndAttributes,
	HANDLE hTemplateFile
)
{
	if (lpFileName && (dwCreationDisposition == OPEN_EXISTING || dwCreationDisposition == OPEN_ALWAYS)) {
		std::wstring resolved = ResolvePathCaseInsensitive(lpFileName);
		return s_origCreateFileW(resolved.c_str(), dwDesiredAccess, dwShareMode,
		                         lpSecurityAttributes, dwCreationDisposition,
		                         dwFlagsAndAttributes, hTemplateFile);
	}

	return s_origCreateFileW(lpFileName, dwDesiredAccess, dwShareMode,
	                         lpSecurityAttributes, dwCreationDisposition,
	                         dwFlagsAndAttributes, hTemplateFile);
}

static HANDLE WINAPI Hook_CreateFileA(
	LPCSTR lpFileName,
	DWORD dwDesiredAccess,
	DWORD dwShareMode,
	LPSECURITY_ATTRIBUTES lpSecurityAttributes,
	DWORD dwCreationDisposition,
	DWORD dwFlagsAndAttributes,
	HANDLE hTemplateFile
)
{
	if (lpFileName && (dwCreationDisposition == OPEN_EXISTING || dwCreationDisposition == OPEN_ALWAYS)) {
		std::string resolved = ResolvePathCaseInsensitiveA(lpFileName);
		return s_origCreateFileA(resolved.c_str(), dwDesiredAccess, dwShareMode,
		                         lpSecurityAttributes, dwCreationDisposition,
		                         dwFlagsAndAttributes, hTemplateFile);
	}

	return s_origCreateFileA(lpFileName, dwDesiredAccess, dwShareMode,
	                         lpSecurityAttributes, dwCreationDisposition,
	                         dwFlagsAndAttributes, hTemplateFile);
}

void InstallPathResolverHooks()
{
	static bool s_installed = false;
	if (s_installed)
		return;
	s_installed = true;

	EnsureCacheLock();

	MH_STATUS status = MH_Initialize();
	if (status != MH_OK && status != MH_ERROR_ALREADY_INITIALIZED) {
		LogInfo("MinHook MH_Initialize failed with status: %d\n", status);
		return;
	}

	status = MH_CreateHook(
		reinterpret_cast<LPVOID>(&CreateFileW),
		reinterpret_cast<LPVOID>(&Hook_CreateFileW),
		reinterpret_cast<LPVOID*>(&s_origCreateFileW)
	);
	if (status == MH_OK) {
		MH_EnableHook(reinterpret_cast<LPVOID>(&CreateFileW));
		LogInfo("Installed CreateFileW case-insensitive resolver hook\n");
	} else {
		LogInfo("Failed to hook CreateFileW: %d\n", status);
	}

	status = MH_CreateHook(
		reinterpret_cast<LPVOID>(&CreateFileA),
		reinterpret_cast<LPVOID>(&Hook_CreateFileA),
		reinterpret_cast<LPVOID*>(&s_origCreateFileA)
	);
	if (status == MH_OK) {
		MH_EnableHook(reinterpret_cast<LPVOID>(&CreateFileA));
		LogInfo("Installed CreateFileA case-insensitive resolver hook\n");
	} else {
		LogInfo("Failed to hook CreateFileA: %d\n", status);
	}
}
