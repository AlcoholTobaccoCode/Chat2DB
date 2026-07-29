<div align="center">
  <img src="./icon.png" alt="Chat2DB" width="100">
  <div align="center">
  Powered by  <a href="https://ottermind.ai">OtterMind</a>
</div>
  <br/>
  <p><strong>An AI-powered database client and SQL workspace for developers, DBAs, analysts, and data teams.</strong></p>
</div>

<div align="center">
  <a href="./README.md"><img alt="README in English" src="https://img.shields.io/badge/English-d9d9d9"></a>
  <a href="./README_CN.md"><img alt="简体中文版自述文件" src="https://img.shields.io/badge/简体中文-d9d9d9"></a>
  <a href="./README_JA.md"><img alt="日本語のREADME" src="https://img.shields.io/badge/日本語-d9d9d9"></a>
  <a href="./README_ES.md"><img alt="README en español" src="https://img.shields.io/badge/Español-d9d9d9"></a>
  <a href="./README_KO.md"><img alt="한국어 README" src="https://img.shields.io/badge/한국어-d9d9d9"></a>
</div>

## What is Chat2DB?

Chat2DB Community is a free, cross-platform database client for Windows, macOS, and Linux. It runs entirely on your machine and combines a full-featured SQL workspace with an AI assistant that you connect to your own model.

