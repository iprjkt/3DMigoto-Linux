#pragma once

#include <windows.h>
#include <unknwn.h>

// 3DMigoto MinGW / Wine / DXVK Compatibility: NVAPI Stub Header
// All proprietary NVIDIA NVAPI calls are stubbed to safe no-op defaults.

typedef int NvAPI_Status;
#define NVAPI_OK 0
#define NVAPI_ERROR -1
#define NVAPI_NOT_SUPPORTED -1
#define NVAPI_STEREO_NOT_ENABLED -2
#define NVAPI_END_ENUMERATION -3

typedef void* StereoHandle;
typedef unsigned char NvU8;
typedef unsigned short NvU16;
typedef unsigned int NvU32;
typedef signed int NvS32;
typedef char NvAPI_ShortString[64];
typedef wchar_t NvAPI_UnicodeString[2048];
#define NVAPI_UNICODE_STRING_MAX 2048
#define NVAPI_SHORT_STRING_MAX 64

typedef enum _NV_STEREO_REGISTRY_PROFILE_TYPE {
	NV_STEREO_REGISTRY_PROFILE_TYPE_NOT_SUPPORTED = 0,
	NV_STEREO_REGISTRY_PROFILE_TYPE_DX9 = 1,
	NV_STEREO_REGISTRY_PROFILE_TYPE_DX10 = 2,
} NV_STEREO_REGISTRY_PROFILE_TYPE;

#define NVAPI_STEREO_DEFAULT_REGISTRY_PROFILE NV_STEREO_REGISTRY_PROFILE_TYPE_NOT_SUPPORTED
#define NVAPI_STEREO_DX9_REGISTRY_PROFILE NV_STEREO_REGISTRY_PROFILE_TYPE_DX9
#define NVAPI_STEREO_DX10_REGISTRY_PROFILE NV_STEREO_REGISTRY_PROFILE_TYPE_DX10
#define NVAPI_STEREO_DRIVER_MODE_DIRECT 0

typedef enum _NV_STEREO_ACTIVE_EYE {
	NVAPI_STEREO_EYE_MONO = 0,
	NVAPI_STEREO_EYE_LEFT = 1,
	NVAPI_STEREO_EYE_RIGHT = 2,
} NV_STEREO_ACTIVE_EYE;

typedef enum _NVAPI_STEREO_SURFACECREATEMODE {
	NVAPI_STEREO_SURFACECREATEMODE_AUTO = 0,
	NVAPI_STEREO_SURFACECREATEMODE_FORCESTEREO = 1,
	NVAPI_STEREO_SURFACECREATEMODE_FORCEMONO = 2,
} NVAPI_STEREO_SURFACECREATEMODE;

typedef struct _NV_DISPLAYCONFIG_PATH_INFO {
	NvU32 version;
	NvU32 sourceModeInfoCount;
	void *targetInfo;
} NV_DISPLAYCONFIG_PATH_INFO;

typedef struct _NV_GET_CURRENT_SLI_STATE {
	NvU32 version;
	NvU32 numGPUs;
	NvU32 maxNumAFRGroups;
} NV_GET_CURRENT_SLI_STATE;
#define NV_GET_CURRENT_SLI_STATE_VER sizeof(NV_GET_CURRENT_SLI_STATE)

// Profile / DRS types for stubbing
typedef void* NvDRSSessionHandle;
typedef void* NvDRSProfileHandle;

typedef enum _NVDRS_SETTING_TYPE {
	NVDRS_DWORD_TYPE = 0,
	NVDRS_BINARY_TYPE = 1,
	NVDRS_WSTRING_TYPE = 2,
} NVDRS_SETTING_TYPE;

typedef enum _NVDRS_SETTING_LOCATION {
	NVDRS_CURRENT_PROFILE_LOCATION = 0,
} NVDRS_SETTING_LOCATION;

