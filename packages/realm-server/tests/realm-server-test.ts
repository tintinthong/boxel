import { module, test } from 'qunit';
import supertest, { Test, SuperTest } from 'supertest';
import { join, resolve } from 'path';
import { Server } from 'http';
import { dirSync, setGracefulCleanup, DirResult } from 'tmp';
import { validate as uuidValidate } from 'uuid';
import {
  copySync,
  existsSync,
  readFileSync,
  readJSONSync,
  removeSync,
  writeJSONSync,
} from 'fs-extra';
import {
  cardSrc,
  compiledCard,
} from '@cardstack/runtime-common/etc/test-fixtures';
import {
  isSingleCardDocument,
  baseRealm,
  loadCard,
  Deferred,
  RealmPaths,
  Realm,
  RealmPermissions,
  VirtualNetwork,
  type LooseSingleCardDocument,
  Loader,
  fetcher,
  maybeHandleScopedCSSRequest,
} from '@cardstack/runtime-common';
import { stringify } from 'qs';
import { Query } from '@cardstack/runtime-common/query';
import {
  setupCardLogs,
  setupBaseRealmServer,
  runTestRealmServer,
  localBaseRealm,
  setupDB,
  createRealm,
} from './helpers';
import '@cardstack/runtime-common/helpers/code-equality-assertion';
import eventSource from 'eventsource';
import { shimExternals } from '../lib/externals';
import { RealmServer } from '../server';
import type * as CardAPI from 'https://cardstack.com/base/card-api';
import stripScopedCSSGlimmerAttributes from '@cardstack/runtime-common/helpers/strip-scoped-css-glimmer-attributes';

setGracefulCleanup();
const testRealmURL = new URL('http://127.0.0.1:4444/');
const testRealm2URL = new URL('http://127.0.0.1:4445');
const testRealmHref = testRealmURL.href;
const testRealm2Href = testRealm2URL.href;
const distDir = resolve(join(__dirname, '..', '..', 'host', 'dist'));
console.log(`using host dist dir: ${distDir}`);

let createJWT = (
  realm: Realm,
  user: string,
  realmUrl: string,
  permissions: RealmPermissions['user'] = [],
) => {
  return realm.createJWT({ user, realm: realmUrl, permissions }, '7d');
};

function createVirtualNetwork() {
  let virtualNetwork = new VirtualNetwork();
  shimExternals(virtualNetwork);
  virtualNetwork.addURLMapping(new URL(baseRealm.url), new URL(localBaseRealm));
  return virtualNetwork;
}

function createVirtualNetworkAndLoader() {
  let virtualNetwork = createVirtualNetwork();
  let fetch = fetcher(virtualNetwork.fetch, [
    async (req, next) => {
      return (await maybeHandleScopedCSSRequest(req)) || next(req);
    },
  ]);
  let loader = new Loader(fetch, virtualNetwork.resolveImport);
  return { virtualNetwork, loader };
}

