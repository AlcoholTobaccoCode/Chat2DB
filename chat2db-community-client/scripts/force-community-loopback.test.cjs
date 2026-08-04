const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { EventEmitter } = require('node:events');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

//#region Community dev server loopback regression

const preloadPath = path.resolve(__dirname, 'force-community-loopback.cjs');
const packageJson = require('../package.json');

assert.ok(fs.existsSync(preloadPath), 'Community loopback preload must exist');
const {
  guardConfiguredPortSelection,
  isConfiguredPortSelection,
  isUmiDevWorker,
  requireConfiguredPort,
  selectConfiguredLoopbackPort,
  trackChildExitCode,
  withCommunityLoopbackHost,
} = require(preloadPath);
assert.equal(typeof withCommunityLoopbackHost, 'function');
assert.equal(typeof trackChildExitCode, 'function');
assert.match(
  packageJson.scripts['start:community:hot'],
  /node --require=.\/scripts\/force-community-loopback\.cjs \.\/node_modules\/umi\/bin\/umi\.js dev/,
  'Community start must preload the guard without replacing inherited NODE_OPTIONS',
);
assert.doesNotMatch(packageJson.scripts['start:community:hot'], /cross-env NODE_OPTIONS=/);

function parentAuxiliaryListenAddress() {
  const script = `
    const net = require('node:net');
    const server = net.createServer();
    server.listen(0, () => {
      process.stdout.write(server.address().address);
      server.close();
    });
  `;

  return execFileSync(process.execPath, ['-e', script], {
    encoding: 'utf8',
    env: {
      ...process.env,
      HOST: '127.0.0.1',
      NODE_OPTIONS: `--require=${preloadPath}`,
      PORT: '8889',
      UMI_ENV: 'community',
    },
  });
}

assert.ok(
  parentAuxiliaryListenAddress(),
  'The preload must not patch the Umi parent process listener',
);

function availableLoopbackPort() {
  const script = `
    const net = require('node:net');
    const server = net.createServer();
    server.listen(0, '127.0.0.1', () => {
      process.stdout.write(String(server.address().port));
      server.close();
    });
  `;
  return Number(execFileSync(process.execPath, ['-e', script], { encoding: 'utf8' }));
}

function workerListenAddresses() {
  const fixtureDirectory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'chat2db-loopback-'),
  );
  const fixturePath = path.join(fixtureDirectory, 'forkedDev.js');
  const fixture = `
    const net = require('node:net');
    const { portfinder } = require(process.env.CHAT2DB_UMI_UTILS_PATH);

    function listen(server, options) {
      return new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(options, () => {
          server.removeListener('error', reject);
          resolve();
        });
      });
    }

    function close(server) {
      return new Promise((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      });
    }

    (async () => {
      const targetPort = Number(process.env.PORT);
      await portfinder.getPortPromise({ port: targetPort });

      const targetServer = net.createServer();
      const auxiliaryServer = net.createServer();
      await listen(targetServer, { host: '0.0.0.0', port: targetPort });
      await listen(auxiliaryServer, { host: '0.0.0.0', port: 0 });
      process.stdout.write(JSON.stringify({
        target: targetServer.address().address,
        auxiliary: auxiliaryServer.address().address,
      }));
      await Promise.all([close(targetServer), close(auxiliaryServer)]);
    })().catch((error) => {
      console.error(error);
      process.exitCode = 1;
    });
  `;

  fs.writeFileSync(fixturePath, fixture);
  try {
    const output = execFileSync(process.execPath, [fixturePath], {
      encoding: 'utf8',
      env: {
        ...process.env,
        CHAT2DB_UMI_UTILS_PATH: require.resolve('@umijs/utils'),
        NODE_OPTIONS: `--require=${preloadPath}`,
        PORT: String(availableLoopbackPort()),
        UMI_ENV: 'community',
      },
    });
    return JSON.parse(output);
  } finally {
    fs.unlinkSync(fixturePath);
    fs.rmdirSync(fixtureDirectory);
  }
}

assert.deepEqual(workerListenAddresses(), {
  target: '127.0.0.1',
  auxiliary: '0.0.0.0',
});