- **30+ databases** — MySQL, PostgreSQL, Oracle, SQL Server, ClickHouse, MongoDB, Redis, SQLite, MariaDB, TiDB, Hive, DB2, Snowflake, BigQuery, Elasticsearch, and more via plugins.
- **SQL workspace** — editing, completion, formatting, execution, saved SQL, and execution history.
- **AI assistant** — bring your own AI model to generate, explain, and optimize SQL in natural language.
- **Database management** — browse metadata, manage tables and objects (DDL/DML), and edit data in place.
- **Data import and export**, **dashboards and charts**, and an **[open-source CLI with MCP support](https://github.com/OtterMind/Chat2DB-CLI)**.

<div align="center">

[![Chat2DB workspace with SQL editor and AI assistant — click to watch the intro video](https://cdn.chat2db-ai.com/website/img/first_video_cover.webp)](https://cdn.chat2db-ai.com/website/video/first_sceen_en.mp4)

</div>

### Screenshots

| Dashboards and charts | ER diagrams |
| --- | --- |
| ![Dashboards and charts](https://cdn.chat2db-ai.com/website/img/bi_dashboard.png) | ![ER diagram](https://cdn.chat2db-ai.com/website/img/er_diagrams.png) |

| Visual data management | Data import and export |
| --- | --- |
| ![Visual data management](https://cdn.chat2db-ai.com/website/img/visual_data_mnagement_en.png) | ![Data import and export](https://cdn.chat2db-ai.com/website/img/import_export_data_en.png) |

## Quick Start

### Option 1: Desktop App

Download the installer for your platform from [GitHub Releases](https://github.com/OtterMind/Chat2DB/releases), install it, and start connecting to your databases. No further setup is required.

### Option 2: Docker

Requirements: Docker 19.03.0+, Docker Compose 2.0.0+ (Compose V2, only for the Compose variant), 2+ CPU cores, 4+ GiB RAM.

First create the encryption key (see [Encryption Key](#encryption-key) for why it matters), then start the container:

```bash
# Run once from a repository checkout. Re-running reuses the same valid key.
git clone https://github.com/OtterMind/Chat2DB.git && cd Chat2DB
./script/security/init-community-encryption-key.sh

docker run --detach \
  --name chat2db-community \
  --restart unless-stopped \
  --publish 127.0.0.1:10825:10825 \
  --volume "$HOME/.chat2db-community-docker:/root/.chat2db-community" \
  --env CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE=/run/secrets/chat2db-community-encryption.key \
  --volume "$HOME/.config/chat2db-community/encryption.key:/run/secrets/chat2db-community-encryption.key:ro" \
  chat2db/chat2db:latest
```

Then open `http://localhost:10825` in your browser.

Alternatively, use the bundled Compose definition:

```bash
./script/security/init-community-encryption-key.sh
docker compose --file docker/docker-compose.yml up --detach
```

Notes:

- To update, pull the new image, remove the old container, and run the start command again. Keep `~/.config/chat2db-community/encryption.key` across rebuilds.
- The `docker run` example stores application data in `$HOME/.chat2db-community-docker`; the Compose definition uses the `chat2db-community-data` named volume. These locations do not share data.
- Chat2DB Community 5.3.0 uses the independent `/root/.chat2db-community` directory and does not automatically migrate data from earlier images that used `/root/.chat2db`.

## Security Notes

Chat2DB Community is a single-user, local-first application. It has no user
accounts or authorization boundaries between users. Keep the HTTP service
bound to `127.0.0.1` or `::1` and do not expose it to other users or
untrusted networks.

Custom JDBC drivers are executable Java code — install them only from
sources you trust. Imported configuration files, archives, SQL files,
database contents, and AI responses remain untrusted data. See the
[Security Policy](SECURITY.md) for the complete trust boundary and
vulnerability reporting process.

If you find this project useful, please give us a Star ⭐️ — it really helps!

<div align="center">
  <a href="https://github.com/OtterMind/Chat2DB"><img src="https://cdn.chat2db.ai/g/Area.gif" alt="Star Chat2DB on GitHub" width="600"></a>
</div>

## Encryption Key

Chat2DB Community encrypts stored datasource passwords and AI model API keys with AES-256-GCM using a per-installation key. Create it once from a repository checkout (requires `openssl`):

```bash
./script/security/init-community-encryption-key.sh
```

The key is written to `~/.config/chat2db-community/encryption.key`. **Back this file up separately and keep it across upgrades and container rebuilds** — replacing or losing it makes previously stored datasource passwords and AI model API keys unreadable. Web/headless startup fails when no valid key is provided; only Desktop mode creates a missing key automatically.

<details>
<summary>Key configuration reference (custom paths, resolution order, validation)</summary>

The key must be valid Base64 that decodes to exactly 32 bytes. The bundled initializer generates the standard padded form: 44 Base64 characters ending in `=`. It is cryptographic key material, not a human-readable password. Datasource passwords and AI API keys use the same key with separate authenticated AAD values, so ciphertext from one purpose cannot be decrypted as the other.

To use a custom path, pass it to the script and configure the same path when starting Chat2DB:

```bash
./script/security/init-community-encryption-key.sh /secure/path/chat2db-community.key

java -Dloader.path=chat2db-community-server/chat2db-community-start/target/lib \
    -Dchat2db.runtime.mode=community \
    -Dchat2db.mode=WEB \
    -Dchat2db.gui=false \
    -Dchat2db.network.status=OFFLINE \
    -Dchat2db.community.encryption-key-file=/secure/path/chat2db-community.key \
    -Dserver.address=127.0.0.1 \
    -Dserver.port=10825 \
    -jar chat2db-community-server/chat2db-community-start/target/chat2db-community.jar
```

The script's key-file path priority is the positional argument, `CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE`, then the default path. It reuses a valid regular file, rejects symbolic links and non-regular files, and refuses to overwrite an invalid file. Keep the key readable only by the Chat2DB process owner.

Key configuration is resolved in this order:

1. JVM property `chat2db.community.encryption-key` containing the Base64 key.
2. Environment variable `CHAT2DB_COMMUNITY_ENCRYPTION_KEY` containing the Base64 key.
3. JVM property `chat2db.community.encryption-key-file` containing a key-file path.
4. Environment variable `CHAT2DB_COMMUNITY_ENCRYPTION_KEY_FILE` containing a key-file path.
5. Default file `~/.config/chat2db-community/encryption.key`.

The first configured value is authoritative. A blank value, malformed Base64, a key that does not decode to 32 bytes, or an invalid key file fails startup instead of falling through to the next source. File-based configuration is recommended because it avoids placing the key value directly in process arguments or environment variables.

Automatic key-file creation depends on `chat2db.mode`, not `chat2db.gui`. Community Desktop mode (`chat2db.runtime.mode=community` with `chat2db.mode=DESKTOP`) creates the selected key file when no inline key is configured and the file is missing. Any non-Desktop mode, including normal Web/headless startup, never creates a missing key and fails until a valid key is provided or initialized. The resolved key is cached for the process lifetime, so changing key configuration requires an application restart.

</details>

## Build from Source

### Prerequisites

- Java 17 JDK: <a href="https://adoptium.net/temurin/releases/?version=17" target="_blank">Eclipse Temurin 17</a>
- Node.js >=18.17 and <19, 20.x, or 22.x (22.22.2 preferred)
- Yarn 1.22.22 using the checked-in lockfile
- Maven 3.8 or later
- Bash 3.2 or later, `curl`, `tar`, and one SHA-512 tool: `sha512sum`, `shasum`, or `openssl` (use Git Bash on Windows)

### Clone the Repository

```bash
git clone https://github.com/OtterMind/Chat2DB.git
cd Chat2DB
```

### One-command Development

Run the launcher from the repository root:

| Goal | Command |
| --- | --- |
| Start the Web backend and frontend dev server | `./script/dev-community.sh` or `./script/dev-community.sh web` |
| Start the JCEF Desktop app and frontend dev server | `./script/dev-community.sh desktop` |
| Force a backend rebuild before startup | Add `--build` |
| Inspect resolved commands without starting processes | Add `--dry-run` |

Both `127.0.0.1:8889` and `127.0.0.1:10825` must be free before startup. The
launcher never stops or reuses an unrelated process, and `--build` does not
restart an existing instance. Stop the previous launcher with `Ctrl+C` before
starting another checkout.

On first use, the launcher installs missing frontend dependencies, builds a
missing or stale backend artifact, and initializes the local Community
encryption key. `Ctrl+C` stops both processes started by the launcher. Use
`./script/dev-community.sh --build` to force a backend rebuild.

The launcher first checks an explicit `JBR_HOME`, `JAVA_HOME`, the real
`java.home` reported by the active PATH Java (covering jenv, asdf, mise, and
SDKMAN), an installed Chat2DB Community.app on macOS, and a staged runtime. If
none contains JCEF, it downloads the pinned JetBrains Runtime for the current
supported platform, verifies JetBrains' official SHA-512 checksum, and keeps it
in the user cache. Automatic downloads support macOS arm64/x64, Linux arm64/x64,
and Windows x64. The first download is approximately 180-205 MiB; later starts
reuse the verified cache. A fresh clone therefore does not require an installed
Chat2DB Community.app or a manually configured `JBR_HOME`. A normal Temurin 17
selected by jenv remains suitable for regular Java development.

`JBR_HOME` remains an explicit override and an invalid value fails immediately.
Set `CHAT2DB_JBR_DOWNLOAD=never` to disable only the automatic JBR download;
a compatible JBR must already be discoverable, and Maven or Yarn may still use
the network. Set
`CHAT2DB_JBR_CACHE_DIR` to an absolute custom cache path, or
`CHAT2DB_JBR_BASE_URL` to an HTTPS mirror serving the exact pinned archives.
Windows Git Bash accepts normal `C:\...` paths. The launcher validates Java 17,
the JCEF module, the project JCEF version, and native resources before startup.
`./script/dev-community.sh desktop --dry-run` only prints the resolved cache,
download, and process commands; it performs no network or cache writes. The
Desktop process contains the backend, so the launcher does not start a second
Web backend in this mode.

The repository's `.node-version`, `.nvmrc`, `.tool-versions`, and Volta settings
pin the preferred Node.js 22.22.2. Activated Node.js >=18.17 and <19, 20.x, and
22.x are supported; Node.js 24 is incompatible with the current Umi toolchain.
Set `CHAT2DB_NODE_HOME` only for a nonstandard installation layout.
The launcher can select an already installed compatible Node.js version, but it
does not install Node.js, Yarn, Maven, or the other prerequisite command-line
tools.

#### Reload behavior

The browser and JCEF Desktop app both load the renderer from
`http://127.0.0.1:8889/` during development. React, TypeScript, and style changes
inside the checkout that started the launcher are watched automatically. The
initial Webpack build and a large incremental rebuild can take several seconds;
wait for `[Webpack] Compiled` in the launcher terminal and confirm the browser
console reports `[webpack] connected.` before diagnosing a reload failure.

A successful rebuild does not bypass React routing, component state, or
conditional rendering. When a temporary UI marker is compiled but not visible,
confirm that the current page and state render the branch that contains it. If
using a second clone to simulate a fresh computer, edit that clone while its
launcher is running; the primary checkout is not watched by the second clone.

Java backend and JCEF changes are not reloaded into the running JVM. Stop the
launcher with `Ctrl+C` and start it again. Newer backend sources are rebuilt
automatically; add `--build` when a clean forced rebuild is required.

#### Fresh-clone validation

A fresh clone does not require an installed Chat2DB Community app or a manually
downloaded JBR. To exercise the automatic JBR download without deleting an
installed macOS app or the normal user cache, use a separate clone, a dedicated
empty cache directory, and a deliberately missing app path:

```bash
CHAT2DB_TEST_JBR_CACHE="$(mktemp -d)"
CHAT2DB_COMMUNITY_APP="/nonexistent/Chat2DB Community.app" \
CHAT2DB_JBR_CACHE_DIR="${CHAT2DB_TEST_JBR_CACHE}" \
./script/dev-community.sh desktop
```

Leave `JBR_HOME` unset and use a normal Java 17 JDK when the purpose of the test
is to verify the download path. The dedicated cache can be removed after the
test; the installed app, normal JBR cache, primary checkout, and application
data do not need to be changed. This validates clone bootstrap, dependency
preparation, JBR download, and process startup; it intentionally does not
simulate an empty Chat2DB user-data directory.

### Manual Frontend Startup

Use Yarn with the checked-in lockfile.

```bash
cd Chat2DB/chat2db-community-client
yarn install --frozen-lockfile
yarn run start:community:hot
```

The Community development server listens on `127.0.0.1:8889`. The current Umi
banner may still list a Network URL, but the startup guard keeps the actual
socket loopback-only. If port 8889 is occupied, startup fails instead of
silently selecting another port.

### Manual Backend Startup

```bash
cd Chat2DB
mvn -B clean package -Dmaven.test.skip=true -Dchat2db.finalName=chat2db-community \
    -f chat2db-community-server/pom.xml \
    -pl chat2db-community-start -am
./script/security/init-community-encryption-key.sh
java -Dloader.path=chat2db-community-server/chat2db-community-start/target/lib \
    -Dchat2db.gui=false \
    -Dchat2db.runtime.mode=community \
    -Dchat2db.mode=WEB \
    -Dchat2db.network.status=OFFLINE \
    -Dchat2db.community.encryption-key-file="$HOME/.config/chat2db-community/encryption.key" \
    -Dserver.address=127.0.0.1 \
    -Dserver.port=10825 \
    -Dspring.profiles.active=dev \
    -jar chat2db-community-server/chat2db-community-start/target/chat2db-community.jar
```

For browser development, keep the frontend and backend commands running as two
separate processes, then open `http://127.0.0.1:8889/`.

### Desktop Development (JCEF)

Use the launcher for Desktop development. It starts the frontend development
server, verifies the required Desktop dependencies, and adapts both complete
JBR archives and the split JBR/JCEF layout used by an installed macOS app. Do
not also start the Web backend: the Desktop process owns `127.0.0.1:10825`
itself.

```bash
./script/dev-community.sh desktop
```

Desktop JVM flags and JCEF layouts differ by platform, so a static manual Java
command is not a launcher-equivalent fallback. Run
`./script/dev-community.sh desktop --dry-run` to inspect the exact command for
the current machine. If launching that command manually, start
`yarn run start:community:hot` first and wait for `127.0.0.1:8889` to become
ready.

In `dev + DESKTOP`, JCEF automatically loads `http://127.0.0.1:8889/`.
Release runtimes continue to load the packaged `dist/index.html`.

### Build a Local Docker Image

```bash
./docker/docker-build.sh 5.3.0 chat2db/chat2db:5.3.0
```

## Database guides

Step-by-step guides for connecting Chat2DB Community to specific databases:

- [BigQuery](./docs/guides/bigquery.md) — Google BigQuery via a Google Cloud service account.

## Community vs Commercial Editions

The Community edition contains the full local database client described above, including custom AI model support. The commercial Pro and Enterprise editions build on the same core and add hosted AI services, user accounts, cloud storage and multi-device sync, and team collaboration and governance features. See [chat2db.ai](https://chat2db.ai) for details.

## Contributing

We welcome bug reports, feature requests, documentation improvements, testing feedback, and pull requests from the community.

Before opening an issue or submitting a pull request, please read our [Contributing Guide](./CONTRIBUTING.md). It explains how to report bugs, suggest improvements, and make contributions easier for maintainers to review.

- For bugs and feature requests, please use [GitHub Issues](https://github.com/OtterMind/Chat2DB/issues).
- For questions, setup help, and open-ended discussions, please use [GitHub Discussions](https://github.com/OtterMind/Chat2DB/discussions).
- If your pull request is related to an issue, please link it in the PR description.

## Community and Support

- GitHub Issues: [report a bug or request a feature](https://github.com/OtterMind/Chat2DB/issues)
- GitHub Discussions: [ask questions and share ideas](https://github.com/OtterMind/Chat2DB/discussions)
- Discord: [join our Discord server](https://discord.gg/uNjb3n5JVN)
- Email: Chat2DB@ch2db.com

## Acknowledgments

Thanks to everyone who has contributed to Chat2DB.

<a href="https://github.com/OtterMind/Chat2DB/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=OtterMind/Chat2DB" alt="Chat2DB contributors" />
</a>

## License

Chat2DB Community version 5.3.0 and later is available under the
[license terms in this repository](./LICENSE). This is a source-available
license based on the Apache License 2.0 with additional conditions. Chat2DB
releases published before version 5.3.0, including version 0.3.7 and the
earlier historical tags, remain under the Apache License 2.0.