module('Realm Server', function (hooks) {
  async function expectEvent<T>({
    assert,
    expected,
    expectedNumberOfEvents,
    onEvents,
    callback,
  }: {
    assert: Assert;
    expected?: Record<string, any>[];
    expectedNumberOfEvents?: number;
    onEvents?: (events: Record<string, any>[]) => void;
    callback: () => Promise<T>;
  }): Promise<T> {
    let defer = new Deferred<Record<string, any>[]>();
    let events: Record<string, any>[] = [];
    let maybeNumEvents = expected?.length ?? expectedNumberOfEvents;
    if (maybeNumEvents == null) {
      throw new Error(
        `expectEvent() must specify either 'expected' or 'expectedNumberOfEvents'`,
      );
    }
    let numEvents = maybeNumEvents;
    let es = new eventSource(`${testRealmHref}_message`);
    es.addEventListener('index', (ev: MessageEvent) => {
      events.push(JSON.parse(ev.data));
      if (events.length >= numEvents) {
        defer.fulfill(events);
      }
    });
    es.onerror = (err: Event) => defer.reject(err);
    let timeout = setTimeout(() => {
      defer.reject(
        new Error(
          `expectEvent timed out, saw events ${JSON.stringify(events)}`,
        ),
      );
    }, 5000);
    await new Promise((resolve) => es.addEventListener('open', resolve));
    let result = await callback();
    let actualEvents = await defer.promise;
    if (expected) {
      assert.deepEqual(actualEvents, expected);
    }
    if (onEvents) {
      onEvents(actualEvents);
    }
    clearTimeout(timeout);
    es.close();
    return result;
  }

  let testRealm: Realm;
  let testRealmServer: Server;
  let request: SuperTest<Test>;
  let dir: DirResult;

  function setupPermissionedRealm(
    hooks: NestedHooks,
    permissions: RealmPermissions,
  ) {
    setupDB(hooks, {
      beforeEach: async (dbAdapter, queue) => {
        dir = dirSync();
        copySync(join(__dirname, 'cards'), dir.name);
        let virtualNetwork = createVirtualNetwork();

        ({ testRealm, testRealmServer } = await runTestRealmServer({
          virtualNetwork,
          dir: dir.name,
          realmURL: testRealmURL,
          permissions,
          dbAdapter,
          queue,
        }));

        request = supertest(testRealmServer);
      },
    });
  }

  let { virtualNetwork, loader } = createVirtualNetworkAndLoader();

  setupCardLogs(
    hooks,
    async () => await loader.import(`${baseRealm.url}card-api`),
  );

  setupBaseRealmServer(hooks, virtualNetwork);

  hooks.beforeEach(async function () {
    dir = dirSync();
    copySync(join(__dirname, 'cards'), dir.name);
  });

  hooks.afterEach(function () {
    testRealmServer.close();
  });

  module('card GET request', function (_hooks) {
    module('public readable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read'],
      });

      test('serves the request', async function (assert) {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+json');

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        let json = response.body;
        assert.ok(json.data.meta.lastModified, 'lastModified exists');
        delete json.data.meta.lastModified;
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        assert.deepEqual(json, {
          data: {
            id: `${testRealmHref}person-1`,
            type: 'card',
            attributes: {
              firstName: 'Mango',
              description: null,
              thumbnailURL: null,
            },
            meta: {
              adoptsFrom: {
                module: `./person`,
                name: 'Person',
              },
              realmInfo: {
                name: 'Test Realm',
                backgroundURL: null,
                iconURL: null,
              },
              realmURL: testRealmURL.href,
            },
            links: {
              self: `${testRealmHref}person-1`,
            },
          },
        });
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+json')
          .set('Authorization', `Bearer invalid-token`);

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          undefined,
          'realm is not public readable',
        );
      });

      test('401 without a JWT', async function (assert) {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+json'); // no Authorization header

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          undefined,
          'realm is not public readable',
        );
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          undefined,
          'realm is not public readable',
        );
      });

      test('200 with permission', async function (assert) {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, ['read'])}`,
          );

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          undefined,
          'realm is not public readable',
        );
      });
    });
  });

  module('card POST request', function (_hooks) {
    module('public writable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read', 'write'],
      });

      test('serves the request', async function (assert) {
        assert.expect(9);
        let id: string | undefined;
        let response = await expectEvent({
          assert,
          expectedNumberOfEvents: 1,
          onEvents: ([event]) => {
            if (event.type === 'incremental') {
              id = event.invalidations[0].split('/').pop()!;
              assert.true(uuidValidate(id!), 'card identifier is a UUID');
              assert.strictEqual(
                event.invalidations[0],
                `${testRealmURL}CardDef/${id}`,
              );
            } else {
              assert.ok(
                false,
                `expect to receive 'incremental' event, but saw ${JSON.stringify(
                  event,
                )} `,
              );
            }
          },
          callback: async () => {
            return await request
              .post('/')
              .send({
                data: {
                  type: 'card',
                  attributes: {},
                  meta: {
                    adoptsFrom: {
                      module: 'https://cardstack.com/base/card-api',
                      name: 'CardDef',
                    },
                  },
                },
              })
              .set('Accept', 'application/vnd.card+json');
          },
        });
        if (!id) {
          assert.ok(false, 'new card identifier was undefined');
        }
        assert.strictEqual(response.status, 201, 'HTTP 201 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let json = response.body;

        if (isSingleCardDocument(json)) {
          assert.strictEqual(
            json.data.id,
            `${testRealmHref}CardDef/${id}`,
            'the id is correct',
          );
          assert.ok(json.data.meta.lastModified, 'lastModified is populated');
          let cardFile = join(dir.name, 'CardDef', `${id}.json`);
          assert.ok(existsSync(cardFile), 'card json exists');
          let card = readJSONSync(cardFile);
          assert.deepEqual(
            card,
            {
              data: {
                attributes: {
                  title: null,
                  description: null,
                  thumbnailURL: null,
                },
                type: 'card',
                meta: {
                  adoptsFrom: {
                    module: 'https://cardstack.com/base/card-api',
                    name: 'CardDef',
                  },
                },
              },
            },
            'file contents are correct',
          );
        } else {
          assert.ok(false, 'response body is not a card document');
        }
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read', 'write'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .post('/')
          .send({})
          .set('Accept', 'application/vnd.card+json')
          .set('Authorization', `Bearer invalid-token`);

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('401 without a JWT', async function (assert) {
        let response = await request
          .post('/')
          .send({})
          .set('Accept', 'application/vnd.card+json'); // no Authorization header

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('401 permissions have been updated', async function (assert) {
        let response = await request
          .post('/')
          .send({})
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, ['read'])}`,
          );

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .post('/')
          .send({})
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
      });

      test('201 with permission', async function (assert) {
        let response = await request
          .post('/')
          .send({
            data: {
              type: 'card',
              attributes: {},
              meta: {
                adoptsFrom: {
                  module: 'https://cardstack.com/base/card-api',
                  name: 'CardDef',
                },
              },
            },
          })
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, [
              'read',
              'write',
            ])}`,
          );

        assert.strictEqual(response.status, 201, 'HTTP 201 status');
      });
    });
  });

  module('card PATCH request', function (_hooks) {
    module('public writable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read', 'write'],
      });

      test('serves the request', async function (assert) {
        let entry = 'person-1.json';
        let expected = [
          {
            type: 'incremental',
            invalidations: [`${testRealmURL}person-1`],
            clientRequestId: null,
          },
        ];
        let response = await expectEvent({
          assert,
          expected,
          callback: async () => {
            return await request
              .patch('/person-1')
              .send({
                data: {
                  type: 'card',
                  attributes: {
                    firstName: 'Van Gogh',
                  },
                  meta: {
                    adoptsFrom: {
                      module: './person.gts',
                      name: 'Person',
                    },
                  },
                },
              })
              .set('Accept', 'application/vnd.card+json');
          },
        });

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );

        let json = response.body;
        assert.ok(json.data.meta.lastModified, 'lastModified exists');
        if (isSingleCardDocument(json)) {
          assert.strictEqual(
            json.data.attributes?.firstName,
            'Van Gogh',
            'the field data is correct',
          );
          assert.ok(json.data.meta.lastModified, 'lastModified is populated');
          delete json.data.meta.lastModified;
          let cardFile = join(dir.name, entry);
          assert.ok(existsSync(cardFile), 'card json exists');
          let card = readJSONSync(cardFile);
          assert.deepEqual(
            card,
            {
              data: {
                type: 'card',
                attributes: {
                  firstName: 'Van Gogh',
                  description: null,
                  thumbnailURL: null,
                },
                meta: {
                  adoptsFrom: {
                    module: `./person`,
                    name: 'Person',
                  },
                },
              },
            },
            'file contents are correct',
          );
        } else {
          assert.ok(false, 'response body is not a card document');
        }

        let query: Query = {
          filter: {
            on: {
              module: `${testRealmHref}person`,
              name: 'Person',
            },
            eq: {
              firstName: 'Van Gogh',
            },
          },
        };

        response = await request
          .get(`/_search?${stringify(query)}`)
          .set('Accept', 'application/vnd.card+json');

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        assert.strictEqual(response.body.data.length, 1, 'found one card');
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read', 'write'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .patch('/person-1')
          .send({})
          .set('Accept', 'application/vnd.card+json')
          .set('Authorization', `Bearer invalid-token`);

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .patch('/person-1')
          .send({
            data: {
              type: 'card',
              attributes: {
                firstName: 'Van Gogh',
              },
              meta: {
                adoptsFrom: {
                  module: './person.gts',
                  name: 'Person',
                },
              },
            },
          })
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
      });

      test('200 with permission', async function (assert) {
        let response = await request
          .patch('/person-1')
          .send({
            data: {
              type: 'card',
              attributes: {
                firstName: 'Van Gogh',
              },
              meta: {
                adoptsFrom: {
                  module: './person.gts',
                  name: 'Person',
                },
              },
            },
          })
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, [
              'read',
              'write',
            ])}`,
          );

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
      });
    });
  });

  module('card DELETE request', function (_hooks) {
    module('public writable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read', 'write'],
      });

      test('serves the request', async function (assert) {
        let entry = 'person-1.json';
        let expected = [
          {
            type: 'incremental',
            invalidations: [`${testRealmURL}person-1`],
          },
        ];
        let response = await expectEvent({
          assert,
          expected,
          callback: async () => {
            return await request
              .delete('/person-1')
              .set('Accept', 'application/vnd.card+json');
          },
        });

        assert.strictEqual(response.status, 204, 'HTTP 204 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let cardFile = join(dir.name, entry);
        assert.false(existsSync(cardFile), 'card json does not exist');
      });

      test('serves a card DELETE request with .json extension in the url', async function (assert) {
        let entry = 'person-1.json';
        let expected = [
          {
            type: 'incremental',
            invalidations: [`${testRealmURL}person-1`],
          },
        ];

        let response = await expectEvent({
          assert,
          expected,
          callback: async () => {
            return await request
              .delete('/person-1.json')
              .set('Accept', 'application/vnd.card+json');
          },
        });

        assert.strictEqual(response.status, 204, 'HTTP 204 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let cardFile = join(dir.name, entry);
        assert.false(existsSync(cardFile), 'card json does not exist');
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read', 'write'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .delete('/person-1')

          .set('Accept', 'application/vnd.card+json')
          .set('Authorization', `Bearer invalid-token`);

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .delete('/person-1')
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
      });

      test('204 with permission', async function (assert) {
        let response = await request
          .delete('/person-1')
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, [
              'read',
              'write',
            ])}`,
          );

        assert.strictEqual(response.status, 204, 'HTTP 204 status');
      });
    });
  });

  module('card source GET request', function (_hooks) {
    module('public readable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read'],
      });

      test('serves the request', async function (assert) {
        let response = await request
          .get('/person.gts')
          .set('Accept', 'application/vnd.card+source');

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let result = response.text.trim();
        assert.strictEqual(result, cardSrc, 'the card source is correct');
        assert.ok(
          response.headers['last-modified'],
          'last-modified header exists',
        );
      });

      test('serves a card-source GET request that results in redirect', async function (assert) {
        let response = await request
          .get('/person')
          .set('Accept', 'application/vnd.card+source');

        assert.strictEqual(response.status, 302, 'HTTP 302 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        assert.strictEqual(response.headers['location'], '/person.gts');
      });

      test('serves a card instance GET request with card-source accept header that results in redirect', async function (assert) {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+source');

        assert.strictEqual(response.status, 302, 'HTTP 302 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        assert.strictEqual(response.headers['location'], '/person-1.json');
      });

      test('serves a card instance GET request with a .json extension and json accept header that results in redirect', async function (assert) {
        let response = await request
          .get('/person.json')
          .set('Accept', 'application/vnd.card+json');

        assert.strictEqual(response.status, 302, 'HTTP 302 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        assert.strictEqual(response.headers['location'], '/person');
      });

      test('serves a module GET request', async function (assert) {
        let response = await request.get('/person');

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm URL header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let body = response.text.trim();
        let moduleAbsolutePath = resolve(join(__dirname, '..', 'person.gts'));

        // Remove platform-dependent id, from https://github.com/emberjs/babel-plugin-ember-template-compilation/blob/d67cca121cfb3bbf5327682b17ed3f2d5a5af528/__tests__/tests.ts#LL1430C1-L1431C1
        body = stripScopedCSSGlimmerAttributes(
          body.replace(/"id":\s"[^"]+"/, '"id": "<id>"'),
        );

        assert.codeEqual(
          body,
          compiledCard('"<id>"', moduleAbsolutePath),
          'module JS is correct',
        );
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .get('/person.gts')
          .set('Accept', 'application/vnd.card+source')
          .set('Authorization', `Bearer invalid-token`);

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('401 without a JWT', async function (assert) {
        let response = await request
          .get('/person.gts')
          .set('Accept', 'application/vnd.card+source'); // no Authorization header

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .get('/person.gts')
          .set('Accept', 'application/vnd.card+source')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
      });

      test('200 with permission', async function (assert) {
        let response = await request
          .get('/person.gts')
          .set('Accept', 'application/vnd.card+source')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, ['read'])}`,
          );

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
      });
    });
  });

  module('card-source DELETE request', function (_hooks) {
    module('public writable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read', 'write'],
      });

      test('serves the request', async function (assert) {
        let entry = 'unused-card.gts';
        let expected = [
          {
            type: 'incremental',
            invalidations: [`${testRealmURL}unused-card.gts`],
          },
        ];
        let response = await expectEvent({
          assert,
          expected,
          callback: async () => {
            return await request
              .delete('/unused-card.gts')
              .set('Accept', 'application/vnd.card+source');
          },
        });

        assert.strictEqual(response.status, 204, 'HTTP 204 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let cardFile = join(dir.name, entry);
        assert.false(existsSync(cardFile), 'card module does not exist');
      });

      test('serves a card-source DELETE request for a card instance', async function (assert) {
        let entry = 'person-1';
        let expected = [
          {
            type: 'incremental',
            invalidations: [`${testRealmURL}person-1`],
          },
        ];
        let response = await expectEvent({
          assert,
          expected,
          callback: async () => {
            return await request
              .delete('/person-1')
              .set('Accept', 'application/vnd.card+source');
          },
        });

        assert.strictEqual(response.status, 204, 'HTTP 204 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let cardFile = join(dir.name, entry);
        assert.false(existsSync(cardFile), 'card instance does not exist');
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read', 'write'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .delete('/unused-card.gts')
          .set('Accept', 'application/vnd.card+source')
          .set('Authorization', `Bearer invalid-token`);

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .delete('/unused-card.gts')
          .set('Accept', 'application/vnd.card+source')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
      });

      test('204 with permission', async function (assert) {
        let response = await request
          .delete('/unused-card.gts')
          .set('Accept', 'application/vnd.card+source')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, [
              'read',
              'write',
            ])}`,
          );

        assert.strictEqual(response.status, 204, 'HTTP 204 status');
      });
    });
  });

  module('card-source POST request', function (_hooks) {
    module('public writable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read', 'write'],
      });

      test('serves a card-source POST request', async function (assert) {
        let entry = 'unused-card.gts';
        let expected = [
          {
            type: 'incremental',
            invalidations: [`${testRealmURL}unused-card.gts`],
            clientRequestId: null,
          },
        ];
        let response = await expectEvent({
          assert,
          expected,
          callback: async () => {
            return await request
              .post('/unused-card.gts')
              .set('Accept', 'application/vnd.card+source')
              .send(`//TEST UPDATE\n${cardSrc}`);
          },
        });

        assert.strictEqual(response.status, 204, 'HTTP 204 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );

        let srcFile = join(dir.name, entry);
        assert.ok(existsSync(srcFile), 'card src exists');
        let src = readFileSync(srcFile, { encoding: 'utf8' });
        assert.codeEqual(
          src,
          `//TEST UPDATE
          ${cardSrc}`,
        );
      });

      test('can serialize a card instance correctly after card definition is changed', async function (assert) {
        // create a card def
        {
          let expected = [
            {
              type: 'incremental',
              invalidations: [`${testRealmURL}test-card.gts`],
              clientRequestId: null,
            },
          ];

          let response = await expectEvent({
            assert,
            expected,
            callback: async () => {
              return await request
                .post('/test-card.gts')
                .set('Accept', 'application/vnd.card+source').send(`
                import { contains, field, CardDef } from 'https://cardstack.com/base/card-api';
                import StringCard from 'https://cardstack.com/base/string';

                export class TestCard extends CardDef {
                  @field field1 = contains(StringCard);
                  @field field2 = contains(StringCard);
                }
              `);
            },
          });
          assert.strictEqual(response.status, 204, 'HTTP 204 status');
        }

        // make an instance of the card def
        let maybeId: string | undefined;
        {
          let response = await expectEvent({
            assert,
            expectedNumberOfEvents: 1,
            callback: async () => {
              return await request
                .post('/')
                .send({
                  data: {
                    type: 'card',
                    attributes: {
                      field1: 'a',
                      field2: 'b',
                    },
                    meta: {
                      adoptsFrom: {
                        module: `${testRealmURL}test-card`,
                        name: 'TestCard',
                      },
                    },
                  },
                })
                .set('Accept', 'application/vnd.card+json');
            },
          });
          assert.strictEqual(response.status, 201, 'HTTP 201 status');
          maybeId = response.body.data.id;
        }
        if (!maybeId) {
          assert.ok(false, 'new card identifier was undefined');
          // eslint-disable-next-line qunit/no-early-return
          return;
        }
        let id = maybeId;

        // modify field
        {
          let expected = [
            {
              type: 'incremental',
              invalidations: [`${testRealmURL}test-card.gts`, id],
              clientRequestId: null,
            },
          ];

          let response = await expectEvent({
            assert,
            expected,
            callback: async () => {
              return await request
                .post('/test-card.gts')
                .set('Accept', 'application/vnd.card+source').send(`
                import { contains, field, CardDef } from 'https://cardstack.com/base/card-api';
                import StringCard from 'https://cardstack.com/base/string';

                export class TestCard extends CardDef {
                  @field field1 = contains(StringCard);
                  @field field2a = contains(StringCard); // rename field2 -> field2a
                }
              `);
            },
          });
          assert.strictEqual(response.status, 204, 'HTTP 204 status');
        }

        // verify serialization matches new card def
        {
          let response = await request
            .get(new URL(id).pathname)
            .set('Accept', 'application/vnd.card+json');

          assert.strictEqual(response.status, 200, 'HTTP 200 status');
          let json = response.body;
          assert.deepEqual(json.data.attributes, {
            field1: 'a',
            field2a: null,
            title: null,
            description: null,
            thumbnailURL: null,
          });
        }

        // set value on renamed field
        {
          let expected = [
            {
              type: 'incremental',
              invalidations: [id],
              clientRequestId: null,
            },
          ];
          let response = await expectEvent({
            assert,
            expected,
            callback: async () => {
              return await request
                .patch(new URL(id).pathname)
                .send({
                  data: {
                    type: 'card',
                    attributes: {
                      field2a: 'c',
                    },
                    meta: {
                      adoptsFrom: {
                        module: `${testRealmURL}test-card`,
                        name: 'TestCard',
                      },
                    },
                  },
                })
                .set('Accept', 'application/vnd.card+json');
            },
          });

          assert.strictEqual(response.status, 200, 'HTTP 200 status');
          assert.strictEqual(
            response.get('X-boxel-realm-url'),
            testRealmURL.href,
            'realm url header is correct',
          );
          assert.strictEqual(
            response.get('X-boxel-realm-public-readable'),
            'true',
            'realm is public readable',
          );

          let json = response.body;
          assert.deepEqual(json.data.attributes, {
            field1: 'a',
            field2a: 'c',
            title: null,
            description: null,
            thumbnailURL: null,
          });
        }

        // verify file serialization is correct
        {
          let localPath = new RealmPaths(testRealmURL).local(new URL(id));
          let jsonFile = `${join(dir.name, localPath)}.json`;
          let doc = JSON.parse(
            readFileSync(jsonFile, { encoding: 'utf8' }),
          ) as LooseSingleCardDocument;
          assert.deepEqual(
            doc,
            {
              data: {
                type: 'card',
                attributes: {
                  field1: 'a',
                  field2a: 'c',
                  title: null,
                  description: null,
                  thumbnailURL: null,
                },
                meta: {
                  adoptsFrom: {
                    module: '/test-card',
                    name: 'TestCard',
                  },
                },
              },
            },
            'instance serialized to filesystem correctly',
          );
        }

        // verify instance GET is correct
        {
          let response = await request
            .get(new URL(id).pathname)
            .set('Accept', 'application/vnd.card+json');

          assert.strictEqual(response.status, 200, 'HTTP 200 status');
          let json = response.body;
          assert.deepEqual(json.data.attributes, {
            field1: 'a',
            field2a: 'c',
            title: null,
            description: null,
            thumbnailURL: null,
          });
        }
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read', 'write'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .post('/unused-card.gts')
          .set('Accept', 'application/vnd.card+source')
          .send(`//TEST UPDATE\n${cardSrc}`)
          .set('Authorization', `Bearer invalid-token`);

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('401 without a JWT', async function (assert) {
        let response = await request
          .post('/unused-card.gts')
          .set('Accept', 'application/vnd.card+source')
          .send(`//TEST UPDATE\n${cardSrc}`); // no Authorization header

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .post('/unused-card.gts')
          .set('Accept', 'application/vnd.card+source')
          .send(`//TEST UPDATE\n${cardSrc}`)
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
      });

      test('204 with permission', async function (assert) {
        let response = await request
          .post('/unused-card.gts')
          .set('Accept', 'application/vnd.card+source')
          .send(`//TEST UPDATE\n${cardSrc}`)
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, [
              'read',
              'write',
            ])}`,
          );

        assert.strictEqual(response.status, 204, 'HTTP 204 status');
      });
    });
  });

  module('directory GET request', function (_hooks) {
    module('public readable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read'],
      });

      test('serves the request', async function (assert) {
        let response = await request
          .get('/dir/')
          .set('Accept', 'application/vnd.api+json');

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let json = response.body;
        assert.deepEqual(
          json,
          {
            data: {
              id: `${testRealmHref}dir/`,
              type: 'directory',
              relationships: {
                'bar.txt': {
                  links: {
                    related: `${testRealmHref}dir/bar.txt`,
                  },
                  meta: {
                    kind: 'file',
                  },
                },
                'foo.txt': {
                  links: {
                    related: `${testRealmHref}dir/foo.txt`,
                  },
                  meta: {
                    kind: 'file',
                  },
                },
                'subdir/': {
                  links: {
                    related: `${testRealmHref}dir/subdir/`,
                  },
                  meta: {
                    kind: 'directory',
                  },
                },
              },
            },
          },
          'the directory response is correct',
        );
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .get('/dir/')
          .set('Accept', 'application/vnd.api+json')
          .set('Authorization', `Bearer invalid-token`);

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('401 without a JWT', async function (assert) {
        let response = await request
          .get('/dir/')
          .set('Accept', 'application/vnd.api+json'); // no Authorization header

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .get('/dir/')
          .set('Accept', 'application/vnd.api+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
      });

      test('200 with permission', async function (assert) {
        let response = await request
          .get('/dir/')
          .set('Accept', 'application/vnd.api+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, ['read'])}`,
          );

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
      });
    });
  });

  module('_search GET request', function (_hooks) {
    let query: Query = {
      filter: {
        on: {
          module: `${testRealmHref}person`,
          name: 'Person',
        },
        eq: {
          firstName: 'Mango',
        },
      },
    };

    module('public readable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read'],
      });

      test('serves a /_search GET request', async function (assert) {
        let response = await request
          .get(`/_search?${stringify(query)}`)
          .set('Accept', 'application/vnd.card+json');

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let json = response.body;
        assert.strictEqual(
          json.data.length,
          1,
          'the card is returned in the search results',
        );
        assert.strictEqual(
          json.data[0].id,
          `${testRealmHref}person-1`,
          'card ID is correct',
        );
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .get(`/_search?${stringify(query)}`)
          .set('Accept', 'application/vnd.card+json');

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('401 without a JWT', async function (assert) {
        let response = await request
          .get(`/_search?${stringify(query)}`)
          .set('Accept', 'application/vnd.card+json'); // no Authorization header

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .get(`/_search?${stringify(query)}`)
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
      });

      test('200 with permission', async function (assert) {
        let response = await request
          .get(`/_search?${stringify(query)}`)
          .set('Accept', 'application/vnd.card+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, ['read'])}`,
          );

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
      });
    });
  });

  module('_info GET request', function (_hooks) {
    module('public readable realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        '*': ['read'],
      });

      test('serves the request', async function (assert) {
        let response = await request
          .get(`/_info`)
          .set('Accept', 'application/vnd.api+json');

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        let json = response.body;
        assert.deepEqual(
          json,
          {
            data: {
              id: testRealmHref,
              type: 'realm-info',
              attributes: {
                name: 'Test Realm',
                backgroundURL: null,
                iconURL: null,
              },
            },
          },
          '/_info response is correct',
        );
      });
    });

    module('permissioned realm', function (hooks) {
      setupPermissionedRealm(hooks, {
        john: ['read'],
      });

      test('401 with invalid JWT', async function (assert) {
        let response = await request
          .get(`/_info`)
          .set('Accept', 'application/vnd.api+json');

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('401 without a JWT', async function (assert) {
        let response = await request
          .get(`/_info`)
          .set('Accept', 'application/vnd.api+json'); // no Authorization header

        assert.strictEqual(response.status, 401, 'HTTP 401 status');
      });

      test('403 without permission', async function (assert) {
        let response = await request
          .get(`/_info`)
          .set('Accept', 'application/vnd.api+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'not-john', testRealmHref)}`,
          );

        assert.strictEqual(response.status, 403, 'HTTP 403 status');
      });

      test('200 with permission', async function (assert) {
        let response = await request
          .get(`/_info`)
          .set('Accept', 'application/vnd.api+json')
          .set(
            'Authorization',
            `Bearer ${createJWT(testRealm, 'john', testRealmHref, ['read'])}`,
          );

        assert.strictEqual(response.status, 200, 'HTTP 200 status');
      });
    });
  });
  module('various other realm tests', function (hooks) {
    let testRealmServer2: Server;
    let testRealm2: Realm;

    hooks.beforeEach(async function () {
      shimExternals(virtualNetwork);
    });

    setupPermissionedRealm(hooks, {
      '*': ['read', 'write'],
    });

    setupDB(hooks, {
      beforeEach: async (dbAdapter, queue) => {
        if (testRealm2) {
          virtualNetwork.unmount(testRealm2.maybeExternalHandle);
        }
        ({ testRealm: testRealm2, testRealmServer: testRealmServer2 } =
          await runTestRealmServer({
            virtualNetwork,
            dir: dir.name,
            realmURL: testRealm2URL,
            dbAdapter,
            queue,
          }));
      },
      afterEach: async () => {
        testRealmServer2.close();
      },
    });

    test('can dynamically load a card definition from own realm', async function (assert) {
      let ref = {
        module: `${testRealmHref}person`,
        name: 'Person',
      };
      await loadCard(ref, { loader });
      let doc = {
        data: {
          attributes: { firstName: 'Mango' },
          meta: { adoptsFrom: ref },
        },
      };
      let api = await loader.import<typeof CardAPI>(
        'https://cardstack.com/base/card-api',
      );
      let person = await api.createFromSerialized<any>(
        doc.data,
        doc,
        undefined,
        loader,
      );
      assert.strictEqual(person.firstName, 'Mango', 'card data is correct');
    });

    test('can dynamically load a card definition from a different realm', async function (assert) {
      let ref = {
        module: `${testRealm2Href}person`,
        name: 'Person',
      };
      await loadCard(ref, { loader });
      let doc = {
        data: {
          attributes: { firstName: 'Mango' },
          meta: { adoptsFrom: ref },
        },
      };
      let api = await loader.import<typeof CardAPI>(
        'https://cardstack.com/base/card-api',
      );
      let person = await api.createFromSerialized<any>(
        doc.data,
        doc,
        undefined,
        loader,
      );
      assert.strictEqual(person.firstName, 'Mango', 'card data is correct');
    });

    test('can instantiate a card that uses a code-ref field', async function (assert) {
      let adoptsFrom = {
        module: `${testRealm2Href}code-ref-test`,
        name: 'TestCard',
      };
      await loadCard(adoptsFrom, { loader });
      let ref = { module: `${testRealm2Href}person`, name: 'Person' };
      let doc = {
        data: {
          attributes: { ref },
          meta: { adoptsFrom },
        },
      };
      let api = await loader.import<typeof CardAPI>(
        'https://cardstack.com/base/card-api',
      );
      let testCard = await api.createFromSerialized<any>(
        doc.data,
        doc,
        undefined,
        loader,
      );
      assert.deepEqual(testCard.ref, ref, 'card data is correct');
    });

    test('can index a newly added file to the filesystem', async function (assert) {
      {
        let response = await request
          .get('/new-card')
          .set('Accept', 'application/vnd.card+json');
        assert.strictEqual(response.status, 404, 'HTTP 404 status');
      }
      let expected = [
        {
          type: 'incremental',
          invalidations: [`${testRealmURL}new-card`],
        },
      ];
      await expectEvent({
        assert,
        expected,
        callback: async () => {
          writeJSONSync(join(dir.name, 'new-card.json'), {
            data: {
              attributes: {
                firstName: 'Mango',
              },
              meta: {
                adoptsFrom: {
                  module: './person',
                  name: 'Person',
                },
              },
            },
          } as LooseSingleCardDocument);
        },
      });

      {
        let response = await request
          .get('/new-card')
          .set('Accept', 'application/vnd.card+json');
        assert.strictEqual(response.status, 200, 'HTTP 200 status');
        let json = response.body;
        assert.ok(json.data.meta.lastModified, 'lastModified exists');
        delete json.data.meta.lastModified;
        assert.strictEqual(
          response.get('X-boxel-realm-url'),
          testRealmURL.href,
          'realm url header is correct',
        );
        assert.strictEqual(
          response.get('X-boxel-realm-public-readable'),
          'true',
          'realm is public readable',
        );
        assert.deepEqual(json, {
          data: {
            id: `${testRealmHref}new-card`,
            type: 'card',
            attributes: {
              firstName: 'Mango',
              description: null,
              thumbnailURL: null,
            },
            meta: {
              adoptsFrom: {
                module: `./person`,
                name: 'Person',
              },
              realmInfo: {
                name: 'Test Realm',
                backgroundURL: null,
                iconURL: null,
              },
              realmURL: testRealmURL.href,
            },
            links: {
              self: `${testRealmHref}new-card`,
            },
          },
        });
      }
    });

    test('can index a changed file in the filesystem', async function (assert) {
      {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+json');
        let json = response.body as LooseSingleCardDocument;
        assert.strictEqual(
          json.data.attributes?.firstName,
          'Mango',
          'initial firstName value is correct',
        );
      }

      let expected = [
        {
          type: 'incremental',
          invalidations: [`${testRealmURL}person-1`],
        },
      ];
      await expectEvent({
        assert,
        expected,
        callback: async () => {
          writeJSONSync(join(dir.name, 'person-1.json'), {
            data: {
              type: 'card',
              attributes: {
                firstName: 'Van Gogh',
              },
              meta: {
                adoptsFrom: {
                  module: './person.gts',
                  name: 'Person',
                },
              },
            },
          } as LooseSingleCardDocument);
        },
      });

      {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+json');
        let json = response.body as LooseSingleCardDocument;
        assert.strictEqual(
          json.data.attributes?.firstName,
          'Van Gogh',
          'updated firstName value is correct',
        );
      }
    });

    test('can index a file deleted from the filesystem', async function (assert) {
      {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+json');
        assert.strictEqual(response.status, 200, 'HTTP 200 status');
      }

      let expected = [
        {
          type: 'incremental',
          invalidations: [`${testRealmURL}person-1`],
        },
      ];
      await expectEvent({
        assert,
        expected,
        callback: async () => {
          removeSync(join(dir.name, 'person-1.json'));
        },
      });

      {
        let response = await request
          .get('/person-1')
          .set('Accept', 'application/vnd.card+json');
        assert.strictEqual(response.status, 404, 'HTTP 404 status');
      }
    });

    test('can make HEAD request to get realmURL and isPublicReadable status', async function (assert) {
      let response = await request
        .head('/person-1')
        .set('Accept', 'application/vnd.card+json');

      assert.strictEqual(response.status, 200, 'HTTP 200 status');
      assert.strictEqual(
        response.headers['x-boxel-realm-url'],
        testRealmURL.href,
      );
      assert.strictEqual(
        response.headers['x-boxel-realm-public-readable'],
        'true',
      );
    });
  });

  module('BOXEL_HTTP_BASIC_PW env var', function (hooks) {
    hooks.afterEach(function () {
      delete process.env.BOXEL_HTTP_BASIC_PW;
    });

    test('serves a text/html GET request', async function (assert) {
      let response = await request.get('/').set('Accept', 'text/html');
      assert.strictEqual(response.status, 200, 'HTTP 200 status');

      process.env.BOXEL_HTTP_BASIC_PW = '1';

      response = await request.get('/').set('Accept', 'text/html');
      assert.strictEqual(response.status, 401, 'HTTP 401 status');
      assert.strictEqual(
        response.headers['www-authenticate'],
        'Basic realm="Boxel realm server"',
      );

      response = await request
        .get('/')
        .set('Accept', 'text/html')
        .auth('cardstack', 'wrong-password');
      assert.strictEqual(response.status, 401, 'HTTP 401 status');
      assert.strictEqual(
        response.text,
        'Authorization Required',
        'the text returned is correct',
      );
      assert.strictEqual(
        response.headers['www-authenticate'],
        'Basic realm="Boxel realm server"',
      );

      response = await request
        .get('/')
        .set('Accept', 'text/html')
        .auth('cardstack', process.env.BOXEL_HTTP_BASIC_PW);
      assert.strictEqual(response.status, 200, 'HTTP 200 status');
      assert.ok(
        /https?:\/\/[^/]+\/__boxel\/assets\/vendor\.css/.test(response.text),
        'the HTML returned is correct',
      );
    });
  });
});

