cmake_minimum_required(VERSION 3.20)
project(3DMigoto LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Global compiler and linker settings for Win32 PE64 DLL under MinGW-w64
add_compile_options(
    -O2
    -g
    -m64
    -fpermissive
    -msse4.2
    -Wno-write-strings
    -Wno-attributes
)

add_link_options(
    -m64
    -static
    -static-libgcc
    -static-libstdc++
    -Wl,--enable-stdcall-fixup
)

add_compile_definitions(
    UNICODE
    _UNICODE
    CRC32C_STATIC=1
    PCRE2_STATIC
    PCRE2_CODE_UNIT_WIDTH=8
    _CRT_SECURE_CPP_OVERLOAD_STANDARD_NAMES=1
    _CRT_SECURE_CPP_OVERLOAD_STANDARD_NAMES_COUNT=1
    _WINDOWS
    _USRDLL
    MIGOTO_DX=11
    NDEBUG
)

# Include directories
include_directories(
    .
    DirectX11
    D3D_Shaders
    HLSLDecompiler
    BinaryDecompiler
    BinaryDecompiler/include
    BinaryDecompiler/internal_includes
    DirectXTK/Inc
    DirectXTK/Src
    external/DirectXMath/Inc
    external/minhook/include
    crc32c-hw-1.0.5/include
    pcre2
    pcre2-10.30/build64
    pcre2-10.30/src
)

# 1. MinHook library
set(MINHOOK_SOURCES
    external/minhook/src/buffer.c
    external/minhook/src/hook.c
    external/minhook/src/trampoline.c
    external/minhook/src/hde/hde64.c
    external/minhook/src/hde/hde32.c
)
add_library(minhook STATIC ${MINHOOK_SOURCES})
target_include_directories(minhook PRIVATE external/minhook/include)

# 2. PCRE2-8 library (built from bundled source)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/pcre2-10.30/src/pcre2_chartables.c.dist
    ${CMAKE_CURRENT_BINARY_DIR}/pcre2_chartables.c
    COPYONLY
)
set(PCRE2_SOURCES
    pcre2-10.30/src/pcre2_auto_possess.c
    pcre2-10.30/src/pcre2_compile.c
    pcre2-10.30/src/pcre2_config.c
    pcre2-10.30/src/pcre2_context.c
    pcre2-10.30/src/pcre2_convert.c
    pcre2-10.30/src/pcre2_dfa_match.c
    pcre2-10.30/src/pcre2_error.c
    pcre2-10.30/src/pcre2_find_bracket.c
    pcre2-10.30/src/pcre2_jit_compile.c
    pcre2-10.30/src/pcre2_maketables.c
    pcre2-10.30/src/pcre2_match.c
    pcre2-10.30/src/pcre2_match_data.c
    pcre2-10.30/src/pcre2_newline.c
    pcre2-10.30/src/pcre2_ord2utf.c
    pcre2-10.30/src/pcre2_pattern_info.c
    pcre2-10.30/src/pcre2_serialize.c
    pcre2-10.30/src/pcre2_string_utils.c
    pcre2-10.30/src/pcre2_study.c
    pcre2-10.30/src/pcre2_substitute.c
    pcre2-10.30/src/pcre2_substring.c
    pcre2-10.30/src/pcre2_tables.c
    pcre2-10.30/src/pcre2_ucd.c
    pcre2-10.30/src/pcre2_valid_utf.c
    pcre2-10.30/src/pcre2_xclass.c
    ${CMAKE_CURRENT_BINARY_DIR}/pcre2_chartables.c
)
add_library(pcre2-8 STATIC ${PCRE2_SOURCES})
target_compile_definitions(pcre2-8 PRIVATE
    HAVE_CONFIG_H
    PCRE2_CODE_UNIT_WIDTH=8
    PCRE2_STATIC
)
target_include_directories(pcre2-8 PRIVATE
    pcre2-10.30/build64
    pcre2-10.30/src
)

# 3. DirectXTK (subset required by 3DMigoto)
set(DIRECTXTK_SOURCES
    DirectXTK/Src/DDSTextureLoader.cpp
    DirectXTK/Src/ScreenGrab.cpp
    DirectXTK/Src/SpriteBatch.cpp
    DirectXTK/Src/SpriteFont.cpp
    DirectXTK/Src/CommonStates.cpp
    DirectXTK/Src/VertexTypes.cpp
    DirectXTK/Src/BinaryReader.cpp
    DirectXTK/Src/PrimitiveBatch.cpp
    DirectXTK/Src/BasicEffect.cpp
    DirectXTK/Src/EffectCommon.cpp
    DirectXTK/Src/WICTextureLoader.cpp
)
add_library(directxtk STATIC ${DIRECTXTK_SOURCES})

# 4. BinaryDecompiler
set(BINARY_DECOMPILER_SOURCES
    BinaryDecompiler/decode.cpp
    BinaryDecompiler/decodeDX9.cpp
    BinaryDecompiler/reflect.cpp
)
add_library(binary_decompiler STATIC ${BINARY_DECOMPILER_SOURCES})

# 5. D3D_Shaders
set(D3D_SHADERS_SOURCES
    D3D_Shaders/Assembler.cpp
    D3D_Shaders/Shaders.cpp
    D3D_Shaders/SignatureParser.cpp
)
add_library(d3d_shaders STATIC ${D3D_SHADERS_SOURCES})

# 6. HLSLDecompiler
set(HLSL_DECOMPILER_SOURCES
    HLSLDecompiler/DecompileHLSL.cpp
)
add_library(hlsl_decompiler STATIC ${HLSL_DECOMPILER_SOURCES})

# 7. Core Proxy DLL: d3d11.dll
set(D3D11_SOURCES
    DirectX11/CommandList.cpp
    DirectX11/cursor.cpp
    DirectX11/D3D11Wrapper.cpp
    DirectX11/DLLMainHook.cpp
    DirectX11/FrameAnalysis.cpp
    DirectX11/HackerContext.cpp
    DirectX11/HackerDevice.cpp
    DirectX11/HackerDXGI.cpp
    DirectX11/HookedContext.cpp
    DirectX11/HookedDevice.cpp
    DirectX11/HookedDXGI.cpp
    DirectX11/Hunting.cpp
    DirectX11/IniHandler.cpp
    DirectX11/input.cpp
    DirectX11/lock.cpp
    DirectX11/nvprofile.cpp
    DirectX11/Overlay.cpp
    DirectX11/Override.cpp
    DirectX11/profiling.cpp
    DirectX11/ResourceHash.cpp
    DirectX11/ShaderRegex.cpp
    Nektra/NktHookLib.cpp
    crc32c-hw-1.0.5/src/crc32c.cpp
    iid.cpp
    ini_parser_lite.cpp
    util.cpp
    DirectX11/HookAddresses.c
    DirectX11/path_resolver.cpp
    DirectX11/d3d11Wrapper.def
)

add_library(3DMigoto SHARED ${D3D11_SOURCES})

set_target_properties(3DMigoto PROPERTIES
    PREFIX ""
    OUTPUT_NAME "d3d11"
    SUFFIX ".dll"
)

target_link_libraries(3DMigoto PRIVATE
    minhook
    pcre2-8
    directxtk
    -Wl,--start-group
    hlsl_decompiler
    binary_decompiler
    d3d_shaders
    -Wl,--end-group
    dxgi
    d3dcompiler
    xinput9_1_0
    shlwapi
    dbghelp
    windowscodecs
    ole32
    uuid
)