const callback = () => {};
assert.deepEqual(
  withCommunityLoopbackHost([8889, callback], 8889),
  [8889, '127.0.0.1', callback],
);
assert.deepEqual(
  withCommunityLoopbackHost([8889, '192.0.2.1', callback], 8889),
  [8889, '127.0.0.1', callback],
);
assert.deepEqual(withCommunityLoopbackHost([8890, callback], 8889), [
  8890,
  callback,
]);
assert.deepEqual(withCommunityLoopbackHost([0, callback], 8889), [
  0,
  callback,
]);
assert.deepEqual(
  withCommunityLoopbackHost(
    [{ port: 8889, host: '0.0.0.0', exclusive: true }, callback],
    8889,
  ),
  [{ port: 8889, host: '127.0.0.1', exclusive: true }, callback],
);
assert.deepEqual(
  withCommunityLoopbackHost([{ port: 8890, host: '0.0.0.0' }], 8889),
  [{ port: 8890, host: '0.0.0.0' }],
);
assert.deepEqual(withCommunityLoopbackHost(['/tmp/chat2db.sock'], 8889), [
  '/tmp/chat2db.sock',
]);

assert.equal(isConfiguredPortSelection({ port: 8889 }, 8889), true);
assert.equal(
  isConfiguredPortSelection({ port: 8889, startPort: 8889 }, 8889),
  false,
);
assert.equal(requireConfiguredPort(8889, 8889), 8889);
assert.throws(() => requireConfiguredPort(8890, 8889), /fallback port 8890/);
assert.equal(isUmiDevWorker('/project/node_modules/umi/bin/forkedDev.js'), true);
assert.equal(isUmiDevWorker('/project/node_modules/umi/bin/umi.js'), false);

let fallbackPortfinderCalls = 0;
const fallbackPortfinder = {
  async getPortPromise() {
    fallbackPortfinderCalls += 1;
    return 8890;
  },
};
let fallbackActivated = false;
guardConfiguredPortSelection(
  fallbackPortfinder,
  8889,
  () => {
    fallbackActivated = true;
  },
  async () => 8890,
);

let selectedPortfinderCalls = 0;
const selectedPortfinder = {
  async getPortPromise() {
    selectedPortfinderCalls += 1;
    return 8889;
  },
};
let loopbackActivated = false;
guardConfiguredPortSelection(
  selectedPortfinder,
  8889,
  () => {
    loopbackActivated = true;
  },
  async (port) => port,
);

let hotRestartProbeCalls = 0;
function hotRestartGetPort(options, callback) {
  hotRestartProbeCalls += 1;
  callback(null, options.startPort);
}
const hotRestartPortfinder = {
  getPort: hotRestartGetPort,
  async getPortPromise() {
    return 8889;
  },
};
guardConfiguredPortSelection(hotRestartPortfinder, 8889, () => {});
assert.equal(
  hotRestartPortfinder.getPort,
  hotRestartGetPort,
  'The callback API used by Umi hot restart must remain unwrapped',
);
hotRestartPortfinder.getPort({ startPort: 8889 }, (error, selectedPort) => {
  assert.equal(error, null);
  assert.equal(selectedPort, 8889);
});
assert.equal(hotRestartProbeCalls, 1);

const failedChild = new EventEmitter();
const parentProcess = {};
trackChildExitCode(failedChild, parentProcess);
failedChild.emit('exit', 7, null);
assert.equal(parentProcess.exitCode, 7);

const restartedChild = new EventEmitter();
const restartingParent = {};
trackChildExitCode(restartedChild, restartingParent);
restartedChild.emit('exit', null, 'SIGTERM');
assert.equal(restartingParent.exitCode, undefined);

Promise.all([
  assert.rejects(
    fallbackPortfinder.getPortPromise({ port: 8889 }),
    /fallback port 8890/,
  ),
  selectedPortfinder.getPortPromise({ port: 8889 }),
  selectConfiguredLoopbackPort(availableLoopbackPort()),
])
  .then(([, selectedPort, probedPort]) => {
    assert.equal(fallbackActivated, false);
    assert.equal(fallbackPortfinderCalls, 0);
    assert.equal(selectedPort, 8889);
    assert.equal(selectedPortfinderCalls, 0);
    assert.equal(loopbackActivated, true);
    assert.ok(Number.isInteger(probedPort) && probedPort > 0);
    console.log('Community dev loopback tests passed');
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });

//#endregion