module('Realm Server serving from root', function (hooks) {
  let testRealmServer: Server;

  let request: SuperTest<Test>;

  let dir: DirResult;

  let { virtualNetwork, loader } = createVirtualNetworkAndLoader();

  setupCardLogs(
    hooks,
    async () => await loader.import(`${baseRealm.url}card-api`),
  );

  setupBaseRealmServer(hooks, virtualNetwork);

  hooks.beforeEach(async function () {
    dir = dirSync();
    copySync(join(__dirname, 'cards'), dir.name);
  });

  setupDB(hooks, {
    beforeEach: async (dbAdapter, queue) => {
      testRealmServer = (
        await runTestRealmServer({
          virtualNetwork,
          dir: dir.name,
          realmURL: testRealmURL,
          dbAdapter,
          queue,
        })
      ).testRealmServer;
      request = supertest(testRealmServer);
    },
    afterEach: async () => {
      testRealmServer.close();
    },
  });

  test('serves a root directory GET request', async function (assert) {
    let response = await request
      .get('/')
      .set('Accept', 'application/vnd.api+json');

    assert.strictEqual(response.status, 200, 'HTTP 200 status');
    let json = response.body;
    assert.deepEqual(
      json,
      {
        data: {
          id: testRealmHref,
          type: 'directory',
          relationships: {
            'a.js': {
              links: {
                related: `${testRealmHref}a.js`,
              },
              meta: {
                kind: 'file',
              },
            },
            'b.js': {
              links: {
                related: `${testRealmHref}b.js`,
              },
              meta: {
                kind: 'file',
              },
            },
            'c.js': {
              links: {
                related: `${testRealmHref}c.js`,
              },
              meta: {
                kind: 'file',
              },
            },
            'code-ref-test.gts': {
              links: {
                related: `${testRealmHref}code-ref-test.gts`,
              },
              meta: {
                kind: 'file',
              },
            },
            'cycle-one.js': {
              links: {
                related: `${testRealmHref}cycle-one.js`,
              },
              meta: {
                kind: 'file',
              },
            },
            'cycle-two.js': {
              links: {
                related: `${testRealmHref}cycle-two.js`,
              },
              meta: {
                kind: 'file',
              },
            },
            'd.js': {
              links: {
                related: `${testRealmHref}d.js`,
              },
              meta: {
                kind: 'file',
              },
            },
            'deadlock/': {
              links: {
                related: `${testRealmHref}deadlock/`,
              },
              meta: {
                kind: 'directory',
              },
            },
            'dir/': {
              links: {
                related: `${testRealmHref}dir/`,
              },
              meta: {
                kind: 'directory',
              },
            },
            'e.js': {
              links: {
                related: `${testRealmHref}e.js`,
              },
              meta: {
                kind: 'file',
              },
            },
            'home.gts': {
              links: {
                related: `${testRealmHref}home.gts`,
              },
              meta: {
                kind: 'file',
              },
            },
            'index.json': {
              links: {
                related: `${testRealmHref}index.json`,
              },
              meta: {
                kind: 'file',
              },
            },
            'person-1.json': {
              links: {
                related: `${testRealmHref}person-1.json`,
              },
              meta: {
                kind: 'file',
              },
            },
            'person-2.json': {
              links: {
                related: `${testRealmHref}person-2.json`,
              },
              meta: {
                kind: 'file',
              },
            },
            'person.gts': {
              links: {
                related: `${testRealmHref}person.gts`,
              },
              meta: {
                kind: 'file',
              },
            },
            'person.json': {
              links: {
                related: `${testRealmHref}person.json`,
              },
              meta: {
                kind: 'file',
              },
            },
            'query-test-cards.gts': {
              links: {
                related: `${testRealmHref}query-test-cards.gts`,
              },
              meta: {
                kind: 'file',
              },
            },
            'unused-card.gts': {
              links: {
                related: `${testRealmHref}unused-card.gts`,
              },
              meta: {
                kind: 'file',
              },
            },
          },
        },
      },
      'the directory response is correct',
    );
  });
});

