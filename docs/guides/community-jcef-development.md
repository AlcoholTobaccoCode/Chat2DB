# Community Web frontend with JCEF backend

This guide is for contributors who can already build and run the Community Web
frontend and backend, and need to test the same checkout in the JCEF Desktop
shell.

The launcher does not prepare the development environment. It does not install
dependencies, build the backend, discover Java runtimes, or check ports.

## Prerequisites

Before starting JCEF Desktop:

1. Install the project dependencies and build the Community backend by following
   the main README.
2. Set `JBR_HOME` to a JBR 17 runtime that contains JCEF.
3. Ensure `127.0.0.1:8889` and `127.0.0.1:10825` are free.
4. Stop the Web backend, because JCEF Desktop starts its embedded backend on
   `127.0.0.1:10825`.

The launcher expects the previously built backend at:

```text
chat2db-community-server/chat2db-community-start/target/chat2db-community.jar
chat2db-community-server/chat2db-community-start/target/lib/
```

## Start the Web frontend and JCEF backend

From the repository root, run:

```bash
JBR_HOME=/path/to/jbr ./script/dev-community-jcef.sh
```

The script starts the Community Web frontend with
`yarn run start:community:hot`, waits until `http://127.0.0.1:8889/` responds,
and then starts the JCEF backend with `-Dchat2db.jcef.web-frontend=true`.
That parameter tells JCEF to load the Web frontend instead of packaged frontend
files. The script does not start a separate Web backend.

Press `Ctrl+C` to stop both processes. Missing dependencies, build artifacts,
and runtime files are reported by Yarn, curl, or Java. Port availability remains
a prerequisite and is not diagnosed by the launcher.

Without `-Dchat2db.jcef.web-frontend=true`, JCEF continues to load the bundled
`dist/index.html`. Packaged releases do not pass this parameter and are
unchanged.
