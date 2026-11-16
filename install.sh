#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# 3DMigoto-Linux Multi-Game Installer (GIMI / SRMI / ZZMI / Custom)
# Reads paths from install.conf (or CLI/interactive), clones importer package
# (Core, ShaderFixes, d3dx.ini), deploys d3dcompiler_47.dll to the game dir,
# and deploys 3DMigoto d3d11.dll + DXVK original_d3d11.dll to prefix system32.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR=""

CONFIG_FILE="$SCRIPT_DIR/install.conf"
GAME=""
GAME_DIR=""
WINE_PREFIX=""
DXVK_PATH=""
CUSTOM_REPO=""
TARGET_EXE=""
PKG_CODE=""

CLI_GAME_DIR=""
CLI_PREFIX=""
CLI_DXVK=""
CLI_REPO=""
CLI_EXE=""
CLI_KEEP_INI=""
CLI_UPDATE_DLL_ONLY=""

CONF_D3D11_PATH=""
CONF_D3DCOMPILER_PATH=""

KEEP_INI=0
UPDATE_DLL_ONLY=0
UNINSTALL=0
AUTO_YES=0
RUN_ALL=0
SHOW_STATUS=0
SAVE_CONFIG=0

# Colors (only if stdout is tty)
if [ -t 1 ]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

info()  { printf "${CYAN}[INFO]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
die()   { err "$*"; exit 1; }

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

usage() {
    cat <<EOF
${BOLD}3DMigoto-Linux Multi-Game Installer${NC}

Deployment layout:
  - <prefix>/drive_c/windows/system32/  <- d3d11.dll (3DMigoto) & original_d3d11.dll (DXVK)
  - <game_dir>/                         <- d3dcompiler_47.dll, Core/, ShaderFixes/, Mods/, d3dx.ini

Usage:
  $(basename "$0") [OPTIONS]

Options:
  -c, --config <FILE>                  Path to config file (default: ./install.conf)
  -g, --game <gimi|srmi|zzmi|custom|SECTION>
                                       Target game preset or section name from install.conf
  -d, --game-dir <PATH>                Game executable directory (e.g. folder with StarRail.exe)
  -p, --prefix <WINEPREFIX>            Wine/Proton prefix directory (contains drive_c)
  -x, --dxvk <PATH>                    Explicit path to DXVK 64-bit d3d11.dll
  -r, --repo <URL>                     Custom git repo URL (used with custom or override)
  -e, --exe <NAME.exe>                 Target executable name
  --all                                Process all enabled=1 game sections in install.conf
  --status                             Show configured paths and DLL installation status
  --save                               Save used game_dir/prefix/dxvk back into install.conf
  --update-dll-only                    Only update d3d11.dll (prefix) & d3dcompiler_47.dll (game_dir)
  --keep-ini                           Do not overwrite existing d3dx.ini in game_dir
  --uninstall                          Remove 3DMigoto DLLs from prefix & d3dcompiler_47.dll from game_dir
  -y, --yes                            Non-interactive mode (accept defaults/config values)
  -h, --help                           Show this help message

Examples:
  # Interactive mode (reads defaults from install.conf if configured):
  ./$(basename "$0")

  # Install/update all games with enabled = 1 in install.conf:
  ./$(basename "$0") --all -y

  # Update only DLLs for all enabled games in install.conf:
  ./$(basename "$0") --all --update-dll-only -y

  # Check status of configured paths in install.conf:
  ./$(basename "$0") --status

  # Install SRMI via CLI and save paths into install.conf:
  ./$(basename "$0") -g srmi -d "/path/to/Star Rail/Games" -p "/path/to/prefix" --save
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -c|--config)
                CONFIG_FILE="${2:-}"
                shift 2
                ;;
            -g|--game)
                GAME="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"
                shift 2
                ;;
            -d|--game-dir)
                CLI_GAME_DIR="${2:-}"
                shift 2
                ;;
            -p|--prefix)
                CLI_PREFIX="${2:-}"
                shift 2
                ;;
            -x|--dxvk)
                CLI_DXVK="${2:-}"
                shift 2
                ;;
            -r|--repo)
                CLI_REPO="${2:-}"
                shift 2
                ;;
            -e|--exe)
                CLI_EXE="${2:-}"
                shift 2
                ;;
            --all)
                RUN_ALL=1
                shift
                ;;
            --status)
                SHOW_STATUS=1
                shift
                ;;
            --save)
                SAVE_CONFIG=1
                shift
                ;;
            --update-dll-only)
                CLI_UPDATE_DLL_ONLY=1
                shift
                ;;
            --keep-ini)
                CLI_KEEP_INI=1
                shift
                ;;
            --uninstall)
                UNINSTALL=1
                shift
                ;;
            -y|--yes)
                AUTO_YES=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1 (use --help for usage)"
                ;;
        esac
    done
}

trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