module('Realm server serving multiple realms', function (hooks) {
  let testRealmServer: Server;
  let request: SuperTest<Test>;
  let dir: DirResult;
  let base: Realm;
  let testRealm: Realm;

  let { virtualNetwork, loader } = createVirtualNetworkAndLoader();
  const basePath = resolve(join(__dirname, '..', '..', 'base'));

  hooks.beforeEach(async function () {
    dir = dirSync();
    copySync(join(__dirname, 'cards'), dir.name);
  });

  setupDB(hooks, {
    beforeEach: async (dbAdapter, queue) => {
      let localBaseRealmURL = new URL('http://127.0.0.1:4446/base/');
      virtualNetwork.addURLMapping(new URL(baseRealm.url), localBaseRealmURL);

      base = await createRealm({
        dir: basePath,
        realmURL: baseRealm.url,
        virtualNetwork,
        queue,
        dbAdapter,
        deferStartUp: true,
      });
      virtualNetwork.mount(base.maybeExternalHandle);

      testRealm = await createRealm({
        dir: dir.name,
        virtualNetwork,
        realmURL: 'http://127.0.0.1:4446/demo/',
        queue,
        dbAdapter,
        deferStartUp: true,
      });
      virtualNetwork.mount(testRealm.maybeExternalHandle);

      testRealmServer = new RealmServer(
        [base, testRealm],
        virtualNetwork,
      ).listen(parseInt(localBaseRealmURL.port));
      await base.start();
      await testRealm.start();

      request = supertest(testRealmServer);
    },
    afterEach: async () => {
      testRealmServer.close();
    },
  });

  setupCardLogs(
    hooks,
    async () => await loader.import(`${baseRealm.url}card-api`),
  );

  test(`Can perform full indexing multiple times on a server that runs multiple realms`, async function (assert) {
    {
      let response = await request
        .get('/demo/person-1')
        .set('Accept', 'application/vnd.card+json');
      assert.strictEqual(response.status, 200, 'HTTP 200 status');
    }

    await base.reindex();
    await testRealm.reindex();

    {
      let response = await request
        .get('/demo/person-1')
        .set('Accept', 'application/vnd.card+json');
      assert.strictEqual(response.status, 200, 'HTTP 200 status');
    }

    await base.reindex();
    await testRealm.reindex();

    {
      let response = await request
        .get('/demo/person-1')
        .set('Accept', 'application/vnd.card+json');
      assert.strictEqual(response.status, 200, 'HTTP 200 status');
    }
  });
});

