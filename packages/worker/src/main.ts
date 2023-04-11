import './setup-logger'; // This should be first
import { FetchHandler } from './fetch';
import { LivenessWatcher } from './liveness';
import { MessageHandler } from './message-handler';
import { LocalRealmAdapter } from './local-realm-adapter';
import { Realm, baseRealm, logger } from '@cardstack/runtime-common';
import { Loader } from '@cardstack/runtime-common/loader';
import { RunnerOptionsManager } from '@cardstack/runtime-common/search-index';
import '@cardstack/runtime-common/externals-global';

let log = logger('service-worker:main');
const worker = globalThis as unknown as ServiceWorkerGlobalScope;

const livenessWatcher = new LivenessWatcher(worker);
const fetchHandler = new FetchHandler(livenessWatcher);
const messageHandler = new MessageHandler(worker, fetchHandler);

livenessWatcher.registerShutdownListener(async () => {
  await fetchHandler.dropCaches();
});

// webpack replaces process.env at build time
let resolvedBaseRealmURL = process.env.RESOLVED_BASE_REALM_URL!;
log.info(`service worker resolvedBaseRealmURL=${resolvedBaseRealmURL}`);
Loader.addURLMapping(new URL(baseRealm.url), new URL(resolvedBaseRealmURL));

// TODO: this should be a more event-driven capability driven from the message
// handler
let runnerOptsMgr = new RunnerOptionsManager();
(async () => {
  try {
    let indexResponse = await fetch('./index.html', {
      headers: { Accept: 'text/html' },
    });
    let indexHTML = await indexResponse.text();
    let ownRealmURL = getConfigFromIndexHTML(indexHTML).ownRealmURL;
    await messageHandler.startingUp;
    if (!messageHandler.fs) {
      throw new Error(`could not get FileSystem`);
    }
    let realm = new Realm(
      ownRealmURL,
      new LocalRealmAdapter(messageHandler.fs),
      async (optsId) => {
        let { registerRunner, entrySetter } = runnerOptsMgr.getOptions(optsId);
        await messageHandler.setupIndexRunner(registerRunner, entrySetter);
      },
      runnerOptsMgr,
      async () => {
        let response = await fetch('./index.html', {
          headers: { Accept: 'text/html' },
        });
        return await response.text();
      },
      { isLocalRealm: true }
    );
    fetchHandler.addRealm(realm);
  } catch (err) {
    log.error(err);
  }
})();

worker.addEventListener('install', () => {
  // force moving on to activation even if another service worker had control
  worker.skipWaiting();
});

worker.addEventListener('activate', () => {
  // takes over when there is *no* existing service worker
  worker.clients.claim();
  log.info('activating service worker');
});

worker.addEventListener('fetch', (event: FetchEvent) => {
  event.respondWith(fetchHandler.handleFetch(event.request));
});

// TODO we could do a better job typing this return value--the config types live
// in the host package
function getConfigFromIndexHTML(indexHTML: string) {
  let match = indexHTML.match(
    /<meta name="@cardstack\/host\/config\/environment" content="([^"].*)">/
  );
  let encodedConfig = match?.[1];
  if (!encodedConfig) {
    throw new Error(`Cannot determine config from index.html:\n${indexHTML}`);
  }
  return JSON.parse(decodeURIComponent(encodedConfig));
}
