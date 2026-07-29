#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  script/dev-community.sh [web|desktop] [--build] [--dry-run]

Modes:
  web      Start the Community backend and frontend dev server (default).
  desktop  Start the frontend dev server and the JCEF desktop process.

Options:
  --build    Rebuild the Community backend before starting.
  --dry-run  Print the resolved commands without starting processes.
  -h, --help Show this help.

Desktop mode discovers a compatible JBR 17 + JCEF runtime from JBR_HOME,
JAVA_HOME, the active PATH Java (including jenv), a staged runtime, or an
installed Chat2DB Community.app on macOS. When none is available, it downloads
and verifies the pinned JetBrains Runtime in a user cache. JBR_HOME is optional,
but an explicitly invalid value fails fast.

Set CHAT2DB_JBR_DOWNLOAD=never to disable automatic downloads. Override the
cache or an HTTPS mirror with CHAT2DB_JBR_CACHE_DIR or CHAT2DB_JBR_BASE_URL.
--dry-run never writes the cache or accesses the network.
EOF
}

MODE="web"
MODE_SET=false
FORCE_BUILD=false
DRY_RUN=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        web|desktop)
            if [ "${MODE_SET}" = true ]; then
                echo "[error] multiple modes provided" >&2
                usage >&2
                exit 2
            fi
            MODE="$1"
            MODE_SET=true
            ;;
        --build)
            FORCE_BUILD=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[error] unknown mode: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
JBR_RUNTIME_MANIFEST="${SCRIPT_DIR}/jbr-runtime-manifest.sh"
CLIENT_DIR="${ROOT_DIR}/chat2db-community-client"
SERVER_DIR="${ROOT_DIR}/chat2db-community-server"
START_DIR="${SERVER_DIR}/chat2db-community-start"
BACKEND_TARGET_DIR="${START_DIR}/target"
BACKEND_JAR="${BACKEND_TARGET_DIR}/chat2db-community.jar"
BACKEND_LIB_DIR="${BACKEND_TARGET_DIR}/lib"
FRONTEND_URL="http://127.0.0.1:8889/"
BACKEND_PORT=10825
FRONTEND_PORT=8889
BACKEND_PID=""
CLIENT_PID=""
DESKTOP_JCEF_FRAMEWORKS=""
DESKTOP_FRAMEWORKS_LINK="${BACKEND_TARGET_DIR}/Frameworks"
DESKTOP_FRAMEWORKS_LINK_CREATED=false
JBR_DOWNLOAD_TEMP_DIR=""
JBR_DOWNLOAD_LOCK_DIR=""
JBR_DOWNLOAD_LOCK_TOKEN=""
JBR_DOWNLOAD_PROCESS_PID=""

# Keep project-aware version managers (jenv, asdf, mise, Volta) anchored to
# this checkout even when the launcher is invoked through an absolute path.
cd "${ROOT_DIR}"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[error] required command not found: $1" >&2
        exit 1
    fi
}

read_supported_node_version() {
    local node_bin="$1"
    local version
    local numeric_version
    local major
    local minor
    local patch

    [ -x "${node_bin}" ] || return 1
    version=$(cd "${CLIENT_DIR}" && "${node_bin}" --version 2>/dev/null || true)
    version=${version//$'\r'/}
    numeric_version=${version#v}
    IFS=. read -r major minor patch <<<"${numeric_version}"
    patch=${patch%%-*}
    if ! [[ "${major}" =~ ^[0-9]+$ ]] \
        || ! [[ "${minor}" =~ ^[0-9]+$ ]] \
        || ! [[ "${patch}" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    case "${major}" in
        18)
            [ "${minor}" -ge 17 ] || return 1
            ;;
        20|22) ;;
        *) return 1 ;;
    esac

    NODE_CANDIDATE_VERSION="v${major}.${minor}.${patch}"
    NODE_CANDIDATE_MAJOR="${major}"
    NODE_CANDIDATE_MINOR="${minor}"
    NODE_CANDIDATE_PATCH="${patch}"
    return 0
}

node_bin_from_home() {
    local node_home="$1"
    local normalized_home

    normalized_home=$(normalize_existing_directory "${node_home}" "$(uname -s)" 2>/dev/null) \
        || return 1

    if [ -x "${normalized_home}/bin/node" ]; then
        printf '%s\n' "${normalized_home}/bin/node"
        return 0
    fi
    if [ -x "${normalized_home}/node.exe" ]; then
        printf '%s\n' "${normalized_home}/node.exe"
        return 0
    fi
    return 1
}

activate_node_runtime() {
    local node_bin="$1"
    local source="$2"
    local node_bin_dir

    node_bin_dir=$(cd "$(dirname "${node_bin}")" && pwd -P)
    export PATH="${node_bin_dir}:${PATH}"
    hash -r
    echo "[dev] selected Node.js ${NODE_CANDIDATE_VERSION} from ${source}"
}

activate_nvm_project_node() {
    local nvm_script="${NVM_DIR:-${HOME}/.nvm}/nvm.sh"
    local original_directory="${PWD}"
    local nounset_enabled=false
    local nvm_status=1
    local source_label="NVM project version"
    local selected_node

    [ -s "${nvm_script}" ] || return 1
    case "$-" in
        *u*) nounset_enabled=true ;;
    esac
    set +u
    # nvm is a shell function, so its public bootstrap must be sourced here.
    . "${nvm_script}"
    cd "${ROOT_DIR}"
    if nvm use --silent >/dev/null 2>&1; then
        nvm_status=0
    elif nvm use --silent 20 >/dev/null 2>&1; then
        nvm_status=0
        source_label="NVM compatible fallback"
    fi
    cd "${original_directory}"
    if [ "${nounset_enabled}" = true ]; then
        set -u
    fi
    [ "${nvm_status}" -eq 0 ] || return 1

    selected_node=$(command -v node 2>/dev/null || true)
    read_supported_node_version "${selected_node}" || return 1
    activate_node_runtime "${selected_node}" "${source_label}"
    return 0
}

