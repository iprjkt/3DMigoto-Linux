# 3DMigoto for Linux

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](#building-from-source)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Wine%20%7C%20Proton-orange)](#requirements)
[![DirectX](https://img.shields.io/badge/DirectX-11.0%20%7C%2011.1-blue)](#key-technical-fixes)
[![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey)](LICENSE)

A specialized 64-bit fork of **3DMigoto** engineered natively for **Linux**, **Wine**, **Proton**, and **DXVK**. 

This fork addresses and eliminates the longstanding architectural incompatibilities that previously prevented 3DMigoto and mod loaders built on top of it (such as **GIMI** and **XXMI**) from running under Wine/Proton when paired with Unity-based games (e.g., *Genshin Impact*).

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
- [Requirements](#requirements)
- [Setup & Installation](#setup--installation)
  - [Wine DLL Overrides](#wine-dll-overrides)
  - [Deployment Options](#deployment-options)
  - [Recommended `d3dx.ini` Settings](#recommended-d3dxini-settings)
- [Building from Source](#building-from-source)
- [Troubleshooting](#troubleshooting)
- [Credits & Acknowledgments](#credits--acknowledgments)

---

## Overview

Stock 3DMigoto was originally authored for native Windows and MSVC. When deployed as a proxy wrapper under Wine or Proton, several fundamental assumptions break down:

1. **Module location vs Process location**: Wine prefixes often install or symlink `d3d11.dll` inside `C:\windows\system32\`. Stock 3DMigoto resolved relative paths (like `Mods/` and `ShaderFixes/`) from the DLL module handle rather than the running executable, causing assets to be searched under `C:\windows\system32\Mods/`.
2. **COM identity leakage**: Unity queries `IUnknown` on graphics interfaces. Stock 3DMigoto forwarded `IUnknown` queries to DXVK's underlying `mOrigDevice1` / `mOrigContext1`, leaking raw DXVK pointers and allowing the game engine to bypass 3DMigoto's hooks entirely.
3. **Unity Graphics Jobs (Multithreading)**: Unity utilizes multithreaded rendering jobs that execute draw calls via **Deferred Contexts** (`CreateDeferredContext` / `CreateDeferredContext1`) and command lists. Without wrapping deferred contexts, character meshes and UI overrides never pass through 3DMigoto's draw call hooks.
4. **Wine hotpatch and timer semantics**: Synchronous Win32 calls like `Beep()` execute blocking thread sleeps in Wine, freezing the game render thread for seconds during shader reload.

This repository provides a complete, natively compilable (via MinGW-w64 & CMake) build of 3DMigoto that resolves all of these issues while maintaining peak rendering performance with zero hot-path overhead.

---

## Key Technical Fixes

### 1. COM Identity & IUnknown Pointer Preservation
- **Problem**: When Unity queries `pDevice->QueryInterface(IID_IUnknown, &pUnk)`, stock 3DMigoto fell through to the underlying DXVK device. Unity would subsequently query `ID3D11DeviceContext` from that `IUnknown`, receiving raw DXVK pointers and completely bypassing 3DMigoto.
- **Fix**: Patched [`HackerDevice::QueryInterface`](file:///home/fxxyz73/3DMigoto-Linux/DirectX11/HackerDevice.cpp) and [`HackerContext::QueryInterface`](file:///home/fxxyz73/3DMigoto-Linux/DirectX11/HackerContext.cpp) to strictly preserve COM identity: queries for `__uuidof(IUnknown)` now return `this` (with `AddRef()`), guaranteeing that the game cannot escape the wrapper chain.

### 2. Deferred Context & Command List Interception
- **Problem**: Unity renders character meshes, UI elements, and effects across worker threads using deferred contexts. Stock 3DMigoto either returned unwrapped contexts or leaked references on query upconversion.
- **Fix**: 
  - Implemented full wrapping in [`HackerDevice::CreateDeferredContext`](file:///home/fxxyz73/3DMigoto-Linux/DirectX11/HackerDevice.cpp) and [`CreateDeferredContext1`](file:///home/fxxyz73/3DMigoto-Linux/DirectX11/HackerDevice.cpp), binding 3DMigoto resources to each worker context and cleanly managing COM reference lifecycles.
  - Added robust command list tracking in [`HackerContext::ExecuteCommandList`](file:///home/fxxyz73/3DMigoto-Linux/DirectX11/HackerContext.cpp) and [`HackerContext::FinishCommandList`](file:///home/fxxyz73/3DMigoto-Linux/DirectX11/HackerContext.cpp).

### 3. Modern Interface Fallback (ID3D11Device2+)
- **Problem**: Unity checks whether the D3D11 runtime supports newer interfaces like `ID3D11Device2` through `ID3D11Device5` and `ID3D11DeviceContext2` through `ID3D11DeviceContext4`. If DXVK supports them, Unity adopts those pointers, again bypassing the D3D11.1 wrapper.
- **Fix**: Both `HackerDevice::QueryInterface` and `HackerContext::QueryInterface` explicitly return `E_NOINTERFACE` for `ID3D11Device2+` and `ID3D11DeviceContext2+`, forcing Unity to cleanly fall back to the wrapped `ID3D11Device1` / `ID3D11DeviceContext1` pipeline.

### 4. Host Executable Base Directory & Linux Path Resolution
- **Problem**: When `d3d11.dll` is installed in Wine's `system32` (or symlinked), `GetModuleFileNameW(hinstDLL, ...)` points to `C:\windows\system32\`. Furthermore, Linux filesystems (ext4/btrfs) are case-sensitive, causing case mismatches in mod INIs and textures to fail.
- **Fix**:
  - Implemented `GetMigotoBaseDirectory()` to anchor all path resolution directly to the host executable (`GetModuleFileNameW(NULL, ...)` / `GenshinImpact.exe`).
  - Implemented an in-memory, thread-safe, case-insensitive path resolver (`ResolvePathCaseInsensitive`) backed by MinHook hooks on `CreateFileW` / `CreateFileA` so paths like `Mods/Character/texture.dds` resolve accurately regardless of disk casing.

### 5. Wine PE Loader & Hotpatch Stub Compatibility
- **Problem**: Wine's PE loader hotpatch stubs on `kernel32.dll` (`LoadLibraryExW`) caused trampoline hooking to return errors during `DLL_PROCESS_ATTACH`, causing `DllMain` to return `FALSE` and aborting process launch.
- **Fix**: Hardened `DirectX11/DLLMainHook.cpp` so non-critical hooking failures degrade gracefully without aborting DLL attachment.

### 6. F10 Reload Stability & Shader State Integrity
- **Problem**: 
  - In Wine, `Beep(frequency, duration)` executes a synchronous `usleep()`. When compiling complex mod shaders that produce compilation warnings or errors, multiple beep calls froze the render thread for 5–10 seconds inside `G->mCriticalSection`, triggering OS "Application Not Responding" dialogs.
  - In `CustomShader::compile`, `cs_override = true` was set before compilation. If Wine's shader compiler aborted on complex HLSL constructs (e.g., non-direct structured resource stores), `cs_override` remained `true` with a `NULL` shader pointer, causing crashes on subsequent compute dispatches.
- **Fix**:
  - Removed synchronous `Beep()` calls during config reload.
  - Automatically reset `vs_override`, `ps_override`, `cs_override`, etc., to `false` whenever compilation or shader creation fails, maintaining pipeline state integrity.

---

## Requirements

1. **Operating System**: Linux with Wine 8.0+ or Proton 8.0+ (Proton-GE / Wine-GE recommended).
2. **Graphics API**: DXVK (v2.0 or newer recommended).
3. **Native Microsoft `d3dcompiler_47.dll`** *(Crucial)*:
   > [!IMPORTANT]
   > Wine's built-in `d3dcompiler_47.dll` implementation lacks support for structured resource stores, advanced HLSL bytecode assembly, and certain shader regex disassemblies. You **must** provide the native 64-bit Microsoft `d3dcompiler_47.dll` (from Windows 10/11 or via `winetricks d3dcompiler_47`).

---

## Setup & Installation

### Wine DLL Overrides

Configure your Wine prefix to load the native versions of `d3d11` and `d3dcompiler_47`.

In your launcher's environment variables or launch script:

```bash
WINEDLLOVERRIDES="d3d11=n,b;d3dcompiler_47=n,b"
```

Or configure via `winecfg`:
1. Run `WINEPREFIX=/path/to/prefix winecfg`.
2. Go to the **Libraries** tab.
3. Add `d3d11` and set to **Native then Builtin**.
4. Add `d3dcompiler_47` and set to **Native then Builtin**.

### Deployment Options

#### Option A: Game Directory (Recommended for Launchers)
1. Copy the compiled `d3d11.dll` into the game directory containing the main executable (e.g., alongside `GenshinImpact.exe`).
2. Place the native 64-bit `d3dcompiler_47.dll` in the same directory.
3. Place `d3dx.ini`, `Mods/`, and `ShaderFixes/` in the same directory.

#### Option B: Prefix System32 Symlink (For System-wide or Launcher Integration)
If using a custom launcher that enforces system32 placement:
```bash
ln -sf /path/to/3DMigoto-Linux/build/d3d11.dll \
  "$WINEPREFIX/drive_c/windows/system32/d3d11.dll"
```
Place the native `d3dcompiler_47.dll` in `$WINEPREFIX/drive_c/windows/system32/d3dcompiler_47.dll`.

### Recommended `d3dx.ini` Settings

Ensure the following settings are present in your `d3dx.ini`:

```ini
[System]
allow_check_interface = 1
allow_create_device = 1
allow_platform_update = 1
load_library_redirect = 2

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
```
build/d3d11.dll
```

---

## Troubleshooting

- **Game launches to black screen / Epilepsy Warning screen then exits:**
  - Verify that `WINEDLLOVERRIDES="d3d11=n,b;d3dcompiler_47=n,b"` is active.
  - Verify that native Microsoft `d3dcompiler_47.dll` is present in the game directory or Wine prefix.
- **Mods are not loading / character remains default:**
  - Verify `allow_platform_update = 1` in `d3dx.ini`.
  - Check `d3d11_log.txt` (temporarily set `calls = 1` and `unbuffered = 1` in `d3dx.ini` to diagnose). Verify that your mod INI files are being discovered and registered.
- **F10 reload freezes or does not take effect:**
  - Ensure you are running this custom build of `d3d11.dll` where synchronous `Beep()` delays and compute shader override safety resets are applied.

---

## Credits & Acknowledgments

- **Bo3b, DarkStarSword, and Chiri**: Original authors and contributors of the [3DMigoto](https://github.com/bo3b/3Dmigoto) project.
- **SilentNightSound & GIMI Community**: Contributors behind the Genshin Impact Model Importer platform.
- **SpectrumQT & XXMI Community**: Architecture and multi-game mod loading tooling.
- **Doitsujin & DXVK Contributors**: The Vulkan-based D3D11 implementation making high-performance DirectX 11 gaming on Linux possible.
- **WineHQ & Valve/CodeWeavers Proton Teams**: The foundation for Windows application execution on Linux.

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for details.