typedef struct _NVDRS_SETTING {
	NvU32 version;
	NvAPI_UnicodeString settingName;
	NvU32 settingId;
	NVDRS_SETTING_TYPE settingType;
	NVDRS_SETTING_LOCATION settingLocation;
	NvU32 isCurrentPredefined;
	NvU32 isPredefinedValid;
	union {
		NvU32 u32CurrentValue;
		NvAPI_UnicodeString wszCurrentValue;
		struct {
			NvU32 length;
			NvU8 *data;
		} binaryCurrentValue;
	};
} NVDRS_SETTING;
#define NVDRS_SETTING_VER sizeof(NVDRS_SETTING)

typedef struct _NVDRS_APPLICATION {
	NvU32 version;
	NvAPI_UnicodeString appName;
	NvAPI_UnicodeString userFriendlyName;
	NvAPI_UnicodeString launcher;
	NvAPI_UnicodeString fileInFolder;
	NvU32 isPredefined;
} NVDRS_APPLICATION;
#define NVDRS_APPLICATION_VER sizeof(NVDRS_APPLICATION)

typedef struct _NVDRS_PROFILE {
	NvU32 version;
	NvAPI_UnicodeString profileName;
	NvU32 isPredefined;
	NvU32 numOfApps;
	NvU32 numOfSettings;
} NVDRS_PROFILE;
#define NVDRS_PROFILE_VER sizeof(NVDRS_PROFILE)

