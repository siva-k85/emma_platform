#!/usr/bin/env node
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');

const log = (message = '') => process.stdout.write(`${message}\n`);
const fatal = (message) => {
  console.error(`\n✖ ${message}`);
  process.exit(1);
};

const parseEnvFile = (envPath) => {
  if (!existsSync(envPath)) {
    return {};
  }
  return readFileSync(envPath, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'))
    .reduce((acc, line) => {
      const eq = line.indexOf('=');
      if (eq === -1) return acc;
      const key = line.slice(0, eq).trim();
      const value = line.slice(eq + 1).trim();
      acc[key] = value;
      return acc;
    }, {});
};

const runFirebase = (args, { parseJson = true } = {}) => {
  const output = execFileSync('firebase', args, {
    cwd: repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  }).trim();
  if (!parseJson) {
    return output;
  }
  try {
    return JSON.parse(output);
  } catch (error) {
    fatal(`Failed to parse JSON from: firebase ${args.join(' ')}\n${output}`);
    return null;
  }
};

const formatDiff = (expected, actual) => {
  return `expected=${JSON.stringify(expected)} actual=${JSON.stringify(actual)}`;
};

const main = () => {
  const configPath = path.join(repoRoot, 'config/firebase.project.json');
  if (!existsSync(configPath)) {
    fatal(`Missing config file at ${configPath}`);
  }

  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  const envPath = path.join(repoRoot, '.env.local');
  const env = parseEnvFile(envPath);

  const projectId = process.env.PROJECT_ID
    || config?.project?.id
    || env.FIREBASE_PROJECT_ID;

  if (!projectId) {
    fatal('Unable to determine Firebase project ID. Set PROJECT_ID env var or populate config/web env.');
  }

  log(`▶ Using project: ${projectId}`);

  const appsList = runFirebase(['apps:list', '--project', projectId, '--json']);
  const webApp = appsList?.result?.find((app) => app.platform === 'WEB');
  if (!webApp) {
    fatal('No WEB app found in project. Create one via firebase apps:create web');
  }

  const appId = env.FIREBASE_APP_ID || config?.webConfig?.appId || webApp.appId;
  log(`▶ Validating WEB app ID: ${appId}`);
  if (!appId) {
    fatal('Missing FIREBASE_APP_ID in .env.local or config/webConfig.');
  }

  const sdkConfigResponse = runFirebase([
    'apps:sdkconfig',
    'web',
    appId,
    '--project',
    projectId,
    '--json'
  ]);

  const sdkConfig = sdkConfigResponse?.sdkConfig || sdkConfigResponse?.result?.sdkConfig;
  if (!sdkConfig) {
    fatal('Unable to retrieve SDK config from Firebase CLI.');
  }

  const checks = [];

  const ensureMatch = (label, expected, actual) => {
    const pass = expected === actual;
    checks.push({ label, pass, details: pass ? '' : formatDiff(expected, actual) });
  };

  ensureMatch('API key', config.webConfig.apiKey, sdkConfig.apiKey);
  ensureMatch('Auth domain', config.webConfig.authDomain, sdkConfig.authDomain);
  ensureMatch('Project ID', config.webConfig.projectId, sdkConfig.projectId);
  ensureMatch('Storage bucket', config.webConfig.storageBucket, sdkConfig.storageBucket);
  ensureMatch('Sender ID', config.webConfig.messagingSenderId, sdkConfig.messagingSenderId);
  ensureMatch('App ID', config.webConfig.appId, sdkConfig.appId);
  ensureMatch('Measurement ID', config.webConfig.measurementId || '', sdkConfig.measurementId || '');

  const vapidKeys = config?.fcm?.webPush?.vapidKeys ?? [];
  const envExpectations = {
    FIREBASE_API_KEY: config.webConfig.apiKey,
    FIREBASE_AUTH_DOMAIN: config.webConfig.authDomain,
    FIREBASE_PROJECT_ID: projectId,
    FIREBASE_STORAGE_BUCKET: config.webConfig.storageBucket,
    FIREBASE_MESSAGING_SENDER_ID: config.webConfig.messagingSenderId,
    FIREBASE_APP_ID: config.webConfig.appId,
    FIREBASE_MEASUREMENT_ID: config.webConfig.measurementId
  };

  Object.entries(envExpectations).forEach(([key, expected]) => {
    const actual = env[key];
    const label = `.env.local -> ${key}`;
    if (!actual) {
      checks.push({ label, pass: false, details: 'missing' });
      return;
    }
    if (expected && expected !== actual) {
      checks.push({ label, pass: false, details: formatDiff(expected, actual) });
    } else {
      checks.push({ label, pass: true, details: '' });
    }
  });

  {
    const label = '.env.local -> FIREBASE_VAPID_PUBLIC_KEY';
    const actual = env.FIREBASE_VAPID_PUBLIC_KEY;
    if (!actual) {
      checks.push({ label, pass: false, details: 'missing' });
    } else if (vapidKeys.length && !vapidKeys.some((key) => key.publicKey === actual)) {
      checks.push({ label, pass: false, details: `value not found in config.fcm.webPush.vapidKeys (${actual})` });
    } else {
      checks.push({ label, pass: true, details: '' });
    }
  }

  const remoteIndexes = runFirebase(['firestore:indexes', '--project', projectId], { parseJson: true });
  const remoteIndexArray = remoteIndexes?.indexes ?? [];

  const localIndexes = config?.firestore?.indexes ?? [];
  const serializeIndexes = (indexes) => JSON.stringify(indexes, null, 2);

  ensureMatch('Firestore indexes', serializeIndexes(localIndexes), serializeIndexes(remoteIndexArray));

  const rulesPath = path.join(repoRoot, 'firestore.rules');
  if (!existsSync(rulesPath)) {
    checks.push({ label: 'firestore.rules present', pass: false, details: 'file missing' });
  } else {
    const localRules = readFileSync(rulesPath, 'utf8').trim();
    const configRules = (config?.firestore?.rules?.text || '').trim();
    ensureMatch('Firestore rules match config', configRules, localRules);
  }

  const failed = checks.filter((item) => !item.pass);
  log('\nVerification summary:');
  checks.forEach(({ label, pass, details }) => {
    log(`${pass ? '✔' : '✖'} ${label}${details ? ` (${details})` : ''}`);
  });

  if (failed.length) {
    fatal(`${failed.length} check(s) failed. Inspect details above.`);
  }

  log('\nAll checks passed.');
};

try {
  main();
} catch (error) {
  fatal(error.message || String(error));
}