strip_quotes() {
    local s="$1"
    if [[ "$s" == \"*\" ]] && [ "${#s}" -ge 2 ]; then
        s="${s:1:${#s}-2}"
    elif [[ "$s" == \'*\' ]] && [ "${#s}" -ge 2 ]; then
        s="${s:1:${#s}-2}"
    fi
    printf '%s' "$s"
}

expand_path() {
    local p
    p="$(strip_quotes "$(trim_ws "$1")")"
    if [[ "$p" == "~/"* ]]; then
        p="$HOME/${p#~/}"
    elif [ "$p" = "~" ]; then
        p="$HOME"
    fi
    p="${p//\$HOME/$HOME}"
    printf '%s' "$p"
}

# Normalize Steam Proton compatdata dir (append /pfx if drive_c lives there)
normalize_prefix_path() {
    local p="$1"
    p="${p%/}"
    if [ -n "$p" ] && [ ! -d "$p/drive_c/windows/system32" ] && [ -d "$p/pfx/drive_c/windows/system32" ]; then
        p="$p/pfx"
    fi
    printf '%s' "$p"
}

conf_get() {
    local conf_file="$1"
    local target_sec="$2"
    local target_key="$3"
    [ -f "$conf_file" ] || return 0

    local cur_sec="" line key val
    local target_sec_l target_key_l
    target_sec_l="$(printf '%s' "$target_sec" | tr '[:upper:]' '[:lower:]')"
    target_key_l="$(printf '%s' "$target_key" | tr '[:upper:]' '[:lower:]')"

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="$(trim_ws "$line")"
        [[ -z "$line" || "$line" == \#* || "$line" == \;* ]] && continue

        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            cur_sec="$(trim_ws "${BASH_REMATCH[1]}")"
            cur_sec="$(printf '%s' "$cur_sec" | tr '[:upper:]' '[:lower:]')"
            continue
        fi

        if [ "$cur_sec" = "$target_sec_l" ] && [[ "$line" == *=* ]]; then
            key="$(trim_ws "${line%%=*}")"
            key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
            if [ "$key" = "$target_key_l" ]; then
                val="${line#*=}"
                expand_path "$val"
                return 0
            fi
        fi
    done < "$conf_file"
}

conf_list_game_sections() {
    local conf_file="$1"
    [ -f "$conf_file" ] || return 0
    local line sec sec_l
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="$(trim_ws "$line")"
        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            sec="$(trim_ws "${BASH_REMATCH[1]}")"
            sec_l="$(printf '%s' "$sec" | tr '[:upper:]' '[:lower:]')"
            if [ "$sec_l" != "global" ]; then
                printf '%s\n' "$sec"
            fi
        fi
    done < "$conf_file"
}

conf_set() {
    local conf_file="$1"
    local target_sec="$2"
    local target_key="$3"
    local new_val="$4"

    [ -f "$conf_file" ] || return 0

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$conf_file" "$target_sec" "$target_key" "$new_val" <<'PYEOF'
import sys, re

conf_file, target_sec, target_key, new_val = sys.argv[1:5]
with open(conf_file, "r", encoding="utf-8", errors="replace") as f:
    lines = f.read().splitlines()

sec_re = re.compile(r'^\s*\[([^\]]+)\]\s*(?:[#;].*)?$')
cur_sec = None
in_target = False
seen_section = False
updated = False
out = []

for line in lines:
    m = sec_re.match(line)
    if m:
        if in_target and not updated:
            out.append(f"{target_key} = {new_val}")
            updated = True
        cur_sec = m.group(1).strip()
        in_target = (cur_sec.lower() == target_sec.lower())
        if in_target:
            seen_section = True
        out.append(line)
        continue

    stripped = line.strip()
    if in_target and stripped and not stripped.startswith("#") and not stripped.startswith(";") and "=" in line:
        k = line.split("=", 1)[0].strip()
        if k.lower() == target_key.lower():
            out.append(f"{k} = {new_val}")
            updated = True
            continue

    out.append(line)

if in_target and not updated:
    out.append(f"{target_key} = {new_val}")
    updated = True

if not seen_section:
    out += ["", f"[{target_sec}]", f"{target_key} = {new_val}"]

with open(conf_file, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
PYEOF
    else
        warn "python3 not found; skipping automatic save to $conf_file"
    fi
}

load_global_config() {
    CONF_D3D11_PATH=""
    CONF_D3DCOMPILER_PATH=""
    GLOBAL_DEFAULT_PREFIX=""
    GLOBAL_DEFAULT_DXVK=""
    GLOBAL_KEEP_INI="0"
    GLOBAL_UPDATE_DLL_ONLY="0"

    if [ -f "$CONFIG_FILE" ]; then
        CONF_D3D11_PATH="$(conf_get "$CONFIG_FILE" "Global" "d3d11_path")"
        CONF_D3DCOMPILER_PATH="$(conf_get "$CONFIG_FILE" "Global" "d3dcompiler_path")"
        GLOBAL_DEFAULT_PREFIX="$(conf_get "$CONFIG_FILE" "Global" "default_prefix")"
        GLOBAL_DEFAULT_DXVK="$(conf_get "$CONFIG_FILE" "Global" "default_dxvk")"
        GLOBAL_KEEP_INI="$(conf_get "$CONFIG_FILE" "Global" "keep_ini")"
        GLOBAL_UPDATE_DLL_ONLY="$(conf_get "$CONFIG_FILE" "Global" "update_dll_only")"
    fi

    KEEP_INI="${CLI_KEEP_INI:-${GLOBAL_KEEP_INI:-0}}"
    UPDATE_DLL_ONLY="${CLI_UPDATE_DLL_ONLY:-${GLOBAL_UPDATE_DLL_ONLY:-0}}"
}

# Check if a DLL file is 64-bit PE
is_pe64_dll() {
    local file="$1"
    [ -f "$file" ] || return 1
    if command -v file >/dev/null 2>&1; then
        file -b "$file" | grep -q -E "PE32\+|x86-64"
    else
        local sz
        sz=$(wc -c < "$file" 2>/dev/null || echo 0)
        [ "$sz" -gt 400000 ]
    fi
}

# Check if a DLL is our 3DMigoto build
is_3dmigoto_dll() {
    local file="$1"
    [ -f "$file" ] || return 1
    grep -q -a -E "HackerDevice|3DMigoto" "$file" 2>/dev/null
}

# Check if a DLL is valid 64-bit DXVK (and NOT 3DMigoto!)
is_dxvk_dll() {
    local file="$1"
    [ -f "$file" ] || return 1
    is_pe64_dll "$file" || return 1
    if is_3dmigoto_dll "$file"; then
        return 1
    fi
    if grep -q -a -i "dxvk" "$file" 2>/dev/null; then
        return 0
    fi
    local sz
    sz=$(wc -c < "$file" 2>/dev/null || echo 0)
    [ "$sz" -gt 1000000 ]
}

locate_migoto_binaries() {
    D3D11_SRC=""
    D3DCOMPILER_SRC=""

    if [ -n "$CONF_D3D11_PATH" ] && [ -f "$CONF_D3D11_PATH" ] && is_3dmigoto_dll "$CONF_D3D11_PATH"; then
        D3D11_SRC="$CONF_D3D11_PATH"
    elif [ -f "$SCRIPT_DIR/d3d11.dll" ] && is_3dmigoto_dll "$SCRIPT_DIR/d3d11.dll"; then
        D3D11_SRC="$SCRIPT_DIR/d3d11.dll"
    elif [ -f "$SCRIPT_DIR/build/d3d11.dll" ] && is_3dmigoto_dll "$SCRIPT_DIR/build/d3d11.dll"; then
        D3D11_SRC="$SCRIPT_DIR/build/d3d11.dll"
    fi

    if [ -z "$D3D11_SRC" ]; then
        die "Could not find 3DMigoto d3d11.dll (checked install.conf d3d11_path, '$SCRIPT_DIR', and '$SCRIPT_DIR/build')."
    fi

    if [ -n "$CONF_D3DCOMPILER_PATH" ] && [ -f "$CONF_D3DCOMPILER_PATH" ]; then
        D3DCOMPILER_SRC="$CONF_D3DCOMPILER_PATH"
    elif [ -f "$SCRIPT_DIR/d3dcompiler_47.dll" ]; then
        D3DCOMPILER_SRC="$SCRIPT_DIR/d3dcompiler_47.dll"
    elif [ -f "$SCRIPT_DIR/Dependencies/d3dcompiler_47.dll" ]; then
        D3DCOMPILER_SRC="$SCRIPT_DIR/Dependencies/d3dcompiler_47.dll"
    fi
}

reset_game_vars() {
    GAME_DIR=""
    WINE_PREFIX=""
    DXVK_PATH=""
    REPO_URL=""
    TARGET_EXE=""
    PKG_CODE=""
    CUSTOM_REPO=""
}

configure_game_preset() {
    reset_game_vars

    if [ -z "$GAME" ] && [ "$UPDATE_DLL_ONLY" -eq 0 ] && [ "$UNINSTALL" -eq 0 ]; then
        printf "\n${BOLD}Select target game / importer package:${NC}\n"
        printf "  1) GIMI  - Genshin Impact     (SilentNightSound/GIMI-Package)\n"
        printf "  2) SRMI  - Honkai: Star Rail  (SpectrumQT/SRMI-Package)\n"
        printf "  3) ZZMI  - Zenless Zone Zero  (leotorrez/ZZMI-Package)\n"
        printf "  4) Custom repo URL\n"
        read -rp "Choice [1-4]: " choice
        case "$choice" in
            1) GAME="gimi" ;;
            2) GAME="srmi" ;;
            3) GAME="zzmi" ;;
            4) GAME="custom" ;;
            *) die "Invalid selection: $choice" ;;
        esac
    fi

    local conf_sec=""
    case "$GAME" in
        gimi|genshin|gi)
            conf_sec="GIMI"
            PKG_CODE="GIMI"
            REPO_URL="https://github.com/SilentNightSound/GIMI-Package.git"
            TARGET_EXE="GenshinImpact.exe"
            ;;
        srmi|hsr|starrail)
            conf_sec="SRMI"
            PKG_CODE="SRMI"
            REPO_URL="https://github.com/SpectrumQT/SRMI-Package.git"
            TARGET_EXE="StarRail.exe"
            ;;
        zzmi|zzz|zenless)
            conf_sec="ZZMI"
            PKG_CODE="ZZMI"
            REPO_URL="https://github.com/leotorrez/ZZMI-Package.git"
            TARGET_EXE="ZenlessZoneZero.exe"
            ;;
        custom)
            conf_sec="Custom"
            ;;
        "")
            conf_sec=""
            ;;
        *)
            # Allow arbitrary section name from install.conf (e.g. -g HI3)
            conf_sec="$GAME"
            PKG_CODE="$(printf '%s' "$GAME" | tr '[:lower:]' '[:upper:]')"
            ;;
    esac

    local c_dir="" c_prefix="" c_dxvk="" c_repo="" c_exe="" c_keep=""
    if [ -n "$conf_sec" ] && [ -f "$CONFIG_FILE" ]; then
        c_dir="$(conf_get "$CONFIG_FILE" "$conf_sec" "game_dir")"
        c_prefix="$(conf_get "$CONFIG_FILE" "$conf_sec" "prefix")"
        c_dxvk="$(conf_get "$CONFIG_FILE" "$conf_sec" "dxvk")"
        c_repo="$(conf_get "$CONFIG_FILE" "$conf_sec" "repo")"
        c_exe="$(conf_get "$CONFIG_FILE" "$conf_sec" "exe")"
        c_keep="$(conf_get "$CONFIG_FILE" "$conf_sec" "keep_ini")"
    fi

    GAME_DIR="${CLI_GAME_DIR:-$c_dir}"
    WINE_PREFIX="${CLI_PREFIX:-${c_prefix:-$GLOBAL_DEFAULT_PREFIX}}"
    DXVK_PATH="${CLI_DXVK:-${c_dxvk:-$GLOBAL_DEFAULT_DXVK}}"
    REPO_URL="${CLI_REPO:-${c_repo:-$REPO_URL}}"
    TARGET_EXE="${CLI_EXE:-${c_exe:-$TARGET_EXE}}"
    if [ -z "$CLI_KEEP_INI" ] && [ -n "$c_keep" ]; then
        KEEP_INI="$c_keep"
    fi

    if [ "$GAME" = "custom" ] || { [ -n "$conf_sec" ] && [ -z "$REPO_URL" ] && [ "$UPDATE_DLL_ONLY" -eq 0 ] && [ "$UNINSTALL" -eq 0 ]; }; then
        if [ -z "$REPO_URL" ]; then
            read -rp "Enter Git repository URL (or GitHub owner/repo): " REPO_URL
        fi
        if [[ "$REPO_URL" != http* ]] && [[ "$REPO_URL" != git@* ]] && [ ! -d "$REPO_URL" ]; then
            REPO_URL="https://github.com/${REPO_URL%.git}.git"
        fi
        if [ -z "$PKG_CODE" ]; then
            read -rp "Enter Core package folder name (e.g. GIMI, SRMI, ZZMI) [leave empty to auto-detect]: " PKG_CODE
        fi
        if [ -z "$TARGET_EXE" ]; then
            read -rp "Enter target game executable (e.g. StarRail.exe): " TARGET_EXE
        fi
    fi

    CONF_SECTION_NAME="$conf_sec"
}

