import { FetchHandler } from './fetch';
import { LivenessWatcher } from './liveness';
import { MessageHandler } from './message-handler';
import { LocalRealm } from './local-realm';

const worker = globalThis as unknown as ServiceWorkerGlobalScope;

const livenessWatcher = new LivenessWatcher(worker);
const messageHandler = new MessageHandler(worker);
const fetchHandler = new FetchHandler(livenessWatcher, messageHandler);

// TODO: this should be a more event-driven capability driven from the message
// handler
(async () => {
  try {
    await messageHandler.startingUp;
    if (!messageHandler.fs) {
      throw new Error(`could not get FileSystem`);
    }
    fetchHandler.addRealm(new LocalRealm(messageHandler.fs));
  } catch (err) {
    console.log(err);
  }
})();

worker.addEventListener('install', () => {
  // force moving on to activation even if another service worker had control
  worker.skipWaiting();
});

worker.addEventListener('activate', () => {
  // takes over when there is *no* existing service worker
  worker.clients.claim();
  console.log('activating service worker');
});

worker.addEventListener('fetch', (event: FetchEvent) => {
  event.respondWith(fetchHandler.handleFetch(event.request));
});
