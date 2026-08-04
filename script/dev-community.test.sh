#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
SOURCE_LAUNCHER="${SCRIPT_DIR}/dev-community.sh"
SOURCE_JBR_MANIFEST="${SCRIPT_DIR}/jbr-runtime-manifest.sh"
TEST_ROOT="$(mktemp -d)"
FIXTURE_ROOT="${TEST_ROOT}/repo"
FAKE_BIN="${TEST_ROOT}/bin"
STATE_DIR="${TEST_ROOT}/state"
JBR_ARCHIVE_FIXTURE="${TEST_ROOT}/fixture-jbr.tar.gz"
SOURCE_JBR_MANIFEST_PRESENT=false

cleanup() {
    if [ -n "${LAUNCHER_PID:-}" ] && kill -0 "${LAUNCHER_PID}" 2>/dev/null; then
        kill -TERM "${LAUNCHER_PID}" 2>/dev/null || true
        wait "${LAUNCHER_PID}" 2>/dev/null || true
    fi
    if [ -f "${STATE_DIR}/client-child.pid" ]; then
        kill -TERM "$(cat "${STATE_DIR}/client-child.pid")" 2>/dev/null || true
    fi
    rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

fail() {
    echo "[fail] $*" >&2
    exit 1
}

assert_contains() {
    local actual="$1"
    local expected="$2"

    if [[ "${actual}" != *"${expected}"* ]]; then
        fail "expected output to contain: ${expected}\nactual output:\n${actual}"
    fi
}

assert_not_contains() {
    local actual="$1"
    local unexpected="$2"

    if [[ "${actual}" == *"${unexpected}"* ]]; then
        fail "expected output not to contain: ${unexpected}\nactual output:\n${actual}"
    fi
}

assert_file_exists() {
    local file="$1"

    [ -f "${file}" ] || fail "expected file to exist: ${file}"
}

assert_path_missing() {
    local path="$1"

    [ ! -e "${path}" ] || fail "expected path not to exist: ${path}"
}

assert_line_count() {
    local file="$1"
    local expected="$2"
    local actual=0

    if [ -f "${file}" ]; then
        actual=$(wc -l <"${file}" | tr -d ' ')
    fi
    [ "${actual}" -eq "${expected}" ] \
        || fail "expected ${file} to contain ${expected} lines, got ${actual}"
}

run_launcher() {
    set +e
    OUTPUT=$(env -u JBR_HOME -u JAVA_HOME -u CHAT2DB_NODE_HOME -u NODE_HOME \
        PATH="${FAKE_BIN}:${PATH}" \
        HOME="${TEST_ROOT}/home" \
        NVM_DIR="${TEST_ROOT}/home/.nvm" \
        CHAT2DB_COMMUNITY_APP="${TEST_ROOT}/missing-community.app" \
        CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE="${TEST_ROOT}/encryption.key" \
        FAKE_STATE_DIR="${STATE_DIR}" \
        bash "${FIXTURE_ROOT}/script/dev-community.sh" "$@" 2>&1)
    STATUS=$?
    set -e
}

wait_for_file() {
    local file="$1"
    local attempts=0

    while [ ! -f "${file}" ] && [ "${attempts}" -lt 50 ]; do
        sleep 0.1
        attempts=$((attempts + 1))
    done
    [ -f "${file}" ] || fail "timed out waiting for ${file}"
}

mkdir -p \
    "${FIXTURE_ROOT}/script/security" \
    "${FIXTURE_ROOT}/chat2db-community-client/node_modules/.bin" \
    "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-bom" \
    "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/lib" \
    "${FAKE_BIN}" \
    "${STATE_DIR}"

cp "${SOURCE_LAUNCHER}" "${FIXTURE_ROOT}/script/dev-community.sh"
if [ -f "${SOURCE_JBR_MANIFEST}" ]; then
    cp "${SOURCE_JBR_MANIFEST}" "${FIXTURE_ROOT}/script/jbr-runtime-manifest.sh"
    SOURCE_JBR_MANIFEST_PRESENT=true
else
    : >"${FIXTURE_ROOT}/script/jbr-runtime-manifest.sh"
fi
touch "${FIXTURE_ROOT}/chat2db-community-client/node_modules/.bin/umi"
touch "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/chat2db-community.jar"
touch "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/lib/flatlaf-3.6.jar"

cat >"${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-bom/pom.xml" <<'EOF'
<project>
    <properties>
        <jcef.version>122.1.9-gd14e051-chromium-122.0.6261.94-api-1.14</jcef.version>
    </properties>
</project>
EOF
touch "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/chat2db-community.jar"

cat >"${FIXTURE_ROOT}/script/security/init-community-encryption-key.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"${FAKE_BIN}/node" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-e" ]; then
    port="${3:-}"
    if [ -n "${FAKE_PORT_PROBE_ERROR:-}" ]; then
        printf 'error:%s\n' "${FAKE_PORT_PROBE_ERROR}"
    elif [ -n "${FAKE_OCCUPIED_PORT:-}" ] && [ "${port}" = "${FAKE_OCCUPIED_PORT}" ]; then
        printf '%s\n' occupied
    else
        printf '%s\n' free
    fi
    exit 0
fi
echo "${FAKE_NODE_VERSION:-v20.20.2}"
EOF

cat >"${FAKE_BIN}/java" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" -XshowSettings:properties "* ]]; then
    if { [ -z "${FAKE_REQUIRED_JAVA_CWD:-}" ] \
        || [ "${PWD}" = "${FAKE_REQUIRED_JAVA_CWD}" ]; } \
        && [ -n "${FAKE_JAVA_HOME:-}" ]; then
        echo "    java.home = ${FAKE_JAVA_HOME}" >&2
    fi
    echo 'openjdk version "17.0.12"' >&2
    exit 0
fi
if [ "${1:-}" = "--list-modules" ]; then
    printf '%s\n' 'java.base@17.0.12' "${FAKE_JAVA_MODULES:-jcef}"
    exit 0
fi
if [ "${1:-}" = "-version" ]; then
    echo 'openjdk version "17.0.12"' >&2
    exit 0
fi
echo "$$" >"${FAKE_STATE_DIR}/backend.pid"
trap 'touch "${FAKE_STATE_DIR}/backend.stopped"; exit 0' TERM INT
while :; do sleep 1; done
EOF

cat >"${FAKE_BIN}/yarn" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "check" ] && [ "${2:-}" = "--integrity" ]; then
    [ "${FAKE_YARN_INTEGRITY:-valid}" = "valid" ]
    exit $?
fi
if [ "${1:-}" = "install" ] && [ "${2:-}" = "--frozen-lockfile" ]; then
    printf '%s\n' install >>"${FAKE_STATE_DIR}/yarn.calls"
    exit 0
fi
echo "$$" >"${FAKE_STATE_DIR}/client.pid"
(
    trap 'touch "${FAKE_STATE_DIR}/client-child.stopped"; exit 0' TERM INT
    while :; do sleep 1; done
) &
echo "$!" >"${FAKE_STATE_DIR}/client-child.pid"
if [ "${FAKE_YARN_PARENT_EXITS:-false}" = true ]; then
    exit 7
