# Community Web and Desktop development

This guide is for contributors running Chat2DB Community from source. It does
not change the end-user installation or release startup flow.

## Prerequisites

Install the following tools before using the launcher:

- Java 17 JDK
- Node.js >=18.17 and <19, 20.x, or 22.x; Node.js 22.22.2 is preferred
- Yarn 1.22.22
- Maven 3.8 or later
- Bash 3.2 or later
- `curl`, `tar`, and one SHA-512 tool: `sha512sum`, `shasum`, or `openssl`

Use Git Bash on Windows. The launcher can select an already installed
compatible Node.js version, but it does not install Node.js, Yarn, Maven, or
the other prerequisite command-line tools.

## Start the development environment

Run the launcher from the repository root:

| Goal | Command |
| --- | --- |
| Start the Web backend and frontend dev server | `./script/dev-community.sh` or `./script/dev-community.sh web` |
| Start the JCEF Desktop app and frontend dev server | `./script/dev-community.sh desktop` |
| Force a backend rebuild before startup | Add `--build` |
| Inspect the resolved commands without starting processes | Add `--dry-run` |

The launcher uses these loopback endpoints:

- Frontend: `http://127.0.0.1:8889/`
- Backend: `http://127.0.0.1:10825/`

Both ports must be free before startup. The launcher does not stop or reuse an
unrelated process, and the frontend fails instead of silently selecting a
different port. Stop an existing launcher with `Ctrl+C` before starting one
from another checkout.

On first use, the launcher installs missing frontend dependencies with the
checked-in lockfile, builds a missing or stale backend artifact, and initializes
the local Community encryption key. `Ctrl+C` stops every process started by the
launcher.

The frontend development server listens only on `127.0.0.1`. Umi may still
print a Network URL in its startup banner, but the server is not exposed on LAN
interfaces.

## Web mode

Web mode starts two processes:

1. The Community backend on `127.0.0.1:10825`.
2. The frontend development server on `127.0.0.1:8889`.

Open `http://127.0.0.1:8889/` after the frontend finishes compiling. React,
TypeScript, and style changes are rebuilt automatically.

Java backend changes are not loaded into the running JVM. Stop the launcher and
start it again after changing backend code. Add `--build` when a forced rebuild
is required.

## Desktop mode

Desktop mode starts the frontend development server and one JCEF Desktop
process. The Desktop process contains the backend, so do not start a separate
Web backend at the same time.

In `dev + DESKTOP`, JCEF loads the renderer from
`http://127.0.0.1:8889/`. Release runtimes continue to load the packaged
`dist/index.html`.

The launcher discovers a compatible JBR 17 with JCEF in this order:

1. `JBR_HOME`
2. `JAVA_HOME`
3. The real `java.home` reported by the active PATH Java
4. An installed Chat2DB Community app on macOS
5. A staged project runtime
6. The verified launcher cache

If no compatible runtime is available, the launcher downloads the pinned
JetBrains Runtime for macOS arm64/x64, Linux arm64/x64, or Windows x64. It
verifies the official SHA-512 checksum before using the archive and reuses the
verified cache on later starts.

An explicitly configured but invalid `JBR_HOME` fails immediately. The
following environment variables control automatic discovery and download:

| Variable | Purpose |
| --- | --- |
| `CHAT2DB_JBR_DOWNLOAD=never` | Disable automatic JBR downloads |
| `CHAT2DB_JBR_CACHE_DIR` | Use an absolute custom cache directory |
| `CHAT2DB_JBR_BASE_URL` | Use an HTTPS mirror containing the pinned archives |
| `CHAT2DB_COMMUNITY_APP` | Override the macOS application path used for discovery |
| `CHAT2DB_NODE_HOME` | Select a Node.js installation in a nonstandard layout |

`./script/dev-community.sh desktop --dry-run` prints the resolved runtime,
download plan, and process commands without accessing the network or writing to
the cache.

## Validate a fresh-clone setup

To exercise the automatic JBR download without changing an installed macOS app
or the normal user cache, use a separate clone and a temporary cache:

```bash
CHAT2DB_TEST_JBR_CACHE="$(mktemp -d)"
CHAT2DB_COMMUNITY_APP="/nonexistent/Chat2DB Community.app" \
CHAT2DB_JBR_CACHE_DIR="${CHAT2DB_TEST_JBR_CACHE}" \
./script/dev-community.sh desktop
```

Leave `JBR_HOME` unset and keep a normal Java 17 JDK active when testing the
download path. Remove only the temporary cache after the test.

## Run launcher tests

Run the shell launcher tests from the repository root:

```bash
bash script/dev-community.test.sh
```

Run the frontend loopback tests from the frontend directory:

```bash
cd chat2db-community-client
yarn test:community-dev-loopback
```

## Troubleshooting

### A required port is occupied

Stop the process using `127.0.0.1:8889` or `127.0.0.1:10825`, then run the
launcher again. The launcher intentionally does not kill existing processes or
move to another port.

### Frontend dependencies are incomplete

The launcher checks Yarn dependency integrity and runs
`yarn install --frozen-lockfile` when installation is required. If installation
fails, fix the reported Yarn or network error and retry.

### Desktop cannot find JCEF

Run `./script/dev-community.sh desktop --dry-run` to inspect every runtime
candidate. Confirm that Java is version 17 and that the selected runtime
contains the JCEF module and native resources for the current platform.

### A frontend change does not appear

Wait for `[Webpack] Compiled` in the launcher terminal and confirm the browser
console reports `[webpack] connected.`. Also confirm that the current route and
component state render the code path that changed.