select_compatible_node() {
    local explicit_node_bin=""
    local current_node_bin=""
    local node_home_bin=""
    local current_version="not found"

    if [ -n "${CHAT2DB_NODE_HOME:-}" ]; then
        explicit_node_bin=$(node_bin_from_home "${CHAT2DB_NODE_HOME}" || true)
        if [ -z "${explicit_node_bin}" ] \
            || ! read_supported_node_version "${explicit_node_bin}"; then
            echo "[error] CHAT2DB_NODE_HOME must contain Node.js >=18.17 and <19, 20.x, or 22.x: ${CHAT2DB_NODE_HOME}" >&2
            exit 1
        fi
        activate_node_runtime "${explicit_node_bin}" "CHAT2DB_NODE_HOME"
        return
    fi

    current_node_bin=$(command -v node 2>/dev/null || true)
    if [ -n "${current_node_bin}" ]; then
        current_version=$("${current_node_bin}" --version 2>/dev/null || true)
        if read_supported_node_version "${current_node_bin}"; then
            return
        fi
    fi

    if [ -n "${NODE_HOME:-}" ]; then
        node_home_bin=$(node_bin_from_home "${NODE_HOME}" || true)
        if [ -n "${node_home_bin}" ] && read_supported_node_version "${node_home_bin}"; then
            activate_node_runtime "${node_home_bin}" "NODE_HOME"
            return
        fi
    fi

    if activate_nvm_project_node; then
        return
    fi

    echo "[error] Node.js ${current_version} is incompatible with this Umi toolchain." >&2
    echo "[error] Activate Node.js 22.22.2 (preferred), 20.x, or >=18.17 and <19 with your version manager." >&2
    echo "[error] You can also set CHAT2DB_NODE_HOME to a compatible Node.js installation." >&2
    exit 1
}

require_java_17() {
    local java_bin="$1"
    local version_output

    if [ ! -x "${java_bin}" ] && ! command -v "${java_bin}" >/dev/null 2>&1; then
        echo "[error] Java executable not found: ${java_bin}" >&2
        exit 1
    fi
    version_output=$("${java_bin}" -version 2>&1)
    if [[ "${version_output}" != *'version "17.'* ]]; then
        echo "[error] Java 17 is required: ${java_bin}" >&2
        echo "${version_output}" >&2
        exit 1
    fi
}

require_maven_java_17() {
    local version_output

    require_command mvn
    version_output=$(mvn -version 2>&1)
    if [[ "${version_output}" != *'Java version: 17.'* ]]; then
        echo "[error] Maven must run with Java 17" >&2
        echo "${version_output}" >&2
        exit 1
    fi
}

normalize_existing_directory() {
    local directory="$1"
    local platform="${2:-$(uname -s)}"

    case "${platform}" in
        MINGW*|MSYS*|CYGWIN*)
            if [[ "${directory}" =~ ^[A-Za-z]:[\\/].* ]]; then
                command -v cygpath >/dev/null 2>&1 || return 1
                directory=$(cygpath -u "${directory}") || return 1
            fi
            ;;
    esac

    [ -d "${directory}" ] || return 1
    (cd "${directory}" && pwd -P)
}

java_home_from_command() {
    local java_bin="$1"
    local settings
    local line

    [ -n "${java_bin}" ] || return 1
    settings=$("${java_bin}" -XshowSettings:properties -version 2>&1 || true)
    while IFS= read -r line; do
        line=${line%$'\r'}
        case "${line}" in
            *"java.home = "*)
                printf '%s\n' "${line#*java.home = }"
                return 0
                ;;
        esac
    done <<<"${settings}"
    return 1
}

