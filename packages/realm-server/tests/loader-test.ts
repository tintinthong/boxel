import { module, test } from 'qunit';
import {
  Loader,
  VirtualNetwork,
  type Realm,
  fetcher,
  maybeHandleScopedCSSRequest,
} from '@cardstack/runtime-common';
import { dirSync, setGracefulCleanup, DirResult } from 'tmp';
import {
  createRealm,
  setupBaseRealmServer,
  runTestRealmServer,
  setupDB,
} from './helpers';
import { copySync } from 'fs-extra';
import { shimExternals } from '../lib/externals';
import { Server } from 'http';
import { join } from 'path';

setGracefulCleanup();

const testRealmURL = new URL('http://127.0.0.1:4444/');
const testRealmHref = testRealmURL.href;

module('loader', function (hooks) {
  let dir: DirResult;
  let testRealmServer: Server;

  let virtualNetwork = new VirtualNetwork();
  shimExternals(virtualNetwork);

  function createLoader() {
    let fetch = fetcher(virtualNetwork.fetch, [
      async (req, next) => {
        return (await maybeHandleScopedCSSRequest(req)) || next(req);
      },
    ]);
    return new Loader(fetch, virtualNetwork.resolveImport);
  }

  setupBaseRealmServer(hooks, virtualNetwork);

  hooks.before(async function () {
    dir = dirSync();
    copySync(join(__dirname, 'cards'), dir.name);
  });

  setupDB(hooks, {
    before: async (dbAdapter, queue) => {
      ({ testRealmServer } = await runTestRealmServer({
        virtualNetwork,
        dir: dir.name,
        realmURL: testRealmURL,
        dbAdapter,
        queue,
      }));
    },
    after: async () => {
      testRealmServer.close();
    },
  });

  test('can dynamically load modules with cycles', async function (assert) {
    let loader = createLoader();
    let module = await loader.import<{ three(): number }>(
      `${testRealmHref}cycle-two`,
    );
    assert.strictEqual(module.three(), 3);
  });

  test('can resolve multiple import load races against a common dep', async function (assert) {
    let loader = createLoader();
    let a = loader.import<{ a(): string }>(`${testRealmHref}a`);
    let b = loader.import<{ b(): string }>(`${testRealmHref}b`);
    let [aModule, bModule] = await Promise.all([a, b]);
    assert.strictEqual(aModule.a(), 'abc', 'module executed successfully');
    assert.strictEqual(bModule.b(), 'bc', 'module executed successfully');
  });

  test('can resolve a import deadlock', async function (assert) {
    let loader = createLoader();
    let a = loader.import<{ a(): string }>(`${testRealmHref}deadlock/a`);
    let b = loader.import<{ b(): string }>(`${testRealmHref}deadlock/b`);
    let c = loader.import<{ c(): string }>(`${testRealmHref}deadlock/c`);
    let [aModule, bModule, cModule] = await Promise.all([a, b, c]);
    assert.strictEqual(aModule.a(), 'abcd', 'module executed successfully');
    assert.strictEqual(bModule.b(), 'bcd', 'module executed successfully');
    assert.strictEqual(cModule.c(), 'cd', 'module executed successfully');
  });

  test('can determine consumed modules', async function (assert) {
    let loader = createLoader();
    await loader.import<{ a(): string }>(`${testRealmHref}a`);
    assert.deepEqual(await loader.getConsumedModules(`${testRealmHref}a`), [
      `${testRealmHref}b`,
      `${testRealmHref}c`,
    ]);
  });

  test('can get consumed modules within a cycle', async function (assert) {
    let loader = createLoader();
    await loader.import<{ three(): number }>(`${testRealmHref}cycle-two`);
    let modules = await loader.getConsumedModules(`${testRealmHref}cycle-two`);
    assert.deepEqual(modules, [`${testRealmHref}cycle-one`]);
  });

  test('supports identify API', async function (assert) {
    let loader = createLoader();
    let { Person } = await loader.import<{ Person: unknown }>(
      `${testRealmHref}person`,
    );
    assert.deepEqual(loader.identify(Person), {
      module: `${testRealmHref}person`,
      name: 'Person',
    });
    // The loader knows which loader instance was used to import the card
    assert.deepEqual(Loader.identify(Person), {
      module: `${testRealmHref}person`,
      name: 'Person',
    });
  });

  test('exports cannot be mutated', async function (assert) {
    let loader = createLoader();
    let module = await loader.import<{ Person: unknown }>(
      `${testRealmHref}person`,
    );
    assert.throws(() => {
      module.Person = 1;
    }, /modules are read only/);
  });

  test('can get a loader used to import a specific card', async function (assert) {
    let loader = createLoader();
    let module = await loader.import<any>(`${testRealmHref}person`);
    let card = module.Person;
    let testingLoader = Loader.getLoaderFor(card);
    assert.strictEqual(testingLoader, loader, 'the loaders are the same');
  });

  module('with a different realm', function (hooks) {
    let loader2: Loader;
    let realm: Realm;

    hooks.before(async function () {
      dir = dirSync();
      copySync(join(__dirname, 'cards'), dir.name);
      shimExternals(virtualNetwork);
    });

    setupDB(hooks, {
      before: async (dbAdapter, queue) => {
        loader2 = createLoader();
        realm = await createRealm({
          dir: dir.name,
          fileSystem: {
            'foo.js': `
          export function checkImportMeta() { return import.meta.url; }
          export function myLoader() { return import.meta.loader; }
        `,
          },
          realmURL: 'http://example.com/',
          virtualNetwork,
          dbAdapter,
          queue,
        });
        virtualNetwork.mount(realm.maybeHandle.bind(realm));
        await realm.ready;
      },
    });

    test('supports import.meta', async function (assert) {
      let { checkImportMeta, myLoader } = await loader2.import<{
        checkImportMeta: () => string;
        myLoader: () => Loader;
      }>('http://example.com/foo');
      assert.strictEqual(checkImportMeta(), 'http://example.com/foo');
      assert.strictEqual(myLoader(), loader2, 'the loader instance is correct');
    });
  });
});