prompt_game_dir() {
    local default_dir="$GAME_DIR"
    if [ -z "$GAME_DIR" ]; then
        printf "\n"
        read -rp "Enter target game directory (folder containing ${TARGET_EXE:-the game .exe}): " GAME_DIR
    elif [ "$AUTO_YES" -eq 0 ] && [ "$RUN_ALL" -eq 0 ] && [ -z "$CLI_GAME_DIR" ]; then
        printf "\n"
        read -rp "Game directory [$default_dir]: " input_dir
        if [ -n "$input_dir" ]; then
            GAME_DIR="$input_dir"
        fi
    fi

    GAME_DIR="$(expand_path "$GAME_DIR")"
    GAME_DIR="${GAME_DIR%/}"

    [ -n "$GAME_DIR" ] || die "Game directory cannot be empty."
    [ -d "$GAME_DIR" ] || die "Game directory does not exist: '$GAME_DIR'"

    if [ -n "$TARGET_EXE" ] && [ ! -f "$GAME_DIR/$TARGET_EXE" ]; then
        warn "'$TARGET_EXE' was not found directly inside '$GAME_DIR'."
        if [ "$AUTO_YES" -eq 0 ]; then
            read -rp "Continue anyway? [y/N]: " ans
            case "$ans" in
                [yY]|[yY][eE][sS]) ;;
                *) exit 1 ;;
            esac
        fi
    fi
}