project_jcef_api_version() {
    local pom_file="${SERVER_DIR}/chat2db-community-bom/pom.xml"
    local line
    local version

    [ -f "${pom_file}" ] || return 1
    while IFS= read -r line; do
        case "${line}" in
            *"<jcef.version>"*"</jcef.version>"*)
                version=${line#*<jcef.version>}
                version=${version%%</jcef.version>*}
                version=${version%%-*}
                if [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    printf '%s\n' "${version}"
                    return 0
                fi
                return 1
                ;;
        esac
    done <"${pom_file}"
    return 1
}

validate_desktop_runtime() {
    local candidate_home="$1"
    local platform="$2"
    local normalized_home
    local java_bin
    local version_output
    local modules_output
    local expected_jcef_version
    local runtime_jcef_version=""
    local release_line
    local missing_path=""
    local mac_frameworks=""
    local packaged_mac_frameworks=""

    DESKTOP_VALIDATION_ERROR=""
    DESKTOP_JCEF_FRAMEWORKS=""
    if ! normalized_home=$(normalize_existing_directory "${candidate_home}" "${platform}"); then
        DESKTOP_VALIDATION_ERROR="directory does not exist: ${candidate_home}"
        return 1
    fi

    case "${platform}" in
        MINGW*|MSYS*|CYGWIN*) java_bin="${normalized_home}/bin/java.exe" ;;
        *) java_bin="${normalized_home}/bin/java" ;;
    esac
    if [ ! -x "${java_bin}" ]; then
        DESKTOP_VALIDATION_ERROR="missing executable: ${java_bin}"
        return 1
    fi

    version_output=$("${java_bin}" -version 2>&1 || true)
    if [[ "${version_output}" != *'version "17.'* ]]; then
        DESKTOP_VALIDATION_ERROR="Java 17 is required: ${java_bin}"
        return 1
    fi
    modules_output=$("${java_bin}" --list-modules 2>/dev/null || true)
    if ! printf '%s\n' "${modules_output}" | grep -Eq '^jcef(@|$)'; then
        DESKTOP_VALIDATION_ERROR="Java runtime does not contain the jcef module: ${normalized_home}"
        return 1
    fi

    if ! expected_jcef_version=$(project_jcef_api_version); then
        DESKTOP_VALIDATION_ERROR="cannot read the project JCEF version from chat2db-community-bom/pom.xml"
        return 1
    fi
    if [ ! -f "${normalized_home}/release" ]; then
        DESKTOP_VALIDATION_ERROR="missing JCEF version metadata: ${normalized_home}/release"
        return 1
    fi
    while IFS= read -r release_line; do
        release_line=${release_line%$'\r'}
        case "${release_line}" in
            JCEF_VERSION=*)
                runtime_jcef_version=${release_line#JCEF_VERSION=}
                runtime_jcef_version=${runtime_jcef_version#\"}
                runtime_jcef_version=${runtime_jcef_version%\"}
                break
                ;;
        esac
    done <"${normalized_home}/release"
    case "${runtime_jcef_version}" in
        "${expected_jcef_version}"|"${expected_jcef_version}".*) ;;
        *)
            DESKTOP_VALIDATION_ERROR="JBR JCEF ${runtime_jcef_version:-unknown} is incompatible; project requires JCEF ${expected_jcef_version}"
            return 1
            ;;
    esac

    case "${platform}" in
        Darwin)
            mac_frameworks="${normalized_home}/../Frameworks"
            packaged_mac_frameworks="${normalized_home}/../../../app/Frameworks"
            if [ ! -d "${mac_frameworks}" ] && [ -d "${packaged_mac_frameworks}" ]; then
                mac_frameworks="${packaged_mac_frameworks}"
            fi
            if [ ! -f "${normalized_home}/lib/libjcef.dylib" ]; then
                missing_path="${normalized_home}/lib/libjcef.dylib"
            elif [ ! -x "${mac_frameworks}/Chromium Embedded Framework.framework/Chromium Embedded Framework" ]; then
                missing_path="${mac_frameworks}/Chromium Embedded Framework.framework/Chromium Embedded Framework"
            elif [ ! -f "${mac_frameworks}/Chromium Embedded Framework.framework/Resources/icudtl.dat" ]; then
                missing_path="${mac_frameworks}/Chromium Embedded Framework.framework/Resources/icudtl.dat"
            elif [ ! -f "${mac_frameworks}/Chromium Embedded Framework.framework/Resources/resources.pak" ]; then
                missing_path="${mac_frameworks}/Chromium Embedded Framework.framework/Resources/resources.pak"
            elif [ ! -x "${mac_frameworks}/jcef Helper.app/Contents/MacOS/jcef Helper" ]; then
                missing_path="${mac_frameworks}/jcef Helper.app/Contents/MacOS/jcef Helper"
            elif [ ! -x "${mac_frameworks}/jcef Helper (GPU).app/Contents/MacOS/jcef Helper (GPU)" ]; then
                missing_path="${mac_frameworks}/jcef Helper (GPU).app/Contents/MacOS/jcef Helper (GPU)"
            elif [ ! -x "${mac_frameworks}/jcef Helper (Renderer).app/Contents/MacOS/jcef Helper (Renderer)" ]; then
                missing_path="${mac_frameworks}/jcef Helper (Renderer).app/Contents/MacOS/jcef Helper (Renderer)"
            fi
            ;;
        Linux)
            if [ ! -f "${normalized_home}/lib/libjcef.so" ]; then
                missing_path="${normalized_home}/lib/libjcef.so"
            elif [ ! -f "${normalized_home}/lib/libcef.so" ]; then
                missing_path="${normalized_home}/lib/libcef.so"
            elif [ ! -x "${normalized_home}/lib/jcef_helper" ]; then
                missing_path="${normalized_home}/lib/jcef_helper"
            elif [ ! -x "${normalized_home}/lib/chrome-sandbox" ]; then
                missing_path="${normalized_home}/lib/chrome-sandbox"
            elif [ ! -f "${normalized_home}/lib/icudtl.dat" ]; then
                missing_path="${normalized_home}/lib/icudtl.dat"
            elif [ ! -f "${normalized_home}/lib/resources.pak" ]; then
                missing_path="${normalized_home}/lib/resources.pak"
            elif [ ! -d "${normalized_home}/lib/locales" ]; then
                missing_path="${normalized_home}/lib/locales"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            if [ ! -f "${normalized_home}/bin/jcef.dll" ]; then
                missing_path="${normalized_home}/bin/jcef.dll"
            elif [ ! -f "${normalized_home}/bin/libcef.dll" ]; then
                missing_path="${normalized_home}/bin/libcef.dll"
            elif [ ! -f "${normalized_home}/bin/jcef_helper.exe" ]; then
                missing_path="${normalized_home}/bin/jcef_helper.exe"
            elif [ ! -f "${normalized_home}/bin/chrome_elf.dll" ]; then
                missing_path="${normalized_home}/bin/chrome_elf.dll"
            elif [ ! -f "${normalized_home}/bin/icudtl.dat" ]; then
                missing_path="${normalized_home}/bin/icudtl.dat"
            elif [ ! -f "${normalized_home}/bin/resources.pak" ]; then
                missing_path="${normalized_home}/bin/resources.pak"
            elif [ ! -d "${normalized_home}/bin/locales" ]; then
                missing_path="${normalized_home}/bin/locales"
            fi
            ;;
        *)
            DESKTOP_VALIDATION_ERROR="unsupported desktop platform: ${platform}"
            return 1
            ;;
    esac
    if [ -n "${missing_path}" ]; then
        DESKTOP_VALIDATION_ERROR="missing JCEF native runtime file: ${missing_path}"
        return 1
    fi
    DESKTOP_JBR_HOME="${normalized_home}"
    DESKTOP_JAVA="${java_bin}"
    if [ "${platform}" = "Darwin" ]; then
        DESKTOP_JCEF_FRAMEWORKS=$(normalize_existing_directory "${mac_frameworks}" "${platform}")
    fi
    return 0
}

try_desktop_runtime() {
    local candidate_home="$1"
    local source="$2"
    local platform="$3"
    local normalized_home

    [ -n "${candidate_home}" ] || return 1
    normalized_home=$(normalize_existing_directory "${candidate_home}" "${platform}" 2>/dev/null \
        || printf '%s' "${candidate_home}")
    case "|${DESKTOP_SEEN_HOMES}|" in
        *"|${normalized_home}|"*) return 1 ;;
    esac
    DESKTOP_SEEN_HOMES="${DESKTOP_SEEN_HOMES}|${normalized_home}"

    if validate_desktop_runtime "${candidate_home}" "${platform}"; then
        DESKTOP_JBR_SOURCE="${source}"
        return 0
    fi
    DESKTOP_RUNTIME_ATTEMPTS="${DESKTOP_RUNTIME_ATTEMPTS}\n  - ${source}: ${candidate_home} (${DESKTOP_VALIDATION_ERROR})"
    return 1
}

#region Managed JBR runtime cache