fi
trap 'touch "${FAKE_STATE_DIR}/client.stopped"; exit 0' TERM INT
while :; do sleep 1; done
EOF

cat >"${FAKE_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_LSOF_UNAVAILABLE:-false}" = true ]; then
    exit 127
fi
if [ -n "${FAKE_OCCUPIED_PORT:-}" ] && [[ "$*" == *":${FAKE_OCCUPIED_PORT}"* ]]; then
    exit 0
fi
exit 1
EOF

cat >"${FAKE_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
output=""
url=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output|-o)
            output="${2:-}"
            shift 2
            ;;
        --output=*)
            output=${1#--output=}
            shift
            ;;
        http://*|https://*|file://*)
            url="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ -z "${output}" ] || [ "${output}" = /dev/null ]; then
    exit 0
fi

printf '%s\n' "${url}" >>"${FAKE_STATE_DIR}/curl.urls"
printf '%s\n' download >>"${FAKE_STATE_DIR}/curl.calls"
if [ "${FAKE_CURL_BLOCK:-false}" = true ]; then
    echo "$$" >"${FAKE_STATE_DIR}/curl.pid"
    trap 'touch "${FAKE_STATE_DIR}/curl.stopped"; exit 143' TERM INT
    while :; do sleep 1; done
fi
if [ "${FAKE_CURL_FAIL:-false}" = true ]; then
    exit 22
fi
if [ -z "${FAKE_CURL_ARCHIVE:-}" ] || [ ! -f "${FAKE_CURL_ARCHIVE}" ]; then
    echo "fake curl has no local archive fixture" >&2
    exit 97
fi
mkdir -p "$(dirname "${output}")"
cp "${FAKE_CURL_ARCHIVE}" "${output}"
exit 0
EOF

cat >"${FAKE_BIN}/mvn" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${JAVA_HOME:-}" >"${FAKE_STATE_DIR}/mvn-java-home"
if [ "${1:-}" = "-version" ]; then
    echo 'Apache Maven 3.9.9'
    if [ -n "${FAKE_EXPECTED_MAVEN_JAVA_HOME:-}" ] \
        && [ "${JAVA_HOME:-}" != "${FAKE_EXPECTED_MAVEN_JAVA_HOME}" ]; then
        echo 'Java version: 24.0.1'
    else
        echo 'Java version: 17.0.12'
    fi
    exit 0
fi
printf '%s\n' "$*" >"${FAKE_STATE_DIR}/mvn-args"
touch "${FAKE_STATE_DIR}/mvn.called"
exit 99
EOF

cat >"${FAKE_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -s)
        if [ -n "${FAKE_UNAME_S:-${FAKE_UNAME:-}}" ]; then
            printf '%s\n' "${FAKE_UNAME_S:-${FAKE_UNAME}}"
        else
            /usr/bin/uname -s
        fi
        ;;
    -m)
        if [ -n "${FAKE_UNAME_M:-}" ]; then
            printf '%s\n' "${FAKE_UNAME_M}"
        else
            /usr/bin/uname -m
        fi
        ;;
    *)
        if [ -n "${FAKE_UNAME:-}" ]; then
            printf '%s\n' "${FAKE_UNAME}"
        else
            /usr/bin/uname "$@"
        fi
        ;;
esac
EOF

cat >"${FAKE_BIN}/cygpath" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-u" ] \
    && [ "${2:-}" = "${FAKE_CYGPATH_INPUT:-}" ] \
    && [ -n "${FAKE_CYGPATH_OUTPUT:-}" ]; then
    printf '%s\n' "${FAKE_CYGPATH_OUTPUT}"
    exit 0
fi
exit 1
EOF

chmod +x \
    "${FIXTURE_ROOT}/script/security/init-community-encryption-key.sh" \
    "${FAKE_BIN}/node" \
    "${FAKE_BIN}/java" \
    "${FAKE_BIN}/yarn" \
    "${FAKE_BIN}/lsof" \
    "${FAKE_BIN}/curl" \
    "${FAKE_BIN}/mvn" \
    "${FAKE_BIN}/uname" \
    "${FAKE_BIN}/cygpath"

create_jcef_runtime() {
    local home="$1"

    mkdir -p \
        "${home}/bin" \
        "${home}/lib" \
        "${home}/../Frameworks/Chromium Embedded Framework.framework" \
        "${home}/../Frameworks/Chromium Embedded Framework.framework/Resources" \
        "${home}/../Frameworks/jcef Helper.app/Contents/MacOS" \
        "${home}/../Frameworks/jcef Helper (GPU).app/Contents/MacOS" \
        "${home}/../Frameworks/jcef Helper (Renderer).app/Contents/MacOS" \
        "${home}/lib/locales" \
        "${home}/bin/locales"
    cp "${FAKE_BIN}/java" "${home}/bin/java"
    cp "${FAKE_BIN}/java" "${home}/bin/java.exe"
    touch \
        "${home}/bin/jcef.dll" \
        "${home}/bin/libcef.dll" \
        "${home}/bin/jcef_helper.exe" \
        "${home}/bin/chrome_elf.dll" \
        "${home}/bin/icudtl.dat" \
        "${home}/bin/resources.pak" \
        "${home}/lib/libjcef.dylib" \
        "${home}/lib/libjcef.so" \
        "${home}/lib/libcef.so" \
        "${home}/lib/icudtl.dat" \
        "${home}/lib/resources.pak" \
        "${home}/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" \
        "${home}/../Frameworks/Chromium Embedded Framework.framework/Resources/icudtl.dat" \
        "${home}/../Frameworks/Chromium Embedded Framework.framework/Resources/resources.pak" \
        "${home}/../Frameworks/jcef Helper.app/Contents/MacOS/jcef Helper" \
        "${home}/../Frameworks/jcef Helper (GPU).app/Contents/MacOS/jcef Helper (GPU)" \
        "${home}/../Frameworks/jcef Helper (Renderer).app/Contents/MacOS/jcef Helper (Renderer)"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${home}/lib/jcef_helper"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${home}/lib/chrome-sandbox"
    chmod +x \
        "${home}/bin/java.exe" \
        "${home}/bin/jcef_helper.exe" \
        "${home}/lib/jcef_helper" \
        "${home}/lib/chrome-sandbox" \
        "${home}/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" \
        "${home}/../Frameworks/jcef Helper.app/Contents/MacOS/jcef Helper" \
        "${home}/../Frameworks/jcef Helper (GPU).app/Contents/MacOS/jcef Helper (GPU)" \
        "${home}/../Frameworks/jcef Helper (Renderer).app/Contents/MacOS/jcef Helper (Renderer)"
    printf '%s\n' \
        'JAVA_VERSION="17.0.12"' \
        'MODULES="java.base java.desktop jcef"' \
        'JCEF_VERSION="122.1.9.770+ge9c0b4b"' \
        >"${home}/release"
}