prompt_wine_prefix() {
    local default_prefix="$WINE_PREFIX"
    if [ -z "$WINE_PREFIX" ]; then
        if [ "$AUTO_YES" -eq 1 ]; then
            die "Wine/Proton prefix directory is required to install d3d11.dll into system32. Pass --prefix or set it in install.conf."
        fi
        printf "\n"
        read -rp "Enter Wine/Proton prefix directory (folder containing drive_c): " WINE_PREFIX
    elif [ "$AUTO_YES" -eq 0 ] && [ "$RUN_ALL" -eq 0 ] && [ -z "$CLI_PREFIX" ]; then
        read -rp "Wine/Proton prefix directory [$default_prefix]: " input_prefix
        if [ -n "$input_prefix" ]; then
            WINE_PREFIX="$input_prefix"
        fi
    fi

    WINE_PREFIX="$(expand_path "$WINE_PREFIX")"
    WINE_PREFIX="$(normalize_prefix_path "$WINE_PREFIX")"

    [ -n "$WINE_PREFIX" ] || die "Wine/Proton prefix directory cannot be empty."
    [ -d "$WINE_PREFIX/drive_c/windows/system32" ] || die "Invalid Wine/Proton prefix (missing drive_c/windows/system32): '$WINE_PREFIX'"
}

find_dxvk_candidate() {
    local sys32="$WINE_PREFIX/drive_c/windows/system32"
    local candidates=()
    local c

    if [ -n "$DXVK_PATH" ]; then
        if is_dxvk_dll "$DXVK_PATH"; then
            printf '%s' "$DXVK_PATH"
            return 0
        else
            die "Provided DXVK path is not a valid 64-bit DXVK DLL: '$DXVK_PATH'"
        fi
    fi

    # Check prefix system32 first before we overwrite d3d11.dll
    for c in \
        "$sys32/original_d3d11.dll" \
        "$sys32/d3d11.dll"
    do
        if is_dxvk_dll "$c"; then
            printf '%s' "$c"
            return 0
        fi
    done

    # Fallback: check game directory for existing DXVK backups
    for c in \
        "$GAME_DIR/original_d3d11.dll" \
        "$GAME_DIR/dxvk_d3d11.dll" \
        "$GAME_DIR/d3d11.dll"
    do
        if is_dxvk_dll "$c"; then
            printf '%s' "$c"
            return 0
        fi
    done

    # Fallback: scan common Linux launcher DXVK caches
    while IFS= read -r c; do
        if is_dxvk_dll "$c"; then
            candidates+=("$c")
        fi
    done < <(find "$HOME/.local/share" -maxdepth 5 -type f -name "d3d11.dll" \( -path "*/x64/*" -o -path "*/dxvk*" -o -path "*/system32/*" \) 2>/dev/null || true)

    if [ "${#candidates[@]}" -gt 0 ]; then
        printf '%s' "${candidates[0]}"
        return 0
    fi

    return 1
}

