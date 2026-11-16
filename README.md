# 3DMigoto for Linux

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](#building-from-source)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Wine%20%7C%20Proton-orange)](#requirements)
[![DirectX](https://img.shields.io/badge/DirectX-11.0%20%7C%2011.1-blue)](#key-technical-fixes)
[![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey)](LICENSE)

A specialized 64-bit fork of **3DMigoto** engineered natively for **Linux**, **Wine**, **Proton**, and **DXVK**.

This fork eliminates the architectural incompatibilities that previously prevented 3DMigoto and model importers built on top of it (**GIMI**, **SRMI**, **ZZMI**, and **XXMI** packages) from running reliably under Wine/Proton with Unity D3D11 games (*Genshin Impact*, *Honkai: Star Rail*, *Zenless Zone Zero*, etc.).

---

## Table of Contents

- [Overview](#overview)
- [Key Technical Fixes](#key-technical-fixes)
  - [1. COM Identity & IUnknown Pointer Preservation](#1-com-identity--iunknown-pointer-preservation)
  - [2. Deferred Context & Command List Interception](#2-deferred-context--command-list-interception)
  - [3. Modern Interface Fallback (ID3D11Device2+)](#3-modern-interface-fallback-id3d11device2)
  - [4. Host Executable Base Directory & Linux Path Resolution](#4-host-executable-base-directory--linux-path-resolution)
  - [5. Wine PE Loader & Hotpatch Stub Compatibility](#5-wine-pe-loader--hotpatch-stub-compatibility)
  - [6. F10 Reload Stability & Shader State Integrity](#6-f10-reload-stability--shader-state-integrity)
  - [7. Thread-Safe Concurrency & Non-Blocking ShaderRegex Cache](#7-thread-safe-concurrency--non-blocking-shaderregex-cache)
  - [8. Dynamic VertexLimitRaise & Assembler Fixes](#8-dynamic-vertexlimitraise--assembler-fixes)
- [Requirements](#requirements)
- [Setup & Installation](#setup--installation)
  - [Deployment Layout](#deployment-layout)
  - [Option 1: Automated Installer (`install.sh` + `install.conf`) — Recommended](#option-1-automated-installer-installsh--installconf--recommended)
  - [Option 2: Manual Installation](#option-2-manual-installation)
  - [Wine DLL Overrides](#wine-dll-overrides)
  - [Recommended `d3dx.ini` Settings](#recommended-d3dxini-settings)
- [Building from Source](#building-from-source)
- [Troubleshooting](#troubleshooting)
- [Credits & Acknowledgments](#credits--acknowledgments)

---

## Overview

Stock 3DMigoto was originally authored for native Windows and MSVC. When deployed under Wine or Proton with DXVK, several fundamental assumptions break down:

1. **Module location vs Process location**: Wine prefixes typically load `d3d11.dll` from `C:\windows\system32\`. Stock 3DMigoto resolved relative paths (`Mods/`, `Core/`, `ShaderFixes/`) from the DLL module handle rather than the running executable, causing assets to be searched under `C:\windows\system32\Mods/`.
2. **COM identity leakage**: Unity queries `IUnknown` on graphics interfaces. Stock 3DMigoto forwarded `IUnknown` queries to DXVK's underlying `mOrigDevice1` / `mOrigContext1`, leaking raw DXVK pointers and bypassing 3DMigoto's hooks entirely.
3. **Unity Graphics Jobs (Multithreading)**: Unity renders character meshes and UI across worker threads via **Deferred Contexts** (`CreateDeferredContext` / `CreateDeferredContext1`) and concurrent draw calls. Without wrapping deferred contexts and synchronizing shader maps with lightweight `SRWLOCK`s, draw calls either bypass hooks or trigger hash-map races and freezes.
4. **Wine hotpatch and timer semantics**: Synchronous Win32 calls like `Beep()` execute blocking sleeps in Wine, freezing the render thread during shader reload.

---

## Key Technical Fixes

### 1. COM Identity & IUnknown Pointer Preservation
- **Fix**: Patched `HackerDevice::QueryInterface` and `HackerContext::QueryInterface` to preserve COM identity: queries for `__uuidof(IUnknown)` return `this` (with `AddRef()`), guaranteeing Unity cannot escape the wrapper chain.

### 2. Deferred Context & Command List Interception
- **Fix**: Wrapped `HackerDevice::CreateDeferredContext` and `CreateDeferredContext1`, binding 3DMigoto state to worker contexts and handling `ExecuteCommandList` / `FinishCommandList`.

### 3. Modern Interface Fallback (ID3D11Device2+)
- **Fix**: `HackerDevice::QueryInterface` and `HackerContext::QueryInterface` return `E_NOINTERFACE` for `ID3D11Device2+` and `ID3D11DeviceContext2+`, forcing clean fallback to wrapped `ID3D11Device1` / `ID3D11DeviceContext1`.

### 4. Host Executable Base Directory & Linux Path Resolution
- **Fix**: `GetMigotoBaseDirectory()` anchors all mod/config path resolution to the host game executable (`GetModuleFileNameW(NULL, ...)`), paired with an in-memory, thread-safe case-insensitive path resolver (`ResolvePathCaseInsensitive`) hooked on `CreateFileW` / `CreateFileA`.

### 5. Wine PE Loader & Hotpatch Stub Compatibility
- **Fix**: Hardened `DirectX11/DLLMainHook.cpp` so non-critical hooking failures on Wine hotpatch stubs degrade gracefully without aborting `DllMain`.

### 6. F10 Reload Stability & Shader State Integrity
- **Fix**: Removed synchronous `Beep()` calls during config reload and reset `vs_override`, `ps_override`, `cs_override`, etc. whenever shader compilation fails.

### 7. Thread-Safe Concurrency & Non-Blocking ShaderRegex Cache
- **Fix**:
  - Synchronized `G->mShaders`, `G->mReloadedShaders`, `G->mOriginalShaders`, and `G->mShaderOverrideMap` using Windows/Wine `SRWLOCK`s to eliminate concurrent `std::unordered_map` bucket cycles (scene freezes) across Unity Graphics Jobs threads.
  - Decoupled `DeferredShaderReplacement` from `G->mCriticalSection` so shader disassembly, regex matching, assembly, and DXVK shader compilation never block other worker threads.
  - Added a thread-safe in-memory `ShaderRegex` cache (`s_shader_regex_mem_cache`) that also replays command list linking on cache hits.

### 8. Dynamic VertexLimitRaise & Assembler Fixes
- **Fix**:
  - Dynamically registers `[TextureOverride*VertexLimitRaise*]` hashes and supports `override_vertex_count`, `override_byte_stride`, and `byte_width` in `[TextureOverride]`, while guarding `CreateBuffer` so constant/index buffers are never resized and structured buffers preserve stride alignment.
  - Fixed assembler pointer invalidation on vector reallocation, multi-component `l(...)` operands, single-line immediate constant buffers, and infinite loops in `strToWords()`.

---

## Requirements

1. **Operating System**: Linux with Wine 8.0+ or Proton 8.0+ (Proton-GE / Wine-GE recommended).
2. **Graphics API**: DXVK (v2.0 or newer recommended).
3. **Native Microsoft `d3dcompiler_47.dll`** *(Crucial)*:
   > [!IMPORTANT]
   > Wine's built-in `d3dcompiler_47.dll` lacks support for structured resource stores and advanced HLSL bytecode assembly/disassembly. You **must** place the native 64-bit Microsoft `d3dcompiler_47.dll` in the game directory.
4. **Tools for `install.sh`** *(for automated setup)*: `bash`, `git`, `python3` (or `sed`), `curl` & `unzip` (fallback if package assets are in GitHub Releases).

---

## Setup & Installation

### Deployment Layout

The recommended and most reliable Linux/Wine layout separates the D3D11 proxy DLL (in the Wine prefix) from game-specific mod files (in the game directory):

```text
<WINEPREFIX>/drive_c/windows/system32/
├── d3d11.dll            <-- 3DMigoto-Linux d3d11.dll (only here, NOT in game_dir)
└── original_d3d11.dll   <-- Original 64-bit DXVK d3d11.dll

<GAME_DIR>/ (e.g. folder containing GenshinImpact.exe / StarRail.exe / ZenlessZoneZero.exe)
├── d3dcompiler_47.dll   <-- Native 64-bit Microsoft d3dcompiler_47.dll
├── d3dx.ini             <-- Game-specific 3DMigoto configuration
├── Core/                <-- Game-specific Core libraries (GIMI / SRMI / ZZMI)
├── ShaderFixes/         <-- Game-specific ShaderFixes
└── Mods/                <-- Your installed mods
```

> [!NOTE]
> Because `3DMigoto-Linux` resolves `d3dx.ini`, `Core/`, `ShaderFixes/`, and `Mods/` from the running game's `.exe` directory (`GetMigotoBaseDirectory()`), placing `d3d11.dll` inside `<prefix>/drive_c/windows/system32/` works cleanly while keeping mod assets isolated inside each game's directory. If multiple games share one Wine prefix, use separate prefixes per game when games need independent DXVK/3DMigoto isolation.

---

### Option 1: Automated Installer (`install.sh` + `install.conf`) — Recommended

Both the repository and release package include [`install.sh`](install.sh) and [`install.conf`](install.conf), which automatically clone the correct importer package (**GIMI**, **SRMI**, **ZZMI**, or custom repo), configure `d3dx.ini` for Linux/Wine, back up DXVK as `original_d3d11.dll`, deploy `d3d11.dll` to `<prefix>/drive_c/windows/system32/`, and place `d3dcompiler_47.dll` in `<game_dir>/`.

#### Step 1: Make `install.sh` executable (or run with `bash`)
```bash
chmod +x install.sh
```

#### Step 2A: Interactive Install
Run `./install.sh` and follow the prompts to select `GIMI` (Genshin Impact), `SRMI` (Honkai: Star Rail), `ZZMI` (Zenless Zone Zero), or a custom repo URL, then enter your game directory and Wine prefix path:
```bash
./install.sh
```

#### Step 2B: CLI Install & Save to `install.conf`
```bash
# Genshin Impact (GIMI)
./install.sh -g gimi \
  -d "/path/to/Genshin Impact game" \
  -p "~/.local/share/anime-game-launcher/prefix" \
  --save

# Honkai: Star Rail (SRMI)
./install.sh -g srmi \
  -d "/path/to/Honkai Star Rail/Games" \
  -p "~/.local/share/honkers-railway-launcher/prefix" \
  --save

# Zenless Zone Zero (ZZMI)
./install.sh -g zzmi \
  -d "/path/to/ZenlessZoneZero Game" \
  -p "~/.local/share/sleepy-launcher/prefix" \
  --save
```

#### Managing Multiple Games via `install.conf`
Edit [`install.conf`](install.conf) to mark your `game_dir`, `prefix`, `dxvk` (optional), and set `enabled = 1` under `[GIMI]`, `[SRMI]`, `[ZZMI]`, or custom sections:

```bash
# Check configured paths and DLL status across all games
./install.sh --status

# Install or update all enabled=1 games in install.conf
./install.sh --all -y

# Update only d3d11.dll (prefix) & d3dcompiler_47.dll (game_dir) for all enabled games
./install.sh --all --update-dll-only -y

# Uninstall 3DMigoto DLLs (restores DXVK in system32 and preserves Mods/)
./install.sh -g srmi --uninstall
```

---

### Option 2: Manual Installation

1. **Back up DXVK in your Wine prefix**:
   ```bash
   cp "$WINEPREFIX/drive_c/windows/system32/d3d11.dll" \
      "$WINEPREFIX/drive_c/windows/system32/original_d3d11.dll"
   ```
   *(Make sure `original_d3d11.dll` is the genuine 64-bit DXVK DLL, **not** 3DMigoto itself.)*
2. **Install 3DMigoto `d3d11.dll` to prefix `system32`**:
   ```bash
   cp /path/to/3DMigoto-Linux/build/d3d11.dll \
      "$WINEPREFIX/drive_c/windows/system32/d3d11.dll"
   ```
   Do **not** copy `d3d11.dll` into the game directory.
3. **Place `d3dcompiler_47.dll` and importer assets in the game directory**:
   - Copy native 64-bit Microsoft `d3dcompiler_47.dll` into `<GAME_DIR>/d3dcompiler_47.dll`.
   - Clone the package matching your game and copy its `Core/`, `ShaderFixes/`, and `d3dx.ini` into `<GAME_DIR>/`:
     - Genshin Impact: `https://github.com/SilentNightSound/GIMI-Package` (`Core\GIMI\main.ini`, `target = GenshinImpact.exe`)
     - Honkai: Star Rail: `https://github.com/SpectrumQT/SRMI-Package` (`Core\SRMI\main.ini`, `target = StarRail.exe`)
     - Zenless Zone Zero: `https://github.com/leotorrez/ZZMI-Package` (`Core\ZZMI\main.ini`, `target = ZenlessZoneZero.exe`)
   - Create `<GAME_DIR>/Mods/` for your mods.

---

### Wine DLL Overrides

Configure your Wine/Proton launcher to load the native versions of `d3d11` and `d3dcompiler_47`:

```bash
WINEDLLOVERRIDES="d3d11=n,b;d3dcompiler_47=n,b"
```

Or configure via `winecfg`:
1. Run `WINEPREFIX=/path/to/prefix winecfg`.
2. Go to the **Libraries** tab.
3. Add `d3d11` and set to **Native then Builtin**.
4. Add `d3dcompiler_47` and set to **Native then Builtin**.

---

### Recommended `d3dx.ini` Settings

If configuring `d3dx.ini` manually (handled automatically by `install.sh`), ensure these settings are present:

```ini
[Loader]
; Set to your game executable: GenshinImpact.exe / StarRail.exe / ZenlessZoneZero.exe
target = GenshinImpact.exe

[Include]
; Match the game package: Core\GIMI\main.ini / Core\SRMI\main.ini / Core\ZZMI\main.ini
include = Core\GIMI\main.ini
include_recursive = Mods
exclude_recursive = DISABLED*

[System]
allow_check_interface = 1
allow_create_device = 1
allow_platform_update = 1
load_library_redirect = 2
skip_early_includes_load = 0
config_initialization_delay = -1

[Logging]
; Keep disabled for production / gameplay performance:
calls = 0
input = 0
debug = 0
unbuffered = 0
```

---

## Building from Source

### Prerequisites (Arch / Debian / Ubuntu / Fedora)

Install CMake, MinGW-w64, and build tools:

```bash
# Arch Linux
sudo pacman -S mingw-w64-gcc cmake make ninja

# Ubuntu / Debian
sudo apt install gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 cmake make ninja

# Fedora
sudo dnf install mingw64-gcc mingw64-gcc-c++ cmake make ninja-build
```

### Build Commands

```bash
# Clone the repository
git clone https://github.com/iprjkt/3DMigoto-Linux.git
cd 3DMigoto-Linux

# Create build directory
mkdir build && cd build

# Configure with MinGW toolchain
cmake .. -DCMAKE_TOOLCHAIN_FILE=../mingw-w64-x86_64.cmake -DCMAKE_BUILD_TYPE=Release

# Compile
cmake --build . -j$(nproc)
```

The output binary will be generated at:
```text
build/d3d11.dll
```

---

## Troubleshooting

- **Game launches to black screen / Epilepsy Warning screen then exits, or fails immediately:**
  - Verify that `WINEDLLOVERRIDES="d3d11=n,b;d3dcompiler_47=n,b"` is active.
  - Verify that `<prefix>/drive_c/windows/system32/original_d3d11.dll` is the genuine 64-bit DXVK DLL (not a copy of 3DMigoto's `d3d11.dll`).
  - Verify that native Microsoft `d3dcompiler_47.dll` is present in `<game_dir>/d3dcompiler_47.dll`.
- **Mods are not loading / character remains default:**
  - Verify `allow_platform_update = 1` and `skip_early_includes_load = 0` in `d3dx.ini`.
  - Verify `[Include]` points to the matching package `Core\<PKG>\main.ini` (`GIMI`, `SRMI`, or `ZZMI`).
  - Check `d3d11_log.txt` inside the game directory (temporarily set `calls = 1` and `unbuffered = 1` in `d3dx.ini` to diagnose).
- **F10 reload freezes or does not take effect:**
  - Ensure you are running the latest `d3d11.dll` build where synchronous `Beep()` delays, `SRWLOCK` synchronization, and compute shader override safety resets are applied.

---

## Credits & Acknowledgments

- **Bo3b, DarkStarSword, and Chiri**: Original authors and contributors of the [3DMigoto](https://github.com/bo3b/3Dmigoto) project.
- **SilentNightSound, leotorrez, SpectrumQT & XXMI/GIMI/SRMI/ZZMI Communities**: Package maintainers and model importer architectures.
- **Doitsujin & DXVK Contributors**: The Vulkan-based D3D11 implementation making high-performance DirectX 11 gaming on Linux possible.
- **WineHQ & Valve/CodeWeavers Proton Teams**: The foundation for Windows application execution on Linux.

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for details.