create_packaged_macos_jcef_runtime() {
    local app="$1"
    local home="${app}/Contents/runtime/Contents/Home"
    local packaged_frameworks="${app}/Contents/app/Frameworks"

    create_jcef_runtime "${home}"
    mkdir -p "$(dirname "${packaged_frameworks}")"
    mv "${home}/../Frameworks" "${packaged_frameworks}"
}

create_node_runtime() {
    local home="$1"
    local version="$2"

    mkdir -p "${home}/bin"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        "echo 'v${version}'" \
        >"${home}/bin/node"
    chmod +x "${home}/bin/node"
}

assert_jbr_manifest_artifact() {
    local platform="$1"
    local architecture="$2"
    local expected_archive="$3"
    local expected_sha512="$4"
    local actual

    actual=$(
        unset JBR_RUNTIME_ARCHIVE JBR_RUNTIME_SHA512
        # shellcheck source=/dev/null
        source "${FIXTURE_ROOT}/script/jbr-runtime-manifest.sh"
        resolve_jbr_runtime_artifact "${platform}" "${architecture}"
        printf '%s|%s' "${JBR_RUNTIME_ARCHIVE:-}" "${JBR_RUNTIME_SHA512:-}"
    )
    [ "${actual}" = "${expected_archive}|${expected_sha512}" ] \
        || fail "unexpected JBR manifest artifact for ${platform}/${architecture}: ${actual}"
}

if [ "${SOURCE_JBR_MANIFEST_PRESENT}" = true ]; then
    assert_jbr_manifest_artifact \
        Darwin arm64 \
        jbr_jcef-17.0.12-osx-aarch64-b1207.37.tar.gz \
        de2a297b8acec5d594c13188510d5d29d11cb7e77c1a1eab7f0a566997c0aa1da308a1684f2afc20ac0ab410ac64bd4ce0e8dc92a601615d7b344d59d42c38e0
    assert_jbr_manifest_artifact \
        Darwin x86_64 \
        jbr_jcef-17.0.12-osx-x64-b1207.37.tar.gz \
        b6862741fd4ea1f790d65d66cdd415097978f21f6f1f9b4d2aa5774b2b50408fcad38a8445efe7c405d86825d23dead4325a7ea0fd2298af5a19b4208236952c
    assert_jbr_manifest_artifact \
        Linux aarch64 \
        jbr_jcef-17.0.12-linux-aarch64-b1207.37.tar.gz \
        cc150d66d338363f7d09248ba922b35e3adf4679004ea83e76883a5720860f2d895bd4c6e00f9162ac8880303cafd3cecb65f35a1e495114dfa7618a5e994091
    assert_jbr_manifest_artifact \
        Linux x86_64 \
        jbr_jcef-17.0.12-linux-x64-b1207.37.tar.gz \
        b08796c2d18ff8be6a038f2471ddbcbeaacb03fbac49dc3b6ac61d23db20e7d346834a3a407d4a670f2911b20d435aab74eb4cb1d64fab3ebc6e698a52387020
    assert_jbr_manifest_artifact \
        MSYS_NT-10.0-22631 x86_64 \
        jbr_jcef-17.0.12-windows-x64-b1207.37.tar.gz \
        d0649ff8efab9bd1f682b044c6a5422714e9af75522d86c653ebcbf01c4aaf2595ca8873aa2e3f45207f57408d7d043f3fd1b1e501520d5788836c7ebe897f01
fi

JBR_ARCHIVE_SOURCE="${TEST_ROOT}/jbr-archive-source/test-jbr"
mkdir -p "$(dirname "${JBR_ARCHIVE_SOURCE}")"
create_jcef_runtime "${JBR_ARCHIVE_SOURCE}"
tar -czf "${JBR_ARCHIVE_FIXTURE}" \
    -C "$(dirname "${JBR_ARCHIVE_SOURCE}")" \
    "$(basename "${JBR_ARCHIVE_SOURCE}")"
if command -v sha512sum >/dev/null 2>&1; then
    TEST_JBR_SHA512=$(sha512sum "${JBR_ARCHIVE_FIXTURE}" | awk '{print $1}')
else
    TEST_JBR_SHA512=$(shasum -a 512 "${JBR_ARCHIVE_FIXTURE}" | awk '{print $1}')
fi

# Download tests replace the copied production manifest with tiny local
# artifacts while preserving the same shell interface used by the launcher.
cat >"${FIXTURE_ROOT}/script/jbr-runtime-manifest.sh" <<EOF
#!/usr/bin/env bash

resolve_jbr_runtime_artifact() {
    local platform="\$1"
    local architecture="\$2"

    case "\${platform}:\${architecture}" in
        Darwin:arm64|Darwin:aarch64)
            JBR_RUNTIME_ARCHIVE="test-osx-aarch64.tar.gz"
            ;;
        Darwin:x86_64|Darwin:amd64)
            JBR_RUNTIME_ARCHIVE="test-osx-x64.tar.gz"
            ;;
        Linux:arm64|Linux:aarch64)
            JBR_RUNTIME_ARCHIVE="test-linux-aarch64.tar.gz"
            ;;
        Linux:x86_64|Linux:amd64)
            JBR_RUNTIME_ARCHIVE="test-linux-x64.tar.gz"
            ;;
        MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64)
            JBR_RUNTIME_ARCHIVE="test-windows-x64.tar.gz"
            ;;
        *)
            return 1
            ;;
    esac
    JBR_RUNTIME_SHA512="\${CHAT2DB_TEST_JBR_SHA512:-${TEST_JBR_SHA512}}"
}
EOF

run_launcher --help
[ "${STATUS}" -eq 0 ] || fail "--help exited with ${STATUS}"
assert_contains "${OUTPUT}" "script/dev-community.sh [web|desktop] [--build] [--dry-run]"

run_launcher nonsense
[ "${STATUS}" -eq 2 ] || fail "invalid mode exited with ${STATUS}, expected 2"
assert_contains "${OUTPUT}" "unknown mode: nonsense"

run_launcher web --dry-run
[ "${STATUS}" -eq 0 ] || fail "web dry-run exited with ${STATUS}"
assert_contains "${OUTPUT}" "mode: web"
assert_contains "${OUTPUT}" "-Dchat2db.gui=false"
assert_contains "${OUTPUT}" "-Dchat2db.mode=WEB"
assert_contains "${OUTPUT}" "yarn run start:community:hot"
assert_not_contains "${OUTPUT}" "-Dchat2db.mode=DESKTOP"

FAKE_YARN_INTEGRITY=invalid run_launcher web --dry-run
[ "${STATUS}" -eq 0 ] || fail "web dry-run failed with stale frontend dependencies: ${OUTPUT}"
assert_contains "${OUTPUT}" "frontend dependencies are missing"
assert_contains "${OUTPUT}" "yarn install --frozen-lockfile"

FAKE_NODE_VERSION=$'v22.22.2\r' run_launcher web --dry-run
[ "${STATUS}" -eq 0 ] || fail "web dry-run rejected a CRLF Node.js version: ${OUTPUT}"