fetch_github_release_zip() {
    local repo_url="$1"
    local dest_dir="$2"
    local slug api_url zip_url zip_file

    slug="$(printf '%s' "$repo_url" | sed -E 's#https?://github\.com/##; s#git@github\.com:##; s#\.git$##; s#/$##')"
    api_url="https://api.github.com/repos/${slug}/releases/latest"

    info "Checking GitHub Releases at $api_url ..."
    if ! command -v curl >/dev/null 2>&1; then
        warn "curl not found; cannot download GitHub release zip."
        return 1
    fi

    if command -v python3 >/dev/null 2>&1; then
        zip_url="$(curl -fsSL "$api_url" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for a in data.get("assets", []):
    name = a.get("name", "").lower()
    if name.endswith(".zip"):
        print(a.get("browser_download_url", ""))
        break
' 2>/dev/null || true)"
    else
        zip_url="$(curl -fsSL "$api_url" | grep -oE '"browser_download_url": *"[^"]+\.zip"' | head -n 1 | cut -d'"' -f4 || true)"
    fi

    [ -n "$zip_url" ] || return 1

    zip_file="$TMP_DIR/package_release.zip"
    info "Downloading release archive: $zip_url"
    curl -fsSL -L "$zip_url" -o "$zip_file"

    mkdir -p "$dest_dir"
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$zip_file" -d "$dest_dir"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m zipfile -e "$zip_file" "$dest_dir"
    else
        die "Neither 'unzip' nor 'python3' is installed to extract $zip_file"
    fi
    return 0
}

find_package_root() {
    local search_dir="$1"
    local found_core=""

    if [ -d "$search_dir/Core" ] || [ -d "$search_dir/ShaderFixes" ]; then
        printf '%s' "$search_dir"
        return 0
    fi
    if [ -n "$PKG_CODE" ] && [ -d "$search_dir/$PKG_CODE/Core" ]; then
        printf '%s' "$search_dir/$PKG_CODE"
        return 0
    fi

    found_core="$(find "$search_dir" -maxdepth 3 -type d -name "Core" 2>/dev/null | head -n 1 || true)"
    if [ -n "$found_core" ]; then
        dirname "$found_core"
        return 0
    fi

    local found_sf
    found_sf="$(find "$search_dir" -maxdepth 3 -type d -name "ShaderFixes" 2>/dev/null | head -n 1 || true)"
    if [ -n "$found_sf" ]; then
        dirname "$found_sf"
        return 0
    fi

    return 1
}

patch_d3dx_ini() {
    local ini_path="$1"
    local target_exe="$2"
    local core_include="$3"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$ini_path" "$target_exe" "$core_include" <<'PYEOF'
import sys, re

ini_path, target_exe, core_include = sys.argv[1], sys.argv[2], sys.argv[3]

with open(ini_path, "r", encoding="utf-8", errors="replace") as f:
    raw = f.read()

newline = "\r\n" if "\r\n" in raw else "\n"
lines = raw.splitlines()

out = []
section = None
seen_loader_target = False
seen_include_core = False
seen_include_mods = False
seen_exclude = False

desired_system = {
    "load_library_redirect": "2",
    "allow_check_interface": "1",
    "allow_create_device": "1",
    "allow_platform_update": "1",
    "skip_early_includes_load": "0",
    "config_initialization_delay": "-1",
}
seen_system = set()

desired_logging = {
    "calls": "0",
    "debug": "0",
    "unbuffered": "0",
}
seen_logging = set()

desired_rendering = {
    "recursive_include": "1",
    "stereo_params": "-1",
    "ini_params": "120",
    "assemble_signature_comments": "1",
    "disassemble_undecipherable_custom_data": "1",
    "patch_assembly_cb_offsets": "1",
}
seen_rendering = set()

def flush_section(sec):
    if sec == "Loader" and target_exe and not seen_loader_target:
        out.append(f"target = {target_exe}")
    elif sec == "Include":
        if core_include and not seen_include_core:
            out.append(f"include = {core_include}")
        if not seen_include_mods:
            out.append("include_recursive = Mods")
        if not seen_exclude:
            out.append("exclude_recursive = DISABLED*")
    elif sec == "System":
        for k, v in desired_system.items():
            if k not in seen_system:
                out.append(f"{k} = {v}")
    elif sec == "Logging":
        for k, v in desired_logging.items():
            if k not in seen_logging:
                out.append(f"{k} = {v}")
    elif sec == "Rendering":
        for k, v in desired_rendering.items():
            if k not in seen_rendering:
                out.append(f"{k} = {v}")

sec_re = re.compile(r'^\s*\[([^\]]+)\]\s*(?:;.*)?$')
kv_re  = re.compile(r'^(\s*)([A-Za-z0-9_]+)(\s*=\s*)(.*)$')

for line in lines:
    m_sec = sec_re.match(line)
    if m_sec:
        flush_section(section)
        section = m_sec.group(1).strip()
        out.append(line)
        continue

    stripped = line.strip()
    if not stripped or stripped.startswith(";"):
        out.append(line)
        continue

    m_kv = kv_re.match(line)
    if m_kv and section:
        indent, key, eq, val = m_kv.groups()
        key_l = key.lower()

        if section == "Loader" and key_l == "target" and target_exe:
            out.append(f"{indent}target = {target_exe}")
            seen_loader_target = True
            continue
        elif section == "Include":
            if key_l == "include" and re.match(r'^Core\\(GIMI|SRMI|ZZMI|WWMI|EFMI)\\main\.ini$', val.strip(), re.I):
                if core_include:
                    if not seen_include_core:
                        out.append(f"{indent}include = {core_include}")
                        seen_include_core = True
                    continue
            elif key_l == "include_recursive" and val.strip().lower() == "mods":
                seen_include_mods = True
            elif key_l == "exclude_recursive" and "disabled" in val.strip().lower():
                seen_exclude = True
        elif section == "System" and key_l in desired_system:
            out.append(f"{indent}{key} = {desired_system[key_l]}")
            seen_system.add(key_l)
            continue
        elif section == "Logging" and key_l in desired_logging:
            out.append(f"{indent}{key} = {desired_logging[key_l]}")
            seen_logging.add(key_l)
            continue
        elif section == "Rendering" and key_l in desired_rendering:
            out.append(f"{indent}{key} = {desired_rendering[key_l]}")
            seen_rendering.add(key_l)
            continue

    out.append(line)

flush_section(section)

existing_secs = {m.group(1).strip() for l in out for m in [sec_re.match(l)] if m}
if "Loader" not in existing_secs and target_exe:
    out = ["[Loader]", f"target = {target_exe}", ""] + out
if "Include" not in existing_secs:
    out += ["", "[Include]"]
    if core_include:
        out.append(f"include = {core_include}")
    out += ["include_recursive = Mods", "exclude_recursive = DISABLED*"]
if "System" not in existing_secs:
    out += ["", "[System]"] + [f"{k} = {v}" for k, v in desired_system.items()]

with open(ini_path, "w", encoding="utf-8") as f:
    f.write(newline.join(out) + newline)
PYEOF
    else
        if [ -n "$TARGET_EXE" ]; then
            sed -i -E "s|^target[[:space:]]*=.*|target = $TARGET_EXE|" "$ini_path"
        fi
        if [ -n "$core_include" ]; then
            local escaped_inc
            escaped_inc="$(printf '%s' "$core_include" | sed 's/\\/\\\\/g')"
            sed -i -E "s|^include[[:space:]]*=[[:space:]]*Core\\\\(GIMI|SRMI|ZZMI|WWMI|EFMI)\\\\main\.ini.*|include = $escaped_inc|" "$ini_path"
        fi
        sed -i -E 's|^skip_early_includes_load[[:space:]]*=.*|skip_early_includes_load = 0|' "$ini_path"
        sed -i -E 's|^config_initialization_delay[[:space:]]*=.*|config_initialization_delay = -1|' "$ini_path"
        sed -i -E 's|^calls[[:space:]]*=.*|calls = 0|' "$ini_path"
        sed -i -E 's|^unbuffered[[:space:]]*=.*|unbuffered = 0|' "$ini_path"
    fi
}

do_uninstall() {
    prompt_game_dir
    prompt_wine_prefix
    local sys32="$WINE_PREFIX/drive_c/windows/system32"

    info "Uninstalling 3DMigoto-Linux DLLs (Mods/ will be preserved)..."

    if [ -f "$sys32/d3d11.dll" ]; then
        if is_3dmigoto_dll "$sys32/d3d11.dll"; then
            rm -f "$sys32/d3d11.dll"
            ok "Removed 3DMigoto d3d11.dll from $sys32"
        else
            warn "$sys32/d3d11.dll is not 3DMigoto; leaving it untouched."
        fi
    fi

    if [ -f "$sys32/original_d3d11.dll" ] && [ ! -f "$sys32/d3d11.dll" ]; then
        mv "$sys32/original_d3d11.dll" "$sys32/d3d11.dll"
        ok "Restored $sys32/original_d3d11.dll -> $sys32/d3d11.dll"
    fi

    if [ -f "$GAME_DIR/d3d11.dll" ] && is_3dmigoto_dll "$GAME_DIR/d3d11.dll"; then
        rm -f "$GAME_DIR/d3d11.dll"
        ok "Removed leftover 3DMigoto d3d11.dll from $GAME_DIR"
    fi

    if [ -f "$GAME_DIR/d3dcompiler_47.dll" ]; then
        rm -f "$GAME_DIR/d3dcompiler_47.dll"
        ok "Removed d3dcompiler_47.dll from $GAME_DIR"
    fi

    ok "Uninstall complete. Your Mods/, Core/, ShaderFixes/, and d3dx.ini remain intact."
}

install_dlls() {
    locate_migoto_binaries
    local sys32="$WINE_PREFIX/drive_c/windows/system32"

    # Back up / install DXVK -> <prefix>/drive_c/windows/system32/original_d3d11.dll
    if [ ! -f "$sys32/original_d3d11.dll" ] || [ -n "$DXVK_PATH" ]; then
        local dxvk_found=""
        dxvk_found="$(find_dxvk_candidate || true)"
        if [ -n "$dxvk_found" ]; then
            if [ "$(realpath "$dxvk_found")" != "$(realpath -m "$sys32/original_d3d11.dll")" ]; then
                cp -f "$dxvk_found" "$sys32/original_d3d11.dll"
                ok "Copied DXVK -> $sys32/original_d3d11.dll (from: $dxvk_found)"
            else
                ok "Verified existing DXVK: $sys32/original_d3d11.dll"
            fi
        else
            warn "Could not auto-detect a 64-bit DXVK d3d11.dll!"
            warn "3DMigoto-Linux requires DXVK renamed as 'original_d3d11.dll' inside '$sys32'."
            warn "Copy your Proton/Wine DXVK x64 d3d11.dll to '$sys32/original_d3d11.dll' before launching."
        fi
    else
        if is_3dmigoto_dll "$sys32/original_d3d11.dll"; then
            die "'$sys32/original_d3d11.dll' is a 3DMigoto DLL (would cause infinite recursion!). Replace it with DXVK's d3d11.dll."
        fi
        ok "Using existing DXVK: $sys32/original_d3d11.dll"
    fi

    # Install 3DMigoto d3d11.dll ONLY into prefix/drive_c/windows/system32
    cp -f "$D3D11_SRC" "$sys32/d3d11.dll"
    chmod 755 "$sys32/d3d11.dll"
    ok "Installed 3DMigoto d3d11.dll -> $sys32/d3d11.dll"

    # Ensure 3DMigoto d3d11.dll is NOT left in game_dir
    if [ -f "$GAME_DIR/d3d11.dll" ] && is_3dmigoto_dll "$GAME_DIR/d3d11.dll"; then
        rm -f "$GAME_DIR/d3d11.dll"
        info "Removed 3DMigoto d3d11.dll from game directory (kept exclusively in prefix system32)"
    fi

    # Keep native d3dcompiler_47.dll in the game directory
    if [ -n "$D3DCOMPILER_SRC" ]; then
        cp -f "$D3DCOMPILER_SRC" "$GAME_DIR/d3dcompiler_47.dll"
        ok "Installed native d3dcompiler_47.dll -> $GAME_DIR/d3dcompiler_47.dll"
    else
        warn "d3dcompiler_47.dll not found in release folder; ensure native 64-bit d3dcompiler_47.dll is placed in '$GAME_DIR'."
    fi
}

install_package() {
    command -v git >/dev/null 2>&1 || die "'git' is required. Please install git first."

    TMP_DIR="$(mktemp -d)"
    local clone_dir="$TMP_DIR/repo"
    local pkg_root=""

    info "Cloning $REPO_URL ..."
    git clone --depth 1 "$REPO_URL" "$clone_dir"

    if ! pkg_root="$(find_package_root "$clone_dir")"; then
        warn "Repository branch does not contain Core/ or ShaderFixes/ directly; checking GitHub Releases..."
        local release_dir="$TMP_DIR/release"
        if fetch_github_release_zip "$REPO_URL" "$release_dir"; then
            pkg_root="$(find_package_root "$release_dir" || true)"
        fi
    fi

    [ -n "$pkg_root" ] || die "Could not find Core/ or ShaderFixes/ inside '$REPO_URL'."
    ok "Found package contents at: $pkg_root"

    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"

    if [ -d "$pkg_root/Core" ]; then
        if [ -d "$GAME_DIR/Core" ]; then
            info "Replacing existing Core/ (old Core backed up to Core.bak.$stamp)"
            mv "$GAME_DIR/Core" "$GAME_DIR/Core.bak.$stamp"
        fi
        cp -a "$pkg_root/Core" "$GAME_DIR/Core"
        if [ ! -d "$GAME_DIR/Core/Debugger" ] && [ -d "$SCRIPT_DIR/Core/Debugger" ]; then
            cp -a "$SCRIPT_DIR/Core/Debugger" "$GAME_DIR/Core/Debugger"
            info "Added Core/Debugger from local release package"
        fi
        ok "Installed Core/ -> $GAME_DIR/Core"
    fi

    if [ -d "$pkg_root/ShaderFixes" ]; then
        if [ -d "$GAME_DIR/ShaderFixes" ]; then
            info "Replacing existing ShaderFixes/ (old ShaderFixes backed up to ShaderFixes.bak.$stamp)"
            mv "$GAME_DIR/ShaderFixes" "$GAME_DIR/ShaderFixes.bak.$stamp"
        fi
        cp -a "$pkg_root/ShaderFixes" "$GAME_DIR/ShaderFixes"
        ok "Installed ShaderFixes/ -> $GAME_DIR/ShaderFixes"
    else
        mkdir -p "$GAME_DIR/ShaderFixes"
    fi

    mkdir -p "$GAME_DIR/Mods"

    local core_include=""
    if [ -n "$PKG_CODE" ] && [ -f "$GAME_DIR/Core/$PKG_CODE/main.ini" ]; then
        core_include="Core\\${PKG_CODE}\\main.ini"
    else
        local detected_main
        detected_main="$(find "$GAME_DIR/Core" -maxdepth 2 -iname "main.ini" 2>/dev/null | head -n 1 || true)"
        if [ -n "$detected_main" ]; then
            local rel_main="${detected_main#"$GAME_DIR/"}"
            core_include="${rel_main//\//\\}"
        fi
    fi

    if [ "$KEEP_INI" = "1" ] && [ -f "$GAME_DIR/d3dx.ini" ]; then
        info "Keeping existing d3dx.ini (--keep-ini / keep_ini=1)"
    else
        if [ -f "$GAME_DIR/d3dx.ini" ]; then
            cp -f "$GAME_DIR/d3dx.ini" "$GAME_DIR/d3dx.ini.bak.$stamp"
            info "Backed up existing d3dx.ini -> d3dx.ini.bak.$stamp"
        fi

        if [ -f "$pkg_root/d3dx.ini" ]; then
            cp -f "$pkg_root/d3dx.ini" "$GAME_DIR/d3dx.ini"
            info "Copied d3dx.ini from cloned package"
        elif [ -f "$SCRIPT_DIR/d3dx.ini" ]; then
            cp -f "$SCRIPT_DIR/d3dx.ini" "$GAME_DIR/d3dx.ini"
            info "Copied base d3dx.ini template from $SCRIPT_DIR"
        elif [ -f "$SCRIPT_DIR/Dependencies/d3dx.ini" ]; then
            cp -f "$SCRIPT_DIR/Dependencies/d3dx.ini" "$GAME_DIR/d3dx.ini"
            info "Copied base d3dx.ini template from $SCRIPT_DIR/Dependencies"
        else
            die "No d3dx.ini found in cloned repo or '$SCRIPT_DIR'."
        fi

        patch_d3dx_ini "$GAME_DIR/d3dx.ini" "$TARGET_EXE" "$core_include"
        ok "Configured d3dx.ini (target=${TARGET_EXE:-auto}, include=${core_include:-none}, Linux/Wine flags applied)"
    fi
}

save_current_config() {
    [ -f "$CONFIG_FILE" ] || { warn "Config file '$CONFIG_FILE' does not exist; skipping save."; return 0; }
    [ -n "${CONF_SECTION_NAME:-}" ] || return 0

    conf_set "$CONFIG_FILE" "$CONF_SECTION_NAME" "enabled" "1"
    [ -n "$GAME_DIR" ]    && conf_set "$CONFIG_FILE" "$CONF_SECTION_NAME" "game_dir" "$GAME_DIR"
    [ -n "$WINE_PREFIX" ] && conf_set "$CONFIG_FILE" "$CONF_SECTION_NAME" "prefix" "$WINE_PREFIX"
    [ -n "$DXVK_PATH" ]   && conf_set "$CONFIG_FILE" "$CONF_SECTION_NAME" "dxvk" "$DXVK_PATH"
    [ -n "$REPO_URL" ]    && conf_set "$CONFIG_FILE" "$CONF_SECTION_NAME" "repo" "$REPO_URL"
    [ -n "$TARGET_EXE" ]  && conf_set "$CONFIG_FILE" "$CONF_SECTION_NAME" "exe" "$TARGET_EXE"
    ok "Saved configuration for [$CONF_SECTION_NAME] into $CONFIG_FILE"
}

show_status() {
    printf "\n${BOLD}=== 3DMigoto-Linux Configuration Status ===${NC}\n"
    printf "Config file: %s\n" "$CONFIG_FILE"
    if [ ! -f "$CONFIG_FILE" ]; then
        warn "Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    printf "Global prefix  : %s\n" "${GLOBAL_DEFAULT_PREFIX:-(not set)}"
    printf "Global dxvk    : %s\n" "${GLOBAL_DEFAULT_DXVK:-(auto)}"

    local sec enabled dir prefix eff_prefix dxvk exe sys32
    while IFS= read -r sec; do
        enabled="$(conf_get "$CONFIG_FILE" "$sec" "enabled")"
        dir="$(conf_get "$CONFIG_FILE" "$sec" "game_dir")"
        prefix="$(conf_get "$CONFIG_FILE" "$sec" "prefix")"
        dxvk="$(conf_get "$CONFIG_FILE" "$sec" "dxvk")"
        exe="$(conf_get "$CONFIG_FILE" "$sec" "exe")"
        eff_prefix="${prefix:-$GLOBAL_DEFAULT_PREFIX}"
        [ -n "$eff_prefix" ] && eff_prefix="$(normalize_prefix_path "$eff_prefix")"

        printf "\n${BOLD}[%s]${NC} (enabled=%s)\n" "$sec" "${enabled:-0}"
        if [ -z "$dir" ]; then
            printf "  game_dir        : ${YELLOW}(not configured)${NC}\n"
        elif [ -d "$dir" ]; then
            printf "  game_dir        : ${GREEN}%s${NC}\n" "$dir"
            if [ -n "$exe" ]; then
                if [ -f "$dir/$exe" ]; then
                    printf "  executable      : ${GREEN}%s (found)${NC}\n" "$exe"
                else
                    printf "  executable      : ${YELLOW}%s (not found)${NC}\n" "$exe"
                fi
            fi
            if [ -f "$dir/d3dcompiler_47.dll" ]; then
                printf "  d3dcompiler_47  : ${GREEN}Installed in game_dir${NC}\n"
            else
                printf "  d3dcompiler_47  : ${RED}Missing in game_dir${NC}\n"
            fi
            if [ -f "$dir/d3d11.dll" ] && is_3dmigoto_dll "$dir/d3d11.dll"; then
                printf "  game_dir d3d11  : ${YELLOW}Present in game_dir (re-run installer to keep only in prefix)${NC}\n"
            fi
        else
            printf "  game_dir        : ${RED}%s (directory missing)${NC}\n" "$dir"
        fi

        if [ -n "$eff_prefix" ]; then
            sys32="$eff_prefix/drive_c/windows/system32"
            if [ -d "$sys32" ]; then
                printf "  prefix          : ${GREEN}%s${NC}\n" "$eff_prefix"
                if [ -f "$sys32/d3d11.dll" ]; then
                    if is_3dmigoto_dll "$sys32/d3d11.dll"; then
                        printf "  system32 d3d11  : ${GREEN}3DMigoto installed${NC}\n"
                    else
                        printf "  system32 d3d11  : ${YELLOW}DXVK / non-3DMigoto${NC}\n"
                    fi
                else
                    printf "  system32 d3d11  : ${RED}Not found${NC}\n"
                fi
                if [ -f "$sys32/original_d3d11.dll" ]; then
                    if is_dxvk_dll "$sys32/original_d3d11.dll"; then
                        printf "  original_d3d11  : ${GREEN}DXVK valid (in system32)${NC}\n"
                    else
                        printf "  original_d3d11  : ${RED}Invalid / 3DMigoto conflict!${NC}\n"
                    fi
                else
                    printf "  original_d3d11  : ${YELLOW}Missing in system32 (will backup DXVK on install)${NC}\n"
                fi
            else
                printf "  prefix          : ${RED}%s (invalid/missing system32)${NC}\n" "$eff_prefix"
            fi
        else
            printf "  prefix          : ${YELLOW}(not configured)${NC}\n"
        fi
        [ -n "$dxvk" ] && printf "  dxvk            : %s\n" "$dxvk"
    done < <(conf_list_game_sections "$CONFIG_FILE")
    printf "\n"
}

run_single_game() {
    configure_game_preset
    prompt_game_dir
    prompt_wine_prefix

    if [ "$UNINSTALL" -eq 1 ]; then
        do_uninstall
        return 0
    fi

    if [ "$UPDATE_DLL_ONLY" = "1" ]; then
        install_dlls
    else
        install_package
        install_dlls
    fi

    if [ "$SAVE_CONFIG" -eq 1 ]; then
        save_current_config
    fi

    printf "\n${GREEN}${BOLD}=== Installation Complete ===${NC}\n"
    printf "Game directory  : %s\n" "$GAME_DIR"
    printf "Prefix system32 : %s/drive_c/windows/system32\n" "$WINE_PREFIX"
    [ -n "$PKG_CODE" ] && printf "Package         : %s\n" "$PKG_CODE"
    printf "\n${BOLD}Important Wine/Proton Launch Override:${NC}\n"
    printf "Make sure your launcher sets the following environment variable:\n"
    printf "  ${YELLOW}WINEDLLOVERRIDES=\"d3d11=n,b;d3dcompiler_47=n,b\"${NC}\n\n"
}

run_all_from_config() {
    [ -f "$CONFIG_FILE" ] || die "Config file not found: '$CONFIG_FILE'"
    local sec enabled count=0
    while IFS= read -r sec; do
        enabled="$(conf_get "$CONFIG_FILE" "$sec" "enabled")"
        if [ "$enabled" = "1" ] || [ "${enabled,,}" = "true" ]; then
            count=$((count + 1))
            info "=== Processing [$sec] from $CONFIG_FILE ==="
            GAME="$(printf '%s' "$sec" | tr '[:upper:]' '[:lower:]')"
            run_single_game
        fi
    done < <(conf_list_game_sections "$CONFIG_FILE")

    if [ "$count" -eq 0 ]; then
        die "No game sections with 'enabled = 1' found in '$CONFIG_FILE'."
    fi
}

main() {
    parse_args "$@"
    load_global_config

    if [ "$SHOW_STATUS" -eq 1 ]; then
        show_status
        exit 0
    fi

    if [ "$RUN_ALL" -eq 1 ]; then
        run_all_from_config
        exit 0
    fi

    if [ "$UNINSTALL" -eq 1 ]; then
        configure_game_preset
        do_uninstall
        exit 0
    fi

    run_single_game
}

main "$@"