resolve_jbr_cache_root() {
    local platform="$1"
    local cache_root="${CHAT2DB_JBR_CACHE_DIR:-}"
    local windows_cache_root=""

    if [ -n "${cache_root}" ]; then
        case "${platform}" in
            MINGW*|MSYS*|CYGWIN*)
                if [[ "${cache_root}" =~ ^[A-Za-z]:[\\/].* ]]; then
                    command -v cygpath >/dev/null 2>&1 || {
                        echo "[error] cygpath is required for a Windows CHAT2DB_JBR_CACHE_DIR" >&2
                        return 1
                    }
                    cache_root=$(cygpath -u "${cache_root}") || return 1
                fi
                ;;
        esac
    else
        case "${platform}" in
            Darwin)
                cache_root="${HOME}/Library/Caches/chat2db-community/jbr"
                ;;
            Linux)
                cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}/chat2db-community/jbr"
                ;;
            MINGW*|MSYS*|CYGWIN*)
                if [ -n "${LOCALAPPDATA:-}" ]; then
                    windows_cache_root="${LOCALAPPDATA}"
                    if [[ "${windows_cache_root}" =~ ^[A-Za-z]:[\\/].* ]]; then
                        command -v cygpath >/dev/null 2>&1 || {
                            echo "[error] cygpath is required to resolve LOCALAPPDATA" >&2
                            return 1
                        }
                        windows_cache_root=$(cygpath -u "${windows_cache_root}") || return 1
                    fi
                    cache_root="${windows_cache_root}/chat2db-community/jbr"
                else
                    cache_root="${HOME}/.cache/chat2db-community/jbr"
                fi
                ;;
            *)
                echo "[error] unsupported desktop platform: ${platform}" >&2
                return 1
                ;;
        esac
    fi

    case "${cache_root}" in
        /*) ;;
        *)
            echo "[error] CHAT2DB_JBR_CACHE_DIR must resolve to an absolute path" >&2
            return 1
            ;;
    esac
    if [ "${cache_root}" != "/" ]; then
        cache_root=${cache_root%/}
    fi
    JBR_CACHE_ROOT="${cache_root}"
}

set_managed_jbr_cache_paths() {
    local platform="$1"
    local checksum_prefix

    checksum_prefix=${JBR_RUNTIME_SHA512:0:16}
    JBR_CACHE_KEY="${JBR_RUNTIME_ARCHIVE%.tar.gz}-${checksum_prefix}"
    JBR_CACHE_INSTALL_DIR="${JBR_CACHE_ROOT}/${JBR_CACHE_KEY}"
    JBR_CACHE_MARKER="${JBR_CACHE_INSTALL_DIR}/.complete"
    JBR_CACHE_LOCK_PATH="${JBR_CACHE_ROOT}/.locks/${JBR_CACHE_KEY}.lock"
    JBR_CACHE_TMP_ROOT="${JBR_CACHE_ROOT}/.tmp"
    case "${platform}" in
        Darwin)
            JBR_CACHE_HOME="${JBR_CACHE_INSTALL_DIR}/Contents/Home"
            JBR_CACHE_FRAMEWORKS="${JBR_CACHE_INSTALL_DIR}/Contents/Frameworks"
            ;;
        *)
            JBR_CACHE_HOME="${JBR_CACHE_INSTALL_DIR}"
            JBR_CACHE_FRAMEWORKS=""
            ;;
    esac
}

resolve_managed_jbr_artifact() {
    local platform="$1"
    local architecture

    if [ ! -f "${JBR_RUNTIME_MANIFEST}" ]; then
        echo "[error] JBR runtime manifest not found: ${JBR_RUNTIME_MANIFEST}" >&2
        return 1
    fi
    # shellcheck source=./jbr-runtime-manifest.sh
    . "${JBR_RUNTIME_MANIFEST}"
    if ! declare -F resolve_jbr_runtime_artifact >/dev/null 2>&1; then
        echo "[error] JBR runtime manifest does not define resolve_jbr_runtime_artifact" >&2
        return 1
    fi

    architecture=$(uname -m)
    if ! resolve_jbr_runtime_artifact "${platform}" "${architecture}"; then
        echo "[error] no pinned JBR runtime for ${platform}/${architecture}" >&2
        return 1
    fi
    if [ -z "${JBR_RUNTIME_ARCHIVE:-}" ] \
        || ! [[ "${JBR_RUNTIME_SHA512:-}" =~ ^[0-9a-fA-F]{128}$ ]]; then
        echo "[error] invalid JBR runtime manifest entry for ${platform}/${architecture}" >&2
        return 1
    fi

    resolve_jbr_cache_root "${platform}"
    set_managed_jbr_cache_paths "${platform}"
}

jbr_cache_marker_matches() {
    [ -f "${JBR_CACHE_MARKER}" ] \
        && grep -Fqx "archive=${JBR_RUNTIME_ARCHIVE}" "${JBR_CACHE_MARKER}" \
        && grep -Fqx "sha512=${JBR_RUNTIME_SHA512}" "${JBR_CACHE_MARKER}"
}

activate_managed_jbr_cache() {
    local platform="$1"
    local record_error="${2:-true}"

    jbr_cache_marker_matches || return 1
    if validate_desktop_runtime "${JBR_CACHE_HOME}" "${platform}"; then
        DESKTOP_JBR_SOURCE="JBR cache"
        return 0
    fi
    if [ "${record_error}" = true ]; then
        DESKTOP_RUNTIME_ATTEMPTS="${DESKTOP_RUNTIME_ATTEMPTS}\n  - JBR cache: ${JBR_CACHE_HOME} (${DESKTOP_VALIDATION_ERROR})"
    fi
    return 1
}

calculate_sha512() {
    local file="$1"
    local checksum=""

    if command -v sha512sum >/dev/null 2>&1; then
        checksum=$(sha512sum "${file}" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        checksum=$(shasum -a 512 "${file}" | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        checksum=$(openssl dgst -sha512 "${file}" | awk '{print $NF}')
    else
        echo "[error] SHA-512 verification requires sha512sum, shasum, or openssl" >&2
        return 1
    fi
    printf '%s\n' "${checksum}" | tr 'A-F' 'a-f'
}

verify_jbr_archive() {
    local archive_path="$1"
    local actual_checksum
    local expected_checksum

    actual_checksum=$(calculate_sha512 "${archive_path}") || return 1
    expected_checksum=$(printf '%s' "${JBR_RUNTIME_SHA512}" | tr 'A-F' 'a-f')
    if [ "${actual_checksum}" != "${expected_checksum}" ]; then
        echo "[error] JBR archive SHA-512 verification failed: ${JBR_RUNTIME_ARCHIVE}" >&2
        return 1
    fi
}

cleanup_jbr_download() {
    local lock_token=""

    if [ -n "${JBR_DOWNLOAD_PROCESS_PID}" ]; then
        if kill -0 "${JBR_DOWNLOAD_PROCESS_PID}" 2>/dev/null; then
            kill -TERM "${JBR_DOWNLOAD_PROCESS_PID}" 2>/dev/null || true
        fi
        wait "${JBR_DOWNLOAD_PROCESS_PID}" 2>/dev/null || true
    fi
    JBR_DOWNLOAD_PROCESS_PID=""

    if [ -n "${JBR_DOWNLOAD_TEMP_DIR}" ] && [ -d "${JBR_DOWNLOAD_TEMP_DIR}" ]; then
        rm -rf "${JBR_DOWNLOAD_TEMP_DIR}"
    fi
    JBR_DOWNLOAD_TEMP_DIR=""

    if [ -n "${JBR_DOWNLOAD_LOCK_DIR}" ] \
        && [ -n "${JBR_DOWNLOAD_LOCK_TOKEN}" ] \
        && [ -f "${JBR_DOWNLOAD_LOCK_DIR}/token" ]; then
        lock_token=$(cat "${JBR_DOWNLOAD_LOCK_DIR}/token" 2>/dev/null || true)
        if [ "${lock_token}" = "${JBR_DOWNLOAD_LOCK_TOKEN}" ]; then
            rm -f "${JBR_DOWNLOAD_LOCK_DIR}/pid" "${JBR_DOWNLOAD_LOCK_DIR}/token"
            rmdir "${JBR_DOWNLOAD_LOCK_DIR}" 2>/dev/null || true
        fi
    fi
    JBR_DOWNLOAD_LOCK_DIR=""
    JBR_DOWNLOAD_LOCK_TOKEN=""
}

handle_jbr_download_signal() {
    local signal="$1"

    cleanup_jbr_download
    case "${signal}" in
        INT) exit 130 ;;
        TERM) exit 143 ;;
    esac
}

acquire_jbr_cache_lock() {
    local platform="$1"
    local owner_pid=""
    local stale_lock=""
    local wait_count=0

    JBR_CACHE_READY_DURING_LOCK=false
    mkdir -p "$(dirname "${JBR_CACHE_LOCK_PATH}")" "${JBR_CACHE_TMP_ROOT}"
    while ! mkdir "${JBR_CACHE_LOCK_PATH}" 2>/dev/null; do
        if activate_managed_jbr_cache "${platform}" false; then
            JBR_CACHE_READY_DURING_LOCK=true
            return 0
        fi

        owner_pid=$(cat "${JBR_CACHE_LOCK_PATH}/pid" 2>/dev/null || true)
        if [ -z "${owner_pid}" ]; then
            sleep 1
            owner_pid=$(cat "${JBR_CACHE_LOCK_PATH}/pid" 2>/dev/null || true)
        fi
        if [[ "${owner_pid}" =~ ^[0-9]+$ ]] && kill -0 "${owner_pid}" 2>/dev/null; then
            if [ "${wait_count}" -eq 0 ]; then
                echo "[dev] waiting for another launcher to finish the JBR download"
            fi
            if [ "${wait_count}" -ge 900 ]; then
                echo "[error] timed out waiting for the JBR cache lock" >&2
                return 1
            fi
            wait_count=$((wait_count + 1))
            sleep 2
            continue
        fi

        stale_lock="${JBR_CACHE_LOCK_PATH}.stale.$$.$RANDOM"
        if mv "${JBR_CACHE_LOCK_PATH}" "${stale_lock}" 2>/dev/null; then
            rm -rf "${stale_lock}"
        fi
    done

    JBR_DOWNLOAD_LOCK_DIR="${JBR_CACHE_LOCK_PATH}"
    JBR_DOWNLOAD_LOCK_TOKEN="$$.$RANDOM.$(date +%s)"
    printf '%s\n' "$$" >"${JBR_DOWNLOAD_LOCK_DIR}/pid"
    printf '%s\n' "${JBR_DOWNLOAD_LOCK_TOKEN}" >"${JBR_DOWNLOAD_LOCK_DIR}/token"
}

resolve_jbr_base_url() {
    local base_url="${CHAT2DB_JBR_BASE_URL:-${JBR_RUNTIME_DEFAULT_BASE_URL:-https://cache-redirector.jetbrains.com/intellij-jbr}}"
    local authority

    case "${base_url}" in
        https://*) ;;
        *)
            echo "[error] CHAT2DB_JBR_BASE_URL must use HTTPS" >&2
            return 1
            ;;
    esac
    authority=${base_url#https://}
    authority=${authority%%/*}
    case "${authority}" in
        ""|*@*)
            echo "[error] CHAT2DB_JBR_BASE_URL must not contain credentials" >&2
            return 1
            ;;
    esac
    JBR_DOWNLOAD_BASE_URL=${base_url%/}
}

plan_managed_jbr_download() {
    local platform="$1"

    resolve_jbr_base_url
    DESKTOP_JBR_HOME="${JBR_CACHE_HOME}"
    case "${platform}" in
        MINGW*|MSYS*|CYGWIN*) DESKTOP_JAVA="${DESKTOP_JBR_HOME}/bin/java.exe" ;;
        *) DESKTOP_JAVA="${DESKTOP_JBR_HOME}/bin/java" ;;
    esac
    DESKTOP_JBR_SOURCE="automatic JBR download (planned)"
    if [ "${platform}" = "Darwin" ]; then
        DESKTOP_JCEF_FRAMEWORKS="${JBR_CACHE_FRAMEWORKS}"
    fi

    echo "[dry-run] JBR download: ${JBR_DOWNLOAD_BASE_URL}/${JBR_RUNTIME_ARCHIVE}"
    echo "[dry-run] JBR SHA-512: ${JBR_RUNTIME_SHA512}"
    echo "[dry-run] JBR cache: ${JBR_CACHE_INSTALL_DIR}"
}

install_managed_jbr() {
    local platform="$1"
    local archive_path
    local curl_status=0
    local extracted_runtime
    local extracted_home

    resolve_jbr_base_url
    require_command curl
    require_command tar

    mkdir -p "${JBR_CACHE_ROOT}"
    JBR_CACHE_ROOT=$(cd "${JBR_CACHE_ROOT}" && pwd -P)
    set_managed_jbr_cache_paths "${platform}"
    if activate_managed_jbr_cache "${platform}"; then
        return 0
    fi

    trap cleanup_jbr_download EXIT
    trap 'handle_jbr_download_signal INT' INT
    trap 'handle_jbr_download_signal TERM' TERM

    acquire_jbr_cache_lock "${platform}"
    if [ "${JBR_CACHE_READY_DURING_LOCK}" = true ]; then
        return 0
    fi
    if activate_managed_jbr_cache "${platform}" false; then
        cleanup_jbr_download
        return 0
    fi

    JBR_DOWNLOAD_TEMP_DIR=$(mktemp -d "${JBR_CACHE_TMP_ROOT}/${JBR_CACHE_KEY}.XXXXXX")
    archive_path="${JBR_DOWNLOAD_TEMP_DIR}/${JBR_RUNTIME_ARCHIVE}.part"
    extracted_runtime="${JBR_DOWNLOAD_TEMP_DIR}/runtime"
    mkdir -p "${extracted_runtime}"

    echo "[dev] downloading JBR 17 + JCEF: ${JBR_RUNTIME_ARCHIVE}"
    curl --fail --location --proto '=https' --proto-redir '=https' \
        --retry 3 --retry-delay 2 --continue-at - \
        --output "${archive_path}" \
        "${JBR_DOWNLOAD_BASE_URL}/${JBR_RUNTIME_ARCHIVE}" &
    JBR_DOWNLOAD_PROCESS_PID=$!
    if wait "${JBR_DOWNLOAD_PROCESS_PID}"; then
        curl_status=0
    else
        curl_status=$?
    fi
    JBR_DOWNLOAD_PROCESS_PID=""
    if [ "${curl_status}" -ne 0 ]; then
        echo "[error] JBR download failed: ${JBR_RUNTIME_ARCHIVE}" >&2
        return 1
    fi
    verify_jbr_archive "${archive_path}"
    echo "[dev] verified JBR archive SHA-512"
    if ! tar -xzf "${archive_path}" -C "${extracted_runtime}" --strip-components=1; then
        echo "[error] failed to extract JBR archive: ${JBR_RUNTIME_ARCHIVE}" >&2
        return 1
    fi

    case "${platform}" in
        Darwin) extracted_home="${extracted_runtime}/Contents/Home" ;;
        *) extracted_home="${extracted_runtime}" ;;
    esac
    if ! validate_desktop_runtime "${extracted_home}" "${platform}"; then
        echo "[error] downloaded JBR runtime is invalid: ${DESKTOP_VALIDATION_ERROR}" >&2
        return 1
    fi
    printf 'archive=%s\nsha512=%s\n' \
        "${JBR_RUNTIME_ARCHIVE}" "${JBR_RUNTIME_SHA512}" \
        >"${extracted_runtime}/.complete"

    case "${JBR_CACHE_INSTALL_DIR}" in
        "${JBR_CACHE_ROOT}"/*) ;;
        *)
            echo "[error] refusing to replace a JBR cache path outside the cache root" >&2
            return 1
            ;;
    esac
    if [ -e "${JBR_CACHE_INSTALL_DIR}" ] || [ -L "${JBR_CACHE_INSTALL_DIR}" ]; then
        rm -rf "${JBR_CACHE_INSTALL_DIR}"
    fi
    if ! mv "${extracted_runtime}" "${JBR_CACHE_INSTALL_DIR}"; then
        echo "[error] failed to install the verified JBR cache" >&2
        return 1
    fi
    if ! validate_desktop_runtime "${JBR_CACHE_HOME}" "${platform}"; then
        rm -rf "${JBR_CACHE_INSTALL_DIR}"
        echo "[error] installed JBR cache is invalid: ${DESKTOP_VALIDATION_ERROR}" >&2
        return 1
    fi
    DESKTOP_JBR_SOURCE="JBR cache"
    cleanup_jbr_download
    echo "[dev] cached JBR runtime: ${JBR_CACHE_INSTALL_DIR}"
}

report_missing_desktop_runtime() {
    echo "[error] No compatible JBR 17 + JCEF runtime found." >&2
    if [ -n "${DESKTOP_RUNTIME_ATTEMPTS}" ]; then
        printf '[error] Checked:%b\n' "${DESKTOP_RUNTIME_ATTEMPTS}" >&2
    fi
    echo "[error] Set JBR_HOME, select a JCEF JBR via your Java manager, or allow the pinned JBR download." >&2
}

#endregion

resolve_desktop_java() {
    local platform
    local download_policy
    local path_java=""
    local path_java_home=""
    local staged_home=""
    local runtime_found=false
    local community_app=""

    platform=$(uname -s)
    DESKTOP_JBR_HOME=""
    DESKTOP_JBR_SOURCE=""
    DESKTOP_SEEN_HOMES=""
    DESKTOP_RUNTIME_ATTEMPTS=""
    DESKTOP_JCEF_FRAMEWORKS=""

    if [ -n "${JBR_HOME:-}" ]; then
        if ! validate_desktop_runtime "${JBR_HOME}" "${platform}"; then
            echo "[error] JBR_HOME is invalid: ${DESKTOP_VALIDATION_ERROR}" >&2
            exit 1
        fi
        DESKTOP_JBR_SOURCE="JBR_HOME"
    else
        if try_desktop_runtime "${JAVA_HOME:-}" "JAVA_HOME" "${platform}"; then
            :
        else
            path_java=$(command -v java 2>/dev/null || true)
            path_java_home=$(java_home_from_command "${path_java}" || true)
            if try_desktop_runtime "${path_java_home}" "PATH java.home" "${platform}"; then
                :
            else
                case "${platform}" in
                    Darwin)
                        if [ -n "${CHAT2DB_COMMUNITY_APP:-}" ]; then
                            community_app="${CHAT2DB_COMMUNITY_APP}"
                            if try_desktop_runtime \
                                "${community_app}/Contents/runtime/Contents/Home" \
                                "installed Community app" "${platform}"; then
                                runtime_found=true
                            fi
                        elif try_desktop_runtime \
                            "/Applications/Chat2DB Community.app/Contents/runtime/Contents/Home" \
                            "installed Community app" "${platform}"; then
                            runtime_found=true
                        elif try_desktop_runtime \
                            "${HOME}/Applications/Chat2DB Community.app/Contents/runtime/Contents/Home" \
                            "installed Community app" "${platform}"; then
                            runtime_found=true
                        fi
                        ;;
                    Linux)
                        staged_home="${ROOT_DIR}/jpackage/input/runtime/linux/Home"
                        ;;
                    MINGW*|MSYS*|CYGWIN*)
                        staged_home="${ROOT_DIR}/jpackage/input/runtime/win/Home"
                        ;;
                esac
                if [ "${runtime_found}" = false ] \
                    && try_desktop_runtime "${staged_home}" "staged runtime" "${platform}"; then
                    runtime_found=true
                fi
                if [ "${runtime_found}" = false ]; then
                    resolve_managed_jbr_artifact "${platform}"
                    if activate_managed_jbr_cache "${platform}"; then
                        runtime_found=true
                    else
                        download_policy="${CHAT2DB_JBR_DOWNLOAD:-auto}"
                        case "${download_policy}" in
                            auto)
                                if [ "${DRY_RUN}" = true ]; then
                                    plan_managed_jbr_download "${platform}"
                                else
                                    install_managed_jbr "${platform}"
                                fi
                                runtime_found=true
                                ;;
                            never)
                                report_missing_desktop_runtime
                                echo "[error] Automatic JBR download is disabled by CHAT2DB_JBR_DOWNLOAD=never." >&2
                                exit 1
                                ;;
                            *)
                                echo "[error] CHAT2DB_JBR_DOWNLOAD must be auto or never" >&2
                                exit 1
                                ;;
                        esac
                    fi
                fi
            fi
        fi
    fi

    echo "[dev] desktop runtime: ${DESKTOP_JBR_HOME} (${DESKTOP_JBR_SOURCE})"
    if [ -n "${DESKTOP_JCEF_FRAMEWORKS}" ]; then
        echo "[dev] desktop JCEF Frameworks: ${DESKTOP_JCEF_FRAMEWORKS}"
    fi
}

prepare_desktop_jcef_frameworks() {
    local standard_frameworks=""
    local existing_target=""

    [ "${MODE}" = "desktop" ] || return
    [ "$(uname -s)" = "Darwin" ] || return
    [ -n "${DESKTOP_JCEF_FRAMEWORKS}" ] || return

    standard_frameworks=$(normalize_existing_directory \
        "${DESKTOP_JBR_HOME}/../Frameworks" "Darwin" 2>/dev/null || true)
    if [ "${DESKTOP_JCEF_FRAMEWORKS}" = "${standard_frameworks}" ]; then
        return
    fi

    if [ -L "${DESKTOP_FRAMEWORKS_LINK}" ]; then
        existing_target=$(readlink "${DESKTOP_FRAMEWORKS_LINK}")
        case "${existing_target}" in
            /*) ;;
            *) existing_target="$(dirname "${DESKTOP_FRAMEWORKS_LINK}")/${existing_target}" ;;
        esac
        existing_target=$(normalize_existing_directory "${existing_target}" "Darwin" 2>/dev/null || true)
        if [ "${existing_target}" != "${DESKTOP_JCEF_FRAMEWORKS}" ]; then
            echo "[error] existing desktop Frameworks link points elsewhere: ${DESKTOP_FRAMEWORKS_LINK}" >&2
            exit 1
        fi
        return
    fi
    if [ -e "${DESKTOP_FRAMEWORKS_LINK}" ]; then
        echo "[error] refusing to replace existing desktop Frameworks path: ${DESKTOP_FRAMEWORKS_LINK}" >&2
        exit 1
    fi

    ln -s "${DESKTOP_JCEF_FRAMEWORKS}" "${DESKTOP_FRAMEWORKS_LINK}"
    DESKTOP_FRAMEWORKS_LINK_CREATED=true
    echo "[dev] linked packaged JCEF Frameworks: ${DESKTOP_FRAMEWORKS_LINK}"
}

cleanup_desktop_jcef_frameworks() {
    local existing_target=""

    [ "${DESKTOP_FRAMEWORKS_LINK_CREATED}" = true ] || return
    if [ -L "${DESKTOP_FRAMEWORKS_LINK}" ]; then
        existing_target=$(readlink "${DESKTOP_FRAMEWORKS_LINK}")
        if [ "${existing_target}" = "${DESKTOP_JCEF_FRAMEWORKS}" ]; then
            rm "${DESKTOP_FRAMEWORKS_LINK}"
        fi
    fi
    DESKTOP_FRAMEWORKS_LINK_CREATED=false
}

backend_needs_build() {
    local newer_source

    if [ "${FORCE_BUILD}" = true ] || [ ! -f "${BACKEND_JAR}" ] \
        || [ ! -d "${BACKEND_LIB_DIR}" ]; then
        return 0
    fi
    if ! desktop_external_dependencies_complete; then
        return 0
    fi

    newer_source=$(find "${SERVER_DIR}" \
        \( -path '*/src/main/*' -o -name 'pom.xml' \) \
        -type f -newer "${BACKEND_JAR}" -print -quit 2>/dev/null || true)
    [ -n "${newer_source}" ]
}

desktop_external_dependencies_complete() {
    local flatlaf_jar=""

    [ "${MODE}" = "desktop" ] || return 0
    [ "$(uname -s)" = "Darwin" ] || return 0
    flatlaf_jar=$(find "${BACKEND_LIB_DIR}" -maxdepth 1 -type f \
        -name 'flatlaf-*.jar' -print -quit 2>/dev/null || true)
    [ -n "${flatlaf_jar}" ]
}

build_backend() {
    local build_java_home=""
    local path_java=""
    local maven_command=(
        mvn -B clean package
        -Dmaven.test.skip=true
        -Dchat2db.finalName=chat2db-community
    )

    if [ "${MODE}" = "desktop" ] && [ "$(uname -s)" = "Darwin" ]; then
        # The release macOS profile excludes FlatLaf for package signing. Source
        # Desktop runs still need its classes in the external loader directory.
        maven_command+=(
            -Dchat2db.externalLib.excludeArtifactIds=__chat2db_dev_none__
        )
    fi
    maven_command+=(
        -f "${SERVER_DIR}/pom.xml"
        -pl chat2db-community-start -am
    )

    echo "[dev] building Community backend (tests skipped)"
    if [ "${DRY_RUN}" = true ]; then
        print_command build "${maven_command[@]}"
        return
    fi

    if [ "${MODE}" = "desktop" ]; then
        build_java_home="${DESKTOP_JBR_HOME}"
    else
        path_java=$(command -v java 2>/dev/null || true)
        build_java_home=$(java_home_from_command "${path_java}" || true)
        build_java_home=$(normalize_existing_directory "${build_java_home}" "$(uname -s)" 2>/dev/null || true)
    fi
    if [ -z "${build_java_home}" ]; then
        echo "[error] cannot resolve Java 17 home for the Maven build" >&2
        exit 1
    fi

    (
        export JAVA_HOME="${build_java_home}"
        export PATH="${JAVA_HOME}/bin:${PATH}"
        require_maven_java_17
        "${maven_command[@]}"
    )
}

prepare_frontend() {
    if [ -e "${CLIENT_DIR}/node_modules/.bin/umi" ]; then
        return
    fi

    echo "[dev] frontend dependencies are missing; installing from yarn.lock"
    if [ "${DRY_RUN}" = true ]; then
        echo "[dry-run] (cd ${CLIENT_DIR} && yarn install --frozen-lockfile)"
        return
    fi
    (
        cd "${CLIENT_DIR}"
        yarn install --frozen-lockfile
    )
}

port_is_listening() {
    local port="$1"
    local probe_result

    if ! probe_result=$(node -e '
const net = require("net");
const host = "127.0.0.1";
const port = Number(process.argv[1]);
const server = net.createServer();

server.once("error", (error) => {
  if (error.code === "EADDRINUSE") {
    process.stdout.write("occupied");
    return;
  }
  process.stdout.write(`error:${error.code || "UNKNOWN"}:${error.message}`);
});
server.listen({ host, port, exclusive: true }, () => {
  server.close((error) => {
    if (error) {
      process.stdout.write(`error:${error.code || "UNKNOWN"}:${error.message}`);
      return;
    }
    process.stdout.write("free");
  });
});
' "${port}" 2>&1); then
        echo "[error] cannot verify 127.0.0.1:${port}: Node.js port probe failed" >&2
        return 2
    fi

    case "${probe_result}" in
        occupied) return 0 ;;
        free) return 1 ;;
        error:*)
            echo "[error] cannot verify 127.0.0.1:${port}: ${probe_result#error:}" >&2
            return 2
            ;;
        *)
            echo "[error] cannot verify 127.0.0.1:${port}: unexpected Node.js port probe output" >&2
            return 2
            ;;
    esac
}

require_free_port() {
    local port="$1"
    local probe_status

    if port_is_listening "${port}"; then
        echo "[error] 127.0.0.1:${port} is already in use; refusing to stop an unrelated process" >&2
        exit 1
    else
        probe_status=$?
    fi
    if [ "${probe_status}" -ne 1 ]; then
        exit 1
    fi
}

print_command() {
    local label="$1"
    shift

    printf '[dry-run] %s:' "${label}"
    printf ' %q' "$@"
    printf '\n'
}

WEB_BACKEND_COMMAND=(
    java
    "-Dloader.path=${BACKEND_LIB_DIR}"
    -Dchat2db.gui=false
    -Dchat2db.runtime.mode=community
    -Dchat2db.mode=WEB
    -Dchat2db.network.status=OFFLINE
    "-Dchat2db.community.encryption-key-file=${CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE:-${HOME}/.config/chat2db-community/encryption.key}"
    -Dserver.address=127.0.0.1
    "-Dserver.port=${BACKEND_PORT}"
    -Dspring.profiles.active=dev
    -jar "${BACKEND_JAR}"
)

select_compatible_node
require_command yarn
if [ "${MODE}" = "web" ]; then
    require_java_17 java
fi
if [ "${DRY_RUN}" = false ]; then
    require_free_port "${FRONTEND_PORT}"
    require_free_port "${BACKEND_PORT}"
fi

DESKTOP_COMMAND=()
if [ "${MODE}" = "desktop" ]; then
    resolve_desktop_java
    DESKTOP_COMMAND=("${DESKTOP_JAVA}")
    case "$(uname -s)" in
        Darwin)
            DESKTOP_COMMAND+=(
                --add-opens=java.desktop/sun.awt=ALL-UNNAMED
                --add-opens=java.desktop/sun.lwawt=ALL-UNNAMED
                --add-opens=java.desktop/sun.lwawt.macosx=ALL-UNNAMED
                --add-opens=java.desktop/com.apple.eawt=ALL-UNNAMED
                -Dapple.awt.application.appearance=system
                "-Dapple.awt.application.name=Chat2DB Community"
                -Dapple.laf.useScreenMenuBar=true
            )
            ;;
        MINGW*|MSYS*|CYGWIN*)
            DESKTOP_COMMAND+=(
                --add-opens=java.desktop/sun.awt=ALL-UNNAMED
                --add-opens=java.desktop/sun.lwawt=ALL-UNNAMED
                -Dsun.java2d.d3d=false
            )
            ;;
    esac
    DESKTOP_COMMAND+=(
        "-Dloader.path=${BACKEND_LIB_DIR}"
        -Dchat2db.gui=true
        -Dchat2db.runtime.mode=community
        -Dchat2db.mode=DESKTOP
        -Dchat2db.network.status=OFFLINE
        -Dfile.encoding=UTF-8
        -Dserver.address=127.0.0.1
        "-Dserver.port=${BACKEND_PORT}"
        -Dspring.profiles.active=dev
        -jar "${BACKEND_JAR}"
    )
fi

if backend_needs_build; then
    build_backend
fi
prepare_frontend

echo "[dev] mode: ${MODE}"
echo "[dev] frontend: ${FRONTEND_URL}"

if [ "${DRY_RUN}" = true ]; then
    print_command frontend yarn run start:community:hot
    if [ "${MODE}" = "web" ]; then
        print_command backend "${WEB_BACKEND_COMMAND[@]}"
    else
        print_command desktop "${DESKTOP_COMMAND[@]}"
    fi
    echo "[dry-run] no processes started"
    exit 0
fi

require_free_port "${FRONTEND_PORT}"
require_free_port "${BACKEND_PORT}"

if [ ! -f "${BACKEND_JAR}" ] || [ ! -d "${BACKEND_LIB_DIR}" ]; then
    echo "[error] Community backend artifact is incomplete after build" >&2
    exit 1
fi
if ! desktop_external_dependencies_complete; then
    echo "[error] Community Desktop dependencies are incomplete after build: FlatLaf is missing" >&2
    exit 1
fi

if [ "${MODE}" = "web" ]; then
    "${SCRIPT_DIR}/security/init-community-encryption-key.sh" \
        "${CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE:-${HOME}/.config/chat2db-community/encryption.key}"
fi

stop_process_group() {
    local label="$1"
    local pid="$2"

    if [ -z "${pid}" ]; then
        return
    fi
    if kill -0 -- "-${pid}" 2>/dev/null; then
        echo "[dev] stopping ${label} process group (pid ${pid})"
        kill -TERM -- "-${pid}" 2>/dev/null || true
    elif kill -0 "${pid}" 2>/dev/null; then
        echo "[dev] stopping ${label} process (pid ${pid})"
        kill -TERM "${pid}" 2>/dev/null || true
    fi
}

cleanup_processes() {
    local exit_status=$?

    trap - EXIT INT TERM
    stop_process_group frontend "${CLIENT_PID}"
    stop_process_group "${MODE}" "${BACKEND_PID}"
    if [ -n "${CLIENT_PID}" ]; then
        wait "${CLIENT_PID}" 2>/dev/null || true
    fi
    if [ -n "${BACKEND_PID}" ]; then
        wait "${BACKEND_PID}" 2>/dev/null || true
    fi
    cleanup_desktop_jcef_frameworks
    exit "${exit_status}"
}

trap cleanup_processes EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Bash 3.2 has no wait -n. Monitor mode also gives each background task its
# own process group so cleanup includes Yarn/Umi descendants.
set -m

start_frontend() {
    (
        cd "${CLIENT_DIR}"
        exec yarn run start:community:hot
    ) &
    CLIENT_PID=$!
    echo "[dev] frontend started (pid ${CLIENT_PID})"
}

wait_for_frontend() {
    local attempts=0

    require_command curl
    echo "[dev] waiting for ${FRONTEND_URL}"
    while [ "${attempts}" -lt 90 ]; do
        if ! kill -0 "${CLIENT_PID}" 2>/dev/null; then
            echo "[error] frontend exited before it became ready" >&2
            return 1
        fi
        if curl --fail --silent --output /dev/null "${FRONTEND_URL}"; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    echo "[error] frontend did not become ready within 90 seconds" >&2
    return 1
}

wait_for_processes() {
    local exited_label
    local exited_pid
    local status

    while :; do
        if ! kill -0 "${BACKEND_PID}" 2>/dev/null; then
            exited_label="${MODE}"
            exited_pid="${BACKEND_PID}"
            break
        fi
        if ! kill -0 "${CLIENT_PID}" 2>/dev/null; then
            exited_label="frontend"
            exited_pid="${CLIENT_PID}"
            break
        fi
        sleep 1
    done

    if wait "${exited_pid}"; then
        status=0
    else
        status=$?
    fi
    echo "[dev] ${exited_label} exited with status ${status}"
    return "${status}"
}

if [ "${MODE}" = "web" ]; then
    "${WEB_BACKEND_COMMAND[@]}" &
    BACKEND_PID=$!
    echo "[dev] backend started (pid ${BACKEND_PID})"
    start_frontend
else
    prepare_desktop_jcef_frameworks
    start_frontend
    wait_for_frontend
    "${DESKTOP_COMMAND[@]}" &
    BACKEND_PID=$!
    echo "[dev] desktop started (pid ${BACKEND_PID})"
fi

echo "[dev] press Ctrl+C to stop both processes"
wait_for_processes
