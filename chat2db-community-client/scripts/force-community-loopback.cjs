const childProcess = require('node:child_process');
const net = require('node:net');
const path = require('node:path');

//#region Community dev server loopback guard

const originalListen = net.Server.prototype.listen;
const originalFork = childProcess.fork;
const targetPort = Number(process.env.PORT);
const loopbackHost = '127.0.0.1';

function trackChildExitCode(child, parentProcess = process) {
  child.once('exit', (code) => {
    if (Number.isInteger(code) && code !== 0) {
      parentProcess.exitCode = code;
    }
  });
  return child;
}

function withCommunityLoopbackHost(args, port) {
  const listenArgs = [...args];
  const options = listenArgs[0];

  if (
    options &&
    typeof options === 'object' &&
    !Array.isArray(options) &&
    Number(options.port) === port
  ) {
    listenArgs[0] = { ...options, host: loopbackHost };
    return listenArgs;
  }

  if (typeof options !== 'number' || options !== port) {
    return listenArgs;
  }

  if (typeof listenArgs[1] === 'string') {
    listenArgs[1] = loopbackHost;
  } else {
    listenArgs.splice(1, 0, loopbackHost);
  }

  return listenArgs;
}

function isConfiguredPortSelection(options, port) {
  return (
    options &&
    typeof options === 'object' &&
    options.startPort === undefined &&
    Number(options.port) === port
  );
}

function requireConfiguredPort(selectedPort, port) {
  if (Number(selectedPort) !== port) {
    throw new Error(
      `Community dev server requires ${loopbackHost}:${port}; refusing Umi fallback port ${selectedPort}`,
    );
  }
  return selectedPort;
}

function guardConfiguredPortSelection(portfinder, port, onSelected) {
  const originalGetPortPromise = portfinder.getPortPromise;
  let selectionPending = true;

  portfinder.getPortPromise = async function getConfiguredPort(options) {
    const guardSelection =
      selectionPending && isConfiguredPortSelection(options, port);
    if (guardSelection) {
      selectionPending = false;
    }

    const selectedPort = await originalGetPortPromise.call(this, options);
    if (guardSelection) {
      requireConfiguredPort(selectedPort, port);
      onSelected();
    }
    return selectedPort;
  };
}

function isUmiDevWorker(entrypoint = process.argv[1]) {
  return path.basename(String(entrypoint || '')) === 'forkedDev.js';
}

if (
  process.env.UMI_ENV === 'community' &&
  Number.isInteger(targetPort) &&
  targetPort > 0 &&
  targetPort <= 65535
) {
  childProcess.fork = function forkWithUmiExitCode(modulePath, ...args) {
    const child = originalFork.call(this, modulePath, ...args);
    return path.basename(String(modulePath)) === 'forkedDev.js'
      ? trackChildExitCode(child)
      : child;
  };

  if (isUmiDevWorker()) {
    let configuredPortSelected = false;
    net.Server.prototype.listen = function listenOnCommunityLoopback(...args) {
      const listenArgs = configuredPortSelected
        ? withCommunityLoopbackHost(args, targetPort)
        : args;
      return originalListen.apply(this, listenArgs);
    };

    const { portfinder } = require('@umijs/utils');
    guardConfiguredPortSelection(portfinder, targetPort, () => {
      configuredPortSelected = true;
    });
  }
}

module.exports = {
  guardConfiguredPortSelection,
  isConfiguredPortSelection,
  isUmiDevWorker,
  requireConfiguredPort,
  trackChildExitCode,
  withCommunityLoopbackHost,
};

//#endregion