mkdir -p "${TEST_ROOT}/plain-jbr/bin"
cp "${FAKE_BIN}/java" "${TEST_ROOT}/plain-jbr/bin/java"
NEVER_DOWNLOAD_CACHE="${TEST_ROOT}/never-download-cache"
rm -f "${STATE_DIR}/curl.calls" "${STATE_DIR}/curl.urls"
CHAT2DB_JBR_DOWNLOAD=never \
CHAT2DB_JBR_CACHE_DIR="${NEVER_DOWNLOAD_CACHE}" \
FAKE_UNAME_S=Linux \
FAKE_UNAME_M=x86_64 \
run_launcher desktop --dry-run
[ "${STATUS}" -ne 0 ] || fail "desktop dry-run accepted a missing JBR_HOME"
assert_contains "${OUTPUT}" "No compatible JBR 17 + JCEF runtime found"
assert_line_count "${STATE_DIR}/curl.calls" 0
assert_path_missing "${NEVER_DOWNLOAD_CACHE}"

DRY_RUN_CACHE="${TEST_ROOT}/dry-run-cache"
rm -f "${STATE_DIR}/curl.calls" "${STATE_DIR}/curl.urls"
CHAT2DB_JBR_DOWNLOAD=auto \
CHAT2DB_JBR_CACHE_DIR="${DRY_RUN_CACHE}" \
CHAT2DB_JBR_BASE_URL="https://fixture.invalid/jbr" \
FAKE_CURL_ARCHIVE="${JBR_ARCHIVE_FIXTURE}" \
FAKE_UNAME_S=Linux \
FAKE_UNAME_M=x86_64 \
run_launcher desktop --dry-run
[ "${STATUS}" -eq 0 ] || fail "desktop dry-run tried to download a missing JBR: ${OUTPUT}"
assert_contains "${OUTPUT}" "test-linux-x64.tar.gz"
assert_contains "${OUTPUT}" "https://fixture.invalid/jbr"
assert_contains "${OUTPUT}" "${DRY_RUN_CACHE}"
assert_line_count "${STATE_DIR}/curl.calls" 0
assert_path_missing "${DRY_RUN_CACHE}"

SLOW_DOWNLOAD_CACHE="${TEST_ROOT}/slow-download-cache"
SLOW_DOWNLOAD_KEY="test-linux-x64-${TEST_JBR_SHA512:0:16}"
rm -f "${STATE_DIR}/curl.calls" "${STATE_DIR}/curl.urls" \
    "${STATE_DIR}/curl.pid" "${STATE_DIR}/curl.stopped"
env -u JBR_HOME -u JAVA_HOME -u CHAT2DB_NODE_HOME -u NODE_HOME \
PATH="${FAKE_BIN}:${PATH}" \
HOME="${TEST_ROOT}/home" \
NVM_DIR="${TEST_ROOT}/home/.nvm" \
CHAT2DB_COMMUNITY_APP="${TEST_ROOT}/missing-community.app" \
CHAT2DB_JBR_DOWNLOAD=auto \
CHAT2DB_JBR_CACHE_DIR="${SLOW_DOWNLOAD_CACHE}" \
CHAT2DB_JBR_BASE_URL="https://fixture.invalid/jbr" \
FAKE_CURL_ARCHIVE="${JBR_ARCHIVE_FIXTURE}" \
FAKE_CURL_BLOCK=true \
FAKE_UNAME_S=Linux \
FAKE_UNAME_M=x86_64 \
FAKE_STATE_DIR="${STATE_DIR}" \
bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop \
    >"${TEST_ROOT}/slow-download.log" 2>&1 &
LAUNCHER_PID=$!
wait_for_file "${STATE_DIR}/curl.pid"
kill -TERM "${LAUNCHER_PID}"
SLOW_EXIT_ATTEMPTS=0
while kill -0 "${LAUNCHER_PID}" 2>/dev/null \
    && [ "${SLOW_EXIT_ATTEMPTS}" -lt 30 ]; do
    sleep 0.1
    SLOW_EXIT_ATTEMPTS=$((SLOW_EXIT_ATTEMPTS + 1))
done
if kill -0 "${LAUNCHER_PID}" 2>/dev/null; then
    kill -TERM "$(cat "${STATE_DIR}/curl.pid")" 2>/dev/null || true
    sleep 1
    kill -KILL "${LAUNCHER_PID}" 2>/dev/null || true
    wait "${LAUNCHER_PID}" 2>/dev/null || true
    LAUNCHER_PID=""
    fail "launcher TERM did not stop an in-progress JBR download"
fi
wait "${LAUNCHER_PID}" 2>/dev/null || true
LAUNCHER_PID=""
wait_for_file "${STATE_DIR}/curl.stopped"
assert_path_missing \
    "${SLOW_DOWNLOAD_CACHE}/.locks/${SLOW_DOWNLOAD_KEY}.lock"
[ -z "$(find "${SLOW_DOWNLOAD_CACHE}" -type f -name '*.part' -print -quit 2>/dev/null || true)" ] \
    || fail "terminated JBR download left a partial archive"

AUTO_DOWNLOAD_CACHE="${TEST_ROOT}/auto-download-cache"
rm -f \
    "${STATE_DIR}/curl.calls" \
    "${STATE_DIR}/curl.urls" \
    "${STATE_DIR}/mvn.called" \
    "${STATE_DIR}/mvn-java-home" \
    "${STATE_DIR}/mvn-args"
CHAT2DB_JBR_DOWNLOAD=auto \
CHAT2DB_JBR_CACHE_DIR="${AUTO_DOWNLOAD_CACHE}" \
CHAT2DB_JBR_BASE_URL="https://fixture.invalid/jbr" \
FAKE_CURL_ARCHIVE="${JBR_ARCHIVE_FIXTURE}" \
FAKE_UNAME_S=Linux \
FAKE_UNAME_M=x86_64 \
run_launcher desktop --build
[ "${STATUS}" -eq 99 ] \
    || fail "desktop did not reach fake Maven after downloading the JBR: ${OUTPUT}"
assert_line_count "${STATE_DIR}/curl.calls" 1
[ "$(cat "${STATE_DIR}/curl.urls")" = \
    "https://fixture.invalid/jbr/test-linux-x64.tar.gz" ] \
    || fail "launcher downloaded an unexpected JBR URL: $(cat "${STATE_DIR}/curl.urls")"
assert_file_exists "${STATE_DIR}/mvn.called"
CACHE_MARKER=$(find "${AUTO_DOWNLOAD_CACHE}" -type f -name .complete -print -quit 2>/dev/null || true)
[ -n "${CACHE_MARKER}" ] || fail "downloaded JBR cache has no completion marker"
CACHED_RELEASE=$(find "${AUTO_DOWNLOAD_CACHE}" -type f -name release -print -quit 2>/dev/null || true)
[ -n "${CACHED_RELEASE}" ] || fail "downloaded JBR cache has no runtime release file"
CACHED_JBR_HOME=$(cd "$(dirname "${CACHED_RELEASE}")" && pwd -P)
assert_contains "${OUTPUT}" "desktop runtime: ${CACHED_JBR_HOME}"
assert_contains "${OUTPUT}" "JBR cache"