module('Realm Server serving from a subdirectory', function (hooks) {
  let testRealmServer: Server;

  let request: SuperTest<Test>;

  let dir: DirResult;

  let { virtualNetwork, loader } = createVirtualNetworkAndLoader();

  setupCardLogs(
    hooks,
    async () => await loader.import(`${baseRealm.url}card-api`),
  );

  setupBaseRealmServer(hooks, virtualNetwork);

  hooks.beforeEach(async function () {
    dir = dirSync();
    copySync(join(__dirname, 'cards'), dir.name);
  });

  setupDB(hooks, {
    beforeEach: async (dbAdapter, queue) => {
      testRealmServer = (
        await runTestRealmServer({
          virtualNetwork,
          dir: dir.name,
          realmURL: new URL('http://127.0.0.1:4446/demo/'),
          dbAdapter,
          queue,
        })
      ).testRealmServer;
      request = supertest(testRealmServer);
    },
    afterEach: async () => {
      testRealmServer.close();
    },
  });

  test('serves a subdirectory GET request that results in redirect', async function (assert) {
    let response = await request.get('/demo');

    assert.strictEqual(response.status, 302, 'HTTP 302 status');
    assert.strictEqual(
      response.headers['location'],
      'http://127.0.0.1:4446/demo/',
    );
  });

  test('redirection keeps query params intact', async function (assert) {
    let response = await request.get(
      '/demo?operatorModeEnabled=true&operatorModeState=%7B%22stacks%22%3A%5B%7B%22items%22%3A%5B%7B%22card%22%3A%7B%22id%22%3A%22http%3A%2F%2Flocalhost%3A4204%2Findex%22%7D%2C%22format%22%3A%22isolated%22%7D%5D%7D%5D%7D',
    );

    assert.strictEqual(response.status, 302, 'HTTP 302 status');
    assert.strictEqual(
      response.headers['location'],
      'http://127.0.0.1:4446/demo/?operatorModeEnabled=true&operatorModeState=%7B%22stacks%22%3A%5B%7B%22items%22%3A%5B%7B%22card%22%3A%7B%22id%22%3A%22http%3A%2F%2Flocalhost%3A4204%2Findex%22%7D%2C%22format%22%3A%22isolated%22%7D%5D%7D%5D%7D',
    );
  });
});
