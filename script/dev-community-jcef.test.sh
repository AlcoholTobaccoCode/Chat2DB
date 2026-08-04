#!/usr/bin/env bash

set -e

fail() {
    echo "[fail] $1" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"

    grep -F -- "${expected}" "${file}" >/dev/null \
        || fail "${file} does not contain: ${expected}"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"

    if grep -F -- "${unexpected}" "${file}" >/dev/null; then
        fail "${file} unexpectedly contains: ${unexpected}"
    fi
}

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

FIXTURE_ROOT="${TEST_ROOT}/repo"
FAKE_BIN="${TEST_ROOT}/bin"
STATE_DIR="${TEST_ROOT}/state"
JBR_HOME_FIXTURE="${TEST_ROOT}/jbr"
mkdir -p \
    "${FIXTURE_ROOT}/script" \
    "${FIXTURE_ROOT}/chat2db-community-client" \
    "${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/lib" \
    "${FAKE_BIN}" \
    "${STATE_DIR}" \
    "${JBR_HOME_FIXTURE}/bin" \
    "${TEST_ROOT}/home"
FIXTURE_ROOT=$(cd "${FIXTURE_ROOT}" && pwd -P)

cp "$(dirname "$0")/dev-community-jcef.sh" \
    "${FIXTURE_ROOT}/script/dev-community-jcef.sh"

cat >"${JBR_HOME_FIXTURE}/bin/java" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${FAKE_STATE_DIR}/java.log"
EOF
cp "${JBR_HOME_FIXTURE}/bin/java" "${JBR_HOME_FIXTURE}/bin/java.exe"

cat >"${FAKE_BIN}/yarn" <<'EOF'
#!/usr/bin/env bash
printf 'cwd=%s\nargs=%s\n' "${PWD}" "$*" >"${FAKE_STATE_DIR}/yarn.log"
trap 'exit 0' TERM INT
while :; do sleep 1; done
EOF

cat >"${FAKE_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
attempts=0
while [ ! -f "${FAKE_STATE_DIR}/yarn.log" ] && [ "${attempts}" -lt 20 ]; do
    attempts=$((attempts + 1))
    sleep 0.05
done
[ -f "${FAKE_STATE_DIR}/yarn.log" ] || exit 1
printf '%s\n' "$*" >"${FAKE_STATE_DIR}/curl.log"
EOF

cat >"${FAKE_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_PLATFORM}"
EOF

chmod +x \
    "${FIXTURE_ROOT}/script/dev-community-jcef.sh" \
    "${JBR_HOME_FIXTURE}/bin/java" \
    "${JBR_HOME_FIXTURE}/bin/java.exe" \
    "${FAKE_BIN}/yarn" \
    "${FAKE_BIN}/curl" \
    "${FAKE_BIN}/uname"

PATH="${FAKE_BIN}:${PATH}" \
HOME="${TEST_ROOT}/home" \
JBR_HOME="${JBR_HOME_FIXTURE}" \
FAKE_PLATFORM=Darwin \
FAKE_STATE_DIR="${STATE_DIR}" \
bash "${FIXTURE_ROOT}/script/dev-community-jcef.sh" >/dev/null 2>&1

assert_contains "${STATE_DIR}/yarn.log" "cwd=${FIXTURE_ROOT}/chat2db-community-client"
assert_contains "${STATE_DIR}/yarn.log" "args=run start:community:hot"
assert_contains "${STATE_DIR}/curl.log" "http://127.0.0.1:8889/"
assert_contains "${STATE_DIR}/java.log" "-Dchat2db.gui=true"
assert_contains "${STATE_DIR}/java.log" "-Dchat2db.mode=DESKTOP"
assert_contains "${STATE_DIR}/java.log" "-Dserver.address=127.0.0.1"
assert_contains "${STATE_DIR}/java.log" "-Dserver.port=10825"
assert_contains "${STATE_DIR}/java.log" "--add-opens=java.desktop/sun.lwawt.macosx=ALL-UNNAMED"
assert_contains "${STATE_DIR}/java.log" "-jar ${FIXTURE_ROOT}/chat2db-community-server/chat2db-community-start/target/chat2db-community.jar"

PATH="${FAKE_BIN}:${PATH}" \
HOME="${TEST_ROOT}/home" \
JBR_HOME="${JBR_HOME_FIXTURE}" \
FAKE_PLATFORM=Linux \
FAKE_STATE_DIR="${STATE_DIR}" \
bash "${FIXTURE_ROOT}/script/dev-community-jcef.sh" >/dev/null 2>&1

assert_not_contains "${STATE_DIR}/java.log" "apple.awt"

rm -f "${STATE_DIR}"/*.log
if PATH="${FAKE_BIN}:${PATH}" \
    HOME="${TEST_ROOT}/home" \
    FAKE_PLATFORM=Linux \
    FAKE_STATE_DIR="${STATE_DIR}" \
    bash "${FIXTURE_ROOT}/script/dev-community-jcef.sh" >/dev/null 2>&1; then
    fail "launcher succeeded without JBR_HOME"
fi
[ ! -e "${STATE_DIR}/yarn.log" ] || fail "frontend started without JBR_HOME"

echo "[pass] Community JCEF development launcher tests"