rm -f \
    "${STATE_DIR}/curl.calls" \
    "${STATE_DIR}/curl.urls" \
    "${STATE_DIR}/mvn.called" \
    "${STATE_DIR}/mvn-java-home" \
    "${STATE_DIR}/mvn-args"
CHAT2DB_JBR_DOWNLOAD=auto \
CHAT2DB_JBR_CACHE_DIR="${AUTO_DOWNLOAD_CACHE}" \
CHAT2DB_JBR_BASE_URL="https://fixture.invalid/jbr" \
FAKE_CURL_ARCHIVE="${JBR_ARCHIVE_FIXTURE}" \
FAKE_UNAME_S=Linux \
FAKE_UNAME_M=x86_64 \
run_launcher desktop --build
[ "${STATUS}" -eq 99 ] || fail "desktop did not reuse the cached JBR: ${OUTPUT}"
assert_line_count "${STATE_DIR}/curl.calls" 0
assert_file_exists "${STATE_DIR}/mvn.called"
assert_contains "${OUTPUT}" "desktop runtime: ${CACHED_JBR_HOME}"

EXPLICIT_JBR_HOME="${TEST_ROOT}/explicit-jbr/Home"
create_jcef_runtime "${EXPLICIT_JBR_HOME}"
EXPLICIT_JBR_HOME_EXPECTED=$(cd "${EXPLICIT_JBR_HOME}" && pwd -P)
rm -f "${STATE_DIR}/curl.calls" "${STATE_DIR}/curl.urls"
set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JBR_HOME="${EXPLICIT_JBR_HOME}" \
    CHAT2DB_JBR_DOWNLOAD=auto \
    CHAT2DB_JBR_CACHE_DIR="${AUTO_DOWNLOAD_CACHE}" \
    CHAT2DB_JBR_BASE_URL="https://fixture.invalid/jbr" \
    FAKE_CURL_ARCHIVE="${JBR_ARCHIVE_FIXTURE}" \
    FAKE_UNAME_S=Linux \
    FAKE_UNAME_M=x86_64 \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "explicit JBR_HOME did not win over the cache: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${EXPLICIT_JBR_HOME_EXPECTED} (JBR_HOME)"
assert_line_count "${STATE_DIR}/curl.calls" 0

BAD_CHECKSUM_CACHE="${TEST_ROOT}/bad-checksum-cache"
BAD_SHA512=$(printf '0%.0s' {1..128})
rm -f \
    "${STATE_DIR}/curl.calls" \
    "${STATE_DIR}/curl.urls" \
    "${STATE_DIR}/mvn.called"
CHAT2DB_JBR_DOWNLOAD=auto \
CHAT2DB_JBR_CACHE_DIR="${BAD_CHECKSUM_CACHE}" \
CHAT2DB_JBR_BASE_URL="https://fixture.invalid/jbr" \
CHAT2DB_TEST_JBR_SHA512="${BAD_SHA512}" \
FAKE_CURL_ARCHIVE="${JBR_ARCHIVE_FIXTURE}" \
FAKE_UNAME_S=Linux \
FAKE_UNAME_M=x86_64 \
run_launcher desktop --build
[ "${STATUS}" -ne 0 ] || fail "desktop accepted a JBR archive with a bad checksum"
assert_contains "${OUTPUT}" "SHA-512"
assert_line_count "${STATE_DIR}/curl.calls" 1
[ ! -f "${STATE_DIR}/mvn.called" ] || fail "Maven ran after the JBR checksum failed"
[ -z "$(find "${BAD_CHECKSUM_CACHE}" -type f -name .complete -print -quit 2>/dev/null || true)" ] \
    || fail "checksum failure left a valid JBR cache marker"

FAILED_DOWNLOAD_CACHE="${TEST_ROOT}/failed-download-cache"
rm -f \
    "${STATE_DIR}/curl.calls" \
    "${STATE_DIR}/curl.urls" \
    "${STATE_DIR}/mvn.called"
CHAT2DB_JBR_DOWNLOAD=auto \
CHAT2DB_JBR_CACHE_DIR="${FAILED_DOWNLOAD_CACHE}" \
CHAT2DB_JBR_BASE_URL="https://fixture.invalid/jbr" \
FAKE_CURL_ARCHIVE="${JBR_ARCHIVE_FIXTURE}" \
FAKE_CURL_FAIL=true \
FAKE_UNAME_S=Linux \
FAKE_UNAME_M=x86_64 \
run_launcher desktop --build
[ "${STATUS}" -ne 0 ] || fail "desktop ignored a JBR download failure"
assert_contains "${OUTPUT}" "download"
assert_line_count "${STATE_DIR}/curl.calls" 1
[ ! -f "${STATE_DIR}/mvn.called" ] || fail "Maven ran after the JBR download failed"
[ -z "$(find "${FAILED_DOWNLOAD_CACHE}" -type f -name .complete -print -quit 2>/dev/null || true)" ] \
    || fail "download failure left a valid JBR cache marker"

rm -f "${CACHED_JBR_HOME}/lib/resources.pak"
rm -f \
    "${STATE_DIR}/curl.calls" \
    "${STATE_DIR}/curl.urls" \
    "${STATE_DIR}/mvn.called" \
    "${STATE_DIR}/mvn-java-home" \
    "${STATE_DIR}/mvn-args"
CHAT2DB_JBR_DOWNLOAD=auto \
CHAT2DB_JBR_CACHE_DIR="${AUTO_DOWNLOAD_CACHE}" \
CHAT2DB_JBR_BASE_URL="https://fixture.invalid/jbr" \
FAKE_CURL_ARCHIVE="${JBR_ARCHIVE_FIXTURE}" \
FAKE_UNAME_S=Linux \
FAKE_UNAME_M=x86_64 \
run_launcher desktop --build
[ "${STATUS}" -eq 99 ] || fail "desktop did not repair a damaged JBR cache: ${OUTPUT}"
assert_line_count "${STATE_DIR}/curl.calls" 1
assert_file_exists "${CACHED_JBR_HOME}/lib/resources.pak"
assert_file_exists "${CACHE_MARKER}"
assert_file_exists "${STATE_DIR}/mvn.called"