// NVAPI function stubs (all inline returning safe defaults)
static inline NvAPI_Status NvAPI_Initialize() { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Unload() { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_GetErrorMessage(NvAPI_Status status, NvAPI_ShortString desc) {
	if (desc) desc[0] = '\0';
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_SYS_GetDriverAndBranchVersion(NvU32 *pDriverVersion, NvAPI_ShortString szBuildBranchString) {
	if (pDriverVersion) *pDriverVersion = 0;
	if (szBuildBranchString) szBuildBranchString[0] = '\0';
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_Stereo_IsEnabled(NvU8 *pIsStereoEnabled) {
	if (pIsStereoEnabled) *pIsStereoEnabled = 0;
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_Stereo_IsActivated(StereoHandle stereoHandle, NvU8 *pIsStereoOn) {
	if (pIsStereoOn) *pIsStereoOn = 0;
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_Stereo_Enable() { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Stereo_SetDriverMode(NvU32 mode) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Stereo_CreateConfigurationProfileRegistryKey(NvU32 registryProfileType) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Stereo_CreateHandleFromIUnknown(IUnknown *pDevice, StereoHandle *pStereoHandle) {
	if (pStereoHandle) *pStereoHandle = (StereoHandle)pDevice;
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_Stereo_DestroyHandle(StereoHandle stereoHandle) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Stereo_GetConvergence(StereoHandle stereoHandle, float *pConvergence) {
	if (pConvergence) *pConvergence = 1.0f;
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_Stereo_SetConvergence(StereoHandle stereoHandle, float newConvergence) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Stereo_GetSeparation(StereoHandle stereoHandle, float *pSeparationPercentage) {
	if (pSeparationPercentage) *pSeparationPercentage = 0.0f;
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_Stereo_SetSeparation(StereoHandle stereoHandle, float newSeparationPercentage) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Stereo_GetEyeSeparation(StereoHandle hStereoHandle, float *pSeparation) {
	if (pSeparation) *pSeparation = 0.0f;
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_Stereo_SetActiveEye(StereoHandle hStereoHandle, NV_STEREO_ACTIVE_EYE StereoEye) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Stereo_ReverseStereoBlitControl(StereoHandle hStereoHandle, NvU8 TurnOn) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Stereo_SetSurfaceCreationMode(StereoHandle hStereoHandle, NVAPI_STEREO_SURFACECREATEMODE creationMode) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_Stereo_GetSurfaceCreationMode(StereoHandle hStereoHandle, NVAPI_STEREO_SURFACECREATEMODE *pCreationMode) {
	if (pCreationMode) *pCreationMode = NVAPI_STEREO_SURFACECREATEMODE_AUTO;
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_Stereo_CapturePngImage(StereoHandle hStereoHandle, wchar_t *filename = NULL) { return NVAPI_NOT_SUPPORTED; }
static inline NvAPI_Status NvAPI_Stereo_GetDefaultProfile(NvAPI_UnicodeString profileName) { return NVAPI_NOT_SUPPORTED; }
static inline NvAPI_Status NvAPI_DISP_GetDisplayConfig(NvU32 *pathInfoCount, NV_DISPLAYCONFIG_PATH_INFO *pathInfo) {
	if (pathInfoCount) *pathInfoCount = 0;
	return NVAPI_OK;
}
static inline NvAPI_Status NvAPI_D3D_GetCurrentSLIState(IUnknown *pDevice, NV_GET_CURRENT_SLI_STATE *pSliState) {
	if (pSliState) {
		pSliState->numGPUs = 1;
		pSliState->maxNumAFRGroups = 1;
	}
	return NVAPI_OK;
}

// DRS stubs
static inline NvAPI_Status NvAPI_DRS_CreateSession(NvDRSSessionHandle *phSession) { if (phSession) *phSession = NULL; return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_DestroySession(NvDRSSessionHandle hSession) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_LoadSettings(NvDRSSessionHandle hSession) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_SaveSettings(NvDRSSessionHandle hSession) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_SaveSettingsToFileEx(NvDRSSessionHandle hSession, const NvAPI_UnicodeString fileName) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_FindProfileByName(NvDRSSessionHandle hSession, NvAPI_UnicodeString profileName, NvDRSProfileHandle *phProfile) { if (phProfile) *phProfile = NULL; return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_FindApplicationByName(NvDRSSessionHandle hSession, NvAPI_UnicodeString appName, NvDRSProfileHandle *phProfile, NVDRS_APPLICATION *pApp) { if (phProfile) *phProfile = NULL; return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_CreateProfile(NvDRSSessionHandle hSession, NVDRS_PROFILE *pProfile, NvDRSProfileHandle *phProfile) { if (phProfile) *phProfile = NULL; return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_CreateApplication(NvDRSSessionHandle hSession, NvDRSProfileHandle hProfile, NVDRS_APPLICATION *pApp) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_GetBaseProfile(NvDRSSessionHandle hSession, NvDRSProfileHandle *phProfile) { if (phProfile) *phProfile = NULL; return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_GetCurrentGlobalProfile(NvDRSSessionHandle hSession, NvDRSProfileHandle *phProfile) { if (phProfile) *phProfile = NULL; return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_GetProfileInfo(NvDRSSessionHandle hSession, NvDRSProfileHandle hProfile, NVDRS_PROFILE *pProfile) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_GetSetting(NvDRSSessionHandle hSession, NvDRSProfileHandle hProfile, NvU32 settingId, NVDRS_SETTING *pSetting) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_SetSetting(NvDRSSessionHandle hSession, NvDRSProfileHandle hProfile, NVDRS_SETTING *pSetting) { return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_GetSettingIdFromName(NvAPI_UnicodeString settingName, NvU32 *pSettingId) { if (pSettingId) *pSettingId = 0; return NVAPI_OK; }
static inline NvAPI_Status NvAPI_DRS_EnumProfiles(NvDRSSessionHandle hSession, NvU32 index, NvDRSProfileHandle *phProfile) { return NVAPI_END_ENUMERATION; }
static inline NvAPI_Status NvAPI_DRS_EnumApplications(NvDRSSessionHandle hSession, NvDRSProfileHandle hProfile, NvU32 startIndex, NvU32 *appCount, NVDRS_APPLICATION *pApp) { if (appCount) *appCount = 0; return NVAPI_END_ENUMERATION; }
static inline NvAPI_Status NvAPI_DRS_EnumSettings(NvDRSSessionHandle hSession, NvDRSProfileHandle hProfile, NvU32 startIndex, NvU32 *settingsCount, NVDRS_SETTING *pSetting) { if (settingsCount) *settingsCount = 0; return NVAPI_END_ENUMERATION; }
