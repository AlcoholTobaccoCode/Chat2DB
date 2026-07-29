# Chat2DB Community Frontend

The Community frontend is built with Umi 4, React, TypeScript, Ant Design 5,
and Zustand. Community behavior is selected with `UMI_ENV=community`.

## Requirements

- Node.js >=18.17 and <19, 20.x, or 22.x (22.22.2 preferred)
- Yarn 1.22.22 using the repository's `yarn.lock`
- The Community backend when running the development server

See the repository [prerequisites](../README.md#prerequisites) for the JDK,
Maven, shell, and Desktop download tools required by the root launcher.

Install dependencies from this directory:

```bash
yarn install --frozen-lockfile
```

Do not generate npm or pnpm lockfiles. The repository maintains only the Yarn
lockfile.

## Development

The preferred entry point is the repository launcher. From the repository root,
run one of these commands:

```bash
./script/dev-community.sh web
./script/dev-community.sh desktop
```

Web mode starts this frontend and the Community Web backend. Desktop mode
starts this frontend and the Community JCEF JVM, which contains its own backend.
Do not start a second backend on port `10825` in Desktop mode.

For manual browser development, start the Community Web backend on
`127.0.0.1:10825`, then run from this directory:

```bash
yarn run start:community:hot
```

The Community development server listens only on `127.0.0.1:8889`. The current
Umi banner may still list a Network URL, but the startup guard keeps the actual
socket loopback-only. If port 8889 is occupied, startup fails instead of
silently selecting another port. Keep the backend and frontend running as
separate processes and open `http://127.0.0.1:8889/`.

React, TypeScript, and style changes in the checkout that started the dev server
are watched automatically. The initial build and large incremental builds can
take several seconds; wait for `[Webpack] Compiled` and confirm the browser
console reports `[webpack] connected.`. A compiled change is still subject to
the current route, component state, and conditional rendering. A dev server
started from another clone does not watch this checkout.

Backend and JCEF Java changes require stopping and restarting the repository
launcher. Use `--build` to force the backend rebuild when needed.

For Desktop development, the launcher starts this frontend and a Community JVM
with `chat2db.mode=DESKTOP` and `spring.profiles.active=dev`. It reuses a
compatible local JBR when available; otherwise it downloads the
repository-pinned JBR 17 with JCEF on macOS arm64/x64, Linux arm64/x64, or
Windows x64, verifies the official SHA-512 checksum, and caches it for later
starts. JCEF then loads the development renderer automatically; do not start a
second Web backend on port `10825`. `CHAT2DB_JBR_DOWNLOAD=never` disables only
the automatic JBR download; Maven or Yarn may still use the network.

Packaged release runtimes keep loading their staged `dist/index.html`.

## Production Build

Build the Community renderer with an explicit public version:

```bash
yarn run build:web:community --app_version=5.3.0
```

The generated renderer is written to `dist/`. For a web or Docker package, the
files are staged under the Spring Boot module at:

```text
../chat2db-community-server/chat2db-community-start/src/main/resources/static/front/
../chat2db-community-server/chat2db-community-start/src/main/resources/thymeleaf/index.html
```

From the repository root, use `./docker/docker-build.sh` to perform the complete
frontend, backend, and image build without manually staging these files.

## Desktop Packaging

The JCEF desktop packaging entry point is repository-local:

```bash
script/package/package-community-jcef.sh 5.3.0 prepare
```

Run it from the repository root. Replace `prepare` with `mac`, `linux`, or `win`
on the matching operating system to build a native installer. Generated inputs
and installers are written under `jpackage/` and are not frontend source files.

## Checks

```bash
yarn run lint
yarn run test:i18n
yarn run test:result-markdown
yarn run test:sql-in-clipboard
```

## Source Conventions

- Prefix TypeScript interfaces and type aliases with `I`.
- Use values from `window._AppThemePack` in JavaScript and CSS variables such
  as `var(--control-item-bg-active)` in styles instead of hard-coded theme
  colors.
- Use keys from `src/i18n/` through `i18n` or `i18nElement`. Placeholders use
  `{1}`, `{2}`, and so on. Spanish and Korean catalogs must keep exact module,
  key, placeholder, and HTML-tag parity with `en-US`; update their source hashes
  whenever the corresponding English wording changes.