PACKAGED_APP="${TEST_ROOT}/Applications/Chat2DB Community.app"
PACKAGED_JBR_HOME="${PACKAGED_APP}/Contents/runtime/Contents/Home"
PACKAGED_FRAMEWORKS="${PACKAGED_APP}/Contents/app/Frameworks"
create_packaged_macos_jcef_runtime "${PACKAGED_APP}"
PACKAGED_JBR_HOME_EXPECTED=$(cd "${PACKAGED_JBR_HOME}" && pwd -P)
PACKAGED_FRAMEWORKS_EXPECTED=$(cd "${PACKAGED_FRAMEWORKS}" && pwd -P)
set +e
OUTPUT=$(env -u JBR_HOME -u JAVA_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    CHAT2DB_COMMUNITY_APP="${PACKAGED_APP}" \
    FAKE_UNAME="Darwin" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "desktop did not discover the installed Community app runtime: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${PACKAGED_JBR_HOME_EXPECTED} (installed Community app)"
assert_contains "${OUTPUT}" "desktop JCEF Frameworks: ${PACKAGED_FRAMEWORKS_EXPECTED}"

STAGED_JBR_HOME="${FIXTURE_ROOT}/jpackage/input/runtime/mac/Home"
STAGED_FRAMEWORKS="${FIXTURE_ROOT}/jpackage/input/mac/Frameworks"
create_jcef_runtime "${STAGED_JBR_HOME}"
mkdir -p "$(dirname "${STAGED_FRAMEWORKS}")"
mv "${STAGED_JBR_HOME}/../Frameworks" "${STAGED_FRAMEWORKS}"
STAGED_JBR_HOME_EXPECTED=$(cd "${STAGED_JBR_HOME}" && pwd -P)
STAGED_FRAMEWORKS_EXPECTED=$(cd "${STAGED_FRAMEWORKS}" && pwd -P)
CHAT2DB_JBR_DOWNLOAD=never \
FAKE_UNAME=Darwin \
run_launcher desktop --dry-run
[ "${STATUS}" -eq 0 ] || fail "desktop did not discover the staged macOS runtime: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${STAGED_JBR_HOME_EXPECTED} (staged runtime)"
assert_contains "${OUTPUT}" "desktop JCEF Frameworks: ${STAGED_FRAMEWORKS_EXPECTED}"
rm -rf "${FIXTURE_ROOT}/jpackage"

rm -f "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/lib/flatlaf-3.6.jar"
set +e
OUTPUT=$(env -u JBR_HOME -u JAVA_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    CHAT2DB_COMMUNITY_APP="${PACKAGED_APP}" \
    FAKE_UNAME="Darwin" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "desktop dry-run failed while checking missing FlatLaf: ${OUTPUT}"
assert_contains "${OUTPUT}" "building Community backend"
assert_contains "${OUTPUT}" "-Dchat2db.externalLib.excludeArtifactIds=__chat2db_dev_none__"
touch "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/lib/flatlaf-3.6.jar"

set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JBR_HOME="${PACKAGED_JBR_HOME}" \
    CHAT2DB_COMMUNITY_APP="${TEST_ROOT}/missing-community.app" \
    FAKE_UNAME="Darwin" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "desktop rejected a packaged Community JBR_HOME: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${PACKAGED_JBR_HOME_EXPECTED} (JBR_HOME)"
assert_contains "${OUTPUT}" "desktop JCEF Frameworks: ${PACKAGED_FRAMEWORKS_EXPECTED}"

set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    JBR_HOME="${TEST_ROOT}/plain-jbr" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "desktop dry-run accepted a JBR without JCEF"
assert_contains "${OUTPUT}" "JBR_HOME"
assert_contains "${OUTPUT}" "missing"

JBR_HOME_FIXTURE="${TEST_ROOT}/jbr runtime/Contents/Home"
create_jcef_runtime "${JBR_HOME_FIXTURE}"
JBR_HOME_EXPECTED=$(cd "${JBR_HOME_FIXTURE}" && pwd -P)
set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JBR_HOME="${JBR_HOME_FIXTURE}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "desktop dry-run exited with ${STATUS}"
assert_contains "${OUTPUT}" "mode: desktop"
assert_contains "${OUTPUT}" "desktop runtime: ${JBR_HOME_EXPECTED} (JBR_HOME)"
assert_contains "${OUTPUT}" "${JBR_HOME_EXPECTED// /\\ }/bin/java"
assert_contains "${OUTPUT}" "-Dchat2db.gui=true"
assert_contains "${OUTPUT}" "-Dchat2db.mode=DESKTOP"
assert_not_contains "${OUTPUT}" "-Dchat2db.mode=WEB"

INCOMPLETE_JBR="${TEST_ROOT}/incomplete-jbr/Contents/Home"
create_jcef_runtime "${INCOMPLETE_JBR}"
rm -f "${INCOMPLETE_JBR}/../Frameworks/Chromium Embedded Framework.framework/Resources/resources.pak"
set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JBR_HOME="${INCOMPLETE_JBR}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "desktop accepted a JBR with incomplete CEF resources"
assert_contains "${OUTPUT}" "resources.pak"

MODULELESS_JBR="${TEST_ROOT}/moduleless-jbr/Contents/Home"
create_jcef_runtime "${MODULELESS_JBR}"
set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JBR_HOME="${MODULELESS_JBR}" \
    FAKE_JAVA_MODULES="java.desktop@17.0.12" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "desktop accepted a Java runtime without the jcef module"
assert_contains "${OUTPUT}" "jcef module"

MISMATCHED_JBR="${TEST_ROOT}/mismatched-jbr/Contents/Home"
create_jcef_runtime "${MISMATCHED_JBR}"
sed -i.bak 's/JCEF_VERSION=.*/JCEF_VERSION="123.0.0.1+incompatible"/' "${MISMATCHED_JBR}/release"
rm -f "${MISMATCHED_JBR}/release.bak"
set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JBR_HOME="${MISMATCHED_JBR}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "desktop accepted a JBR with an incompatible JCEF ABI"
assert_contains "${OUTPUT}" "JCEF 122.1.9"

JAVA_HOME_FIXTURE="${TEST_ROOT}/java home jbr/Contents/Home"
create_jcef_runtime "${JAVA_HOME_FIXTURE}"
JAVA_HOME_EXPECTED=$(cd "${JAVA_HOME_FIXTURE}" && pwd -P)
set +e
OUTPUT=$(env -u JBR_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JAVA_HOME="${JAVA_HOME_FIXTURE}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "desktop did not discover JAVA_HOME: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${JAVA_HOME_EXPECTED} (JAVA_HOME)"

JENV_RUNTIME="${TEST_ROOT}/real-jbr/Contents/Home"
JENV_SYMLINK="${TEST_ROOT}/jenv/versions/chat2db-jbr17"
create_jcef_runtime "${JENV_RUNTIME}"
JENV_RUNTIME_EXPECTED=$(cd "${JENV_RUNTIME}" && pwd -P)
mkdir -p "$(dirname "${JENV_SYMLINK}")"
ln -s "${JENV_RUNTIME}" "${JENV_SYMLINK}"
set +e
OUTPUT=$(env -u JBR_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JAVA_HOME="${JENV_SYMLINK}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "desktop did not resolve a jenv JAVA_HOME symlink: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${JENV_RUNTIME_EXPECTED} (JAVA_HOME)"

PATH_RUNTIME="${TEST_ROOT}/path-jbr/Contents/Home"
create_jcef_runtime "${PATH_RUNTIME}"
PATH_RUNTIME_EXPECTED=$(cd "${PATH_RUNTIME}" && pwd -P)
set +e
OUTPUT=$(env -u JBR_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JAVA_HOME="${TEST_ROOT}/plain-jbr" \
    FAKE_JAVA_HOME="${PATH_RUNTIME}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "desktop did not fall back to PATH java.home: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${PATH_RUNTIME_EXPECTED} (PATH java.home)"

WINDOWS_PATH_JAVA_INPUT='C:\dev tools\chat2db-path-jbr\Home'
set +e
OUTPUT=$(env -u JBR_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JAVA_HOME="${TEST_ROOT}/plain-jbr" \
    FAKE_JAVA_HOME="${WINDOWS_PATH_JAVA_INPUT}"$'\r' \
    FAKE_UNAME="MSYS_NT-10.0-22631" \
    FAKE_CYGPATH_INPUT="${WINDOWS_PATH_JAVA_INPUT}" \
    FAKE_CYGPATH_OUTPUT="${PATH_RUNTIME}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "desktop did not strip CR from Windows PATH java.home: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${PATH_RUNTIME_EXPECTED} (PATH java.home)"

WINDOWS_JBR_HOME="${TEST_ROOT}/windows-jbr/Home"
WINDOWS_JBR_INPUT='C:\dev tools\chat2db-jbr\Home'
create_jcef_runtime "${WINDOWS_JBR_HOME}"
WINDOWS_JBR_EXPECTED=$(cd "${WINDOWS_JBR_HOME}" && pwd -P)
set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JBR_HOME="${WINDOWS_JBR_INPUT}" \
    FAKE_UNAME="MSYS_NT-10.0-22631" \
    FAKE_CYGPATH_INPUT="${WINDOWS_JBR_INPUT}" \
    FAKE_CYGPATH_OUTPUT="${WINDOWS_JBR_HOME}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "desktop did not normalize a Windows JBR_HOME path: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${WINDOWS_JBR_EXPECTED} (JBR_HOME)"
assert_contains "${OUTPUT}" "${WINDOWS_JBR_EXPECTED// /\\ }/bin/java.exe"

rm -f "${STATE_DIR}/mvn.called" "${STATE_DIR}/mvn-java-home" "${STATE_DIR}/mvn-args"
set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JAVA_HOME="${TEST_ROOT}/plain-jbr" \
    JBR_HOME="${JBR_HOME_FIXTURE}" \
    FAKE_EXPECTED_MAVEN_JAVA_HOME="${JBR_HOME_EXPECTED}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --build 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "fake Maven build unexpectedly succeeded"
[ -f "${STATE_DIR}/mvn.called" ] || fail "desktop build did not invoke Maven"
[ "$(cat "${STATE_DIR}/mvn-java-home")" = "${JBR_HOME_EXPECTED}" ] \
    || fail "desktop Maven build did not use the validated JBR: ${OUTPUT}"
assert_not_contains "${OUTPUT}" "Maven must run with Java 17"
assert_contains "$(cat "${STATE_DIR}/mvn-args")" "-Dchat2db.externalLib.excludeArtifactIds=__chat2db_dev_none__"
rm -f "${STATE_DIR}/mvn.called" "${STATE_DIR}/mvn-java-home" "${STATE_DIR}/mvn-args"

set +e
OUTPUT=$(env -u JBR_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JAVA_HOME="${TEST_ROOT}/plain-jbr" \
    FAKE_JAVA_HOME="${PATH_RUNTIME}" \
    FAKE_EXPECTED_MAVEN_JAVA_HOME="${PATH_RUNTIME_EXPECTED}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" web --build 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "fake Maven build unexpectedly succeeded"
[ -f "${STATE_DIR}/mvn.called" ] || fail "web build did not invoke Maven"
[ "$(cat "${STATE_DIR}/mvn-java-home")" = "${PATH_RUNTIME_EXPECTED}" ] \
    || fail "web Maven build did not use PATH java.home: ${OUTPUT}"
assert_not_contains "${OUTPUT}" "Maven must run with Java 17"
assert_not_contains "$(cat "${STATE_DIR}/mvn-args")" "chat2db.externalLib.excludeArtifactIds"
rm -f "${STATE_DIR}/mvn.called" "${STATE_DIR}/mvn-java-home" "${STATE_DIR}/mvn-args"

OUTSIDE_DIR="${TEST_ROOT}/outside-repository"
mkdir -p "${OUTSIDE_DIR}"
set +e
OUTPUT=$(cd "${OUTSIDE_DIR}" && env -u JBR_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    JAVA_HOME="${TEST_ROOT}/plain-jbr" \
    FAKE_JAVA_HOME="${PATH_RUNTIME}" \
    FAKE_REQUIRED_JAVA_CWD="${FIXTURE_ROOT}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "absolute launcher invocation did not discover the repository jenv runtime: ${OUTPUT}"
assert_contains "${OUTPUT}" "desktop runtime: ${PATH_RUNTIME_EXPECTED} (PATH java.home)"

NODE_HOME_FIXTURE="${TEST_ROOT}/node home"
create_node_runtime "${NODE_HOME_FIXTURE}" "22.22.2"
set +e
OUTPUT=$(env -u JBR_HOME -u JAVA_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/isolated-home" \
    NVM_DIR="${TEST_ROOT}/isolated-home/.nvm" \
    CHAT2DB_NODE_HOME="${NODE_HOME_FIXTURE}" \
    FAKE_NODE_VERSION="v24.15.0" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" web --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "explicit CHAT2DB_NODE_HOME was not used: ${OUTPUT}"
assert_contains "${OUTPUT}" "selected Node.js v22.22.2 from CHAT2DB_NODE_HOME"

WINDOWS_NODE_HOME="${TEST_ROOT}/windows-node"
WINDOWS_NODE_INPUT='C:\Program Files\nodejs'
mkdir -p "${WINDOWS_NODE_HOME}"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    "echo 'v22.22.2'" \
    >"${WINDOWS_NODE_HOME}/node.exe"
chmod +x "${WINDOWS_NODE_HOME}/node.exe"
set +e
OUTPUT=$(env -u JBR_HOME -u JAVA_HOME -u NODE_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/isolated-home" \
    NVM_DIR="${TEST_ROOT}/isolated-home/.nvm" \
    CHAT2DB_NODE_HOME="${WINDOWS_NODE_INPUT}" \
    FAKE_NODE_VERSION="v24.15.0" \
    FAKE_UNAME="MSYS_NT-10.0-22631" \
    FAKE_CYGPATH_INPUT="${WINDOWS_NODE_INPUT}" \
    FAKE_CYGPATH_OUTPUT="${WINDOWS_NODE_HOME}" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" web --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "web did not normalize a Windows CHAT2DB_NODE_HOME path: ${OUTPUT}"
assert_contains "${OUTPUT}" "selected Node.js v22.22.2 from CHAT2DB_NODE_HOME"

NVM_HOME="${TEST_ROOT}/nvm-home"
NVM_NODE_HOME="${NVM_HOME}/runtime"
create_node_runtime "${NVM_NODE_HOME}" "22.22.2"
mkdir -p "${NVM_HOME}"
cat >"${NVM_HOME}/nvm.sh" <<'EOF'
nvm() {
    if [ "${1:-}" = "use" ]; then
        export PATH="${FAKE_NVM_NODE_HOME}/bin:${PATH}"
        return 0
    fi
    return 1
}
EOF
set +e
OUTPUT=$(env -u JBR_HOME -u JAVA_HOME -u CHAT2DB_NODE_HOME -u NODE_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/nvm-user-home" \
    NVM_DIR="${NVM_HOME}" \
    FAKE_NVM_NODE_HOME="${NVM_NODE_HOME}" \
    FAKE_NODE_VERSION="v24.15.0" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" web --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -eq 0 ] || fail "NVM project version was not activated: ${OUTPUT}"
assert_contains "${OUTPUT}" "selected Node.js v22.22.2 from NVM project version"

ASDF_HOME="${TEST_ROOT}/asdf-home"
ASDF_NODE_HOME="${ASDF_HOME}/.asdf/installs/nodejs/22.22.2"
create_node_runtime "${ASDF_NODE_HOME}" "22.22.2"
set +e
OUTPUT=$(env -u JBR_HOME -u JAVA_HOME -u CHAT2DB_NODE_HOME -u NODE_HOME \
    PATH="${FAKE_BIN}:${PATH}" \
    HOME="${ASDF_HOME}" \
    NVM_DIR="${ASDF_HOME}/.nvm" \
    FAKE_NODE_VERSION="v24.15.0" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" web --dry-run 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "launcher scanned an asdf private installation instead of respecting PATH"
assert_contains "${OUTPUT}" "Activate Node.js 22.22.2"

[ "$(tr -d '\r\n' < "${ROOT_DIR}/.node-version")" = "22.22.2" ] \
    || fail ".node-version must pin Node.js 22.22.2"
[ "$(tr -d '\r\n' < "${ROOT_DIR}/.nvmrc")" = "22.22.2" ] \
    || fail ".nvmrc must pin Node.js 22.22.2"
assert_contains "$(cat "${ROOT_DIR}/.tool-versions")" "nodejs 22.22.2"
node -e '
const packageJson = require(process.argv[1]);
if (packageJson.packageManager !== "yarn@1.22.22"
    || packageJson.volta?.node !== "22.22.2"
    || packageJson.volta?.yarn !== "1.22.22") {
  process.exit(1);
}
' "${ROOT_DIR}/chat2db-community-client/package.json" \
    || fail "client package.json must pin the supported Node.js and Yarn versions"

set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    FAKE_OCCUPIED_PORT=10825 \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" web --build 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "launcher started while port 10825 was occupied"
assert_contains "${OUTPUT}" "127.0.0.1:10825 is already in use"
[ ! -f "${STATE_DIR}/mvn.called" ] || fail "Maven ran before the occupied-port check"
[ ! -f "${STATE_DIR}/backend.pid" ] || fail "backend started despite occupied port"
[ ! -f "${STATE_DIR}/client.pid" ] || fail "client started despite occupied port"

rm -f "${STATE_DIR}/mvn.called"
set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    FAKE_LSOF_UNAVAILABLE=true \
    FAKE_OCCUPIED_PORT=10825 \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" web --build 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "launcher started while Node reported port 10825 occupied"
assert_contains "${OUTPUT}" "127.0.0.1:10825 is already in use"
[ ! -f "${STATE_DIR}/mvn.called" ] || fail "Maven ran before the Node port probe"

rm -f "${STATE_DIR}/mvn.called"
set +e
OUTPUT=$(PATH="${FAKE_BIN}:${PATH}" \
    FAKE_PORT_PROBE_ERROR="EACCES:permission denied" \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community.sh" web --build 2>&1)
STATUS=$?
set -e
[ "${STATUS}" -ne 0 ] || fail "launcher ignored an indeterminate Node port probe"
assert_contains "${OUTPUT}" "cannot verify 127.0.0.1:8889: EACCES:permission denied"
[ ! -f "${STATE_DIR}/mvn.called" ] || fail "Maven ran after an indeterminate port probe"

rm -f "${STATE_DIR}"/*.pid "${STATE_DIR}"/*.stopped
env -u JBR_HOME -u JAVA_HOME \
PATH="${FAKE_BIN}:${PATH}" \
HOME="${TEST_ROOT}/home" \
CHAT2DB_COMMUNITY_APP="${PACKAGED_APP}" \
CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE="${TEST_ROOT}/encryption.key" \
FAKE_UNAME="Darwin" \
FAKE_STATE_DIR="${STATE_DIR}" \
bash "${FIXTURE_ROOT}/script/dev-community.sh" desktop >"${TEST_ROOT}/desktop-launcher.log" 2>&1 &
LAUNCHER_PID=$!
wait_for_file "${STATE_DIR}/backend.pid"
wait_for_file "${STATE_DIR}/client.pid"
[ -L "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/Frameworks" ] \
    || fail "desktop did not create the packaged JCEF Frameworks link"
[ "$(readlink "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/Frameworks")" = "${PACKAGED_FRAMEWORKS_EXPECTED}" ] \
    || fail "desktop linked the wrong packaged JCEF Frameworks directory"
kill -TERM "${LAUNCHER_PID}"
wait "${LAUNCHER_PID}" || true
LAUNCHER_PID=""
wait_for_file "${STATE_DIR}/backend.stopped"
wait_for_file "${STATE_DIR}/client.stopped"
wait_for_file "${STATE_DIR}/client-child.stopped"
[ ! -e "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/Frameworks" ] \
    || fail "desktop left its temporary JCEF Frameworks link behind"

PATH="${FAKE_BIN}:${PATH}" \
CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE="${TEST_ROOT}/encryption.key" \
FAKE_STATE_DIR="${STATE_DIR}" \
FAKE_YARN_PARENT_EXITS=true \
bash "${FIXTURE_ROOT}/script/dev-community.sh" web >"${TEST_ROOT}/parent-exit.log" 2>&1 &
LAUNCHER_PID=$!
wait_for_file "${STATE_DIR}/client-child.pid"
wait "${LAUNCHER_PID}" || true
LAUNCHER_PID=""
wait_for_file "${STATE_DIR}/client-child.stopped"

rm -f "${STATE_DIR}"/*.pid "${STATE_DIR}"/*.stopped

PATH="${FAKE_BIN}:${PATH}" \
CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE="${TEST_ROOT}/encryption.key" \
FAKE_STATE_DIR="${STATE_DIR}" \
bash "${FIXTURE_ROOT}/script/dev-community.sh" web >"${TEST_ROOT}/launcher.log" 2>&1 &
LAUNCHER_PID=$!
wait_for_file "${STATE_DIR}/backend.pid"
wait_for_file "${STATE_DIR}/client.pid"
kill -TERM "${LAUNCHER_PID}"
wait "${LAUNCHER_PID}" || true
LAUNCHER_PID=""
wait_for_file "${STATE_DIR}/backend.stopped"
wait_for_file "${STATE_DIR}/client.stopped"
wait_for_file "${STATE_DIR}/client-child.stopped"

[ "${SOURCE_JBR_MANIFEST_PRESENT}" = true ] \
    || fail "missing JBR runtime manifest: ${SOURCE_JBR_MANIFEST}"

echo "[pass] dev-community launcher tests"
