import {
  currentURL,
  click,
  fillIn,
  triggerKeyEvent,
  waitFor,
  waitUntil,
} from '@ember/test-helpers';

import { setupApplicationTest } from 'ember-qunit';

import window from 'ember-window-mock';
import { setupWindowMock } from 'ember-window-mock/test-support';
import { module, test } from 'qunit';
import stringify from 'safe-stable-stringify';

import { FieldContainer, GridContainer } from '@cardstack/boxel-ui/components';

import {
  baseRealm,
  type LooseSingleCardDocument,
  Deferred,
} from '@cardstack/runtime-common';
import { Realm } from '@cardstack/runtime-common/realm';

import { AuthenticationErrorMessages } from '@cardstack/runtime-common/router';

import { claimsFromRawToken } from '@cardstack/host/resources/realm-session';
import type OperatorModeStateService from '@cardstack/host/services/operator-mode-state-service';
import type RecentCardsService from '@cardstack/host/services/recent-cards-service';

import {
  createJWT,
  percySnapshot,
  setupLocalIndexing,
  setupServerSentEvents,
  setupOnSave,
  testRealmURL,
  testRealmSecretSeed,
  type TestContextWithSSE,
  type TestContextWithSave,
  setupAcceptanceTestRealm,
  visitOperatorMode,
  lookupLoaderService,
} from '../helpers';
import { setupMatrixServiceMock } from '../helpers/mock-matrix-service';

const testRealm2URL = `http://test-realm/test2/`;
let realmPermissions: { [realmURL: string]: ('read' | 'write')[] };

module('Acceptance | interact submode tests', function (hooks) {
  let realm: Realm;

  setupApplicationTest(hooks);
  setupLocalIndexing(hooks);
  setupServerSentEvents(hooks);
  setupOnSave(hooks);
  setupWindowMock(hooks);
  setupMatrixServiceMock(hooks, { realmPermissions: () => realmPermissions });

  hooks.beforeEach(async function () {
    realmPermissions = {
      [testRealmURL]: ['read', 'write'],
      [testRealm2URL]: ['read', 'write'],
    };

    let loader = lookupLoaderService().loader;
    let cardApi: typeof import('https://cardstack.com/base/card-api');
    let string: typeof import('https://cardstack.com/base/string');
    let catalogEntry: typeof import('https://cardstack.com/base/catalog-entry');
    let cardsGrid: typeof import('https://cardstack.com/base/cards-grid');
    cardApi = await loader.import(`${baseRealm.url}card-api`);
    string = await loader.import(`${baseRealm.url}string`);
    catalogEntry = await loader.import(`${baseRealm.url}catalog-entry`);
    cardsGrid = await loader.import(`${baseRealm.url}cards-grid`);

    let {
      field,
      contains,
      containsMany,
      linksTo,
      linksToMany,
      CardDef,
      Component,
      FieldDef,
    } = cardApi;
    let { default: StringField } = string;
    let { CatalogEntry } = catalogEntry;
    let { CardsGrid } = cardsGrid;

    class Pet extends CardDef {
      static displayName = 'Pet';
      @field name = contains(StringField);
      @field favoriteTreat = contains(StringField);

      @field title = contains(StringField, {
        computeVia: function (this: Pet) {
          return this.name;
        },
      });
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          <h3 data-test-pet={{@model.name}}>
            <@fields.name />
          </h3>
        </template>
      };
      static isolated = class Isolated extends Component<typeof this> {
        <template>
          <GridContainer class='container'>
            <h2><@fields.title /></h2>
            <div>
              <div>Favorite Treat: <@fields.favoriteTreat /></div>
              <div data-test-editable-meta>
                {{#if @canEdit}}
                  <@fields.title />
                  is editable.
                {{else}}
                  <@fields.title />
                  is NOT editable.
                {{/if}}
              </div>
            </div>
          </GridContainer>
        </template>
      };
    }

    class ShippingInfo extends FieldDef {
      static displayName = 'Shipping Info';
      @field preferredCarrier = contains(StringField);
      @field remarks = contains(StringField);
      @field title = contains(StringField, {
        computeVia: function (this: ShippingInfo) {
          return this.preferredCarrier;
        },
      });
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          <span data-test-preferredCarrier={{@model.preferredCarrier}}></span>
          <@fields.preferredCarrier />
        </template>
      };
    }

    class Address extends FieldDef {
      static displayName = 'Address';
      @field city = contains(StringField);
      @field country = contains(StringField);
      @field shippingInfo = contains(ShippingInfo);
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          <h3 data-test-city={{@model.city}}>
            <@fields.city />
          </h3>
          <h3 data-test-country={{@model.country}}>
            <@fields.country />
          </h3>
          <div data-test-shippingInfo-field><@fields.shippingInfo /></div>

          <div data-test-editable-meta>
            {{#if @canEdit}}
              address is editable.
            {{else}}
              address is NOT editable.
            {{/if}}
          </div>
        </template>
      };

      static edit = class Edit extends Component<typeof this> {
        <template>
          <FieldContainer @label='city' @tag='label' data-test-boxel-input-city>
            <@fields.city />
          </FieldContainer>
          <FieldContainer
            @label='country'
            @tag='label'
            data-test-boxel-input-country
          >
            <@fields.country />
          </FieldContainer>
          <div data-test-shippingInfo-field><@fields.shippingInfo /></div>
        </template>
      };
    }

    class Person extends CardDef {
      static displayName = 'Person';
      @field firstName = contains(StringField);
      @field pet = linksTo(Pet);
      @field friends = linksToMany(Pet);
      @field firstLetterOfTheName = contains(StringField, {
        computeVia: function (this: Person) {
          if (!this.firstName) {
            return;
          }
          return this.firstName[0];
        },
      });
      @field title = contains(StringField, {
        computeVia: function (this: Person) {
          return this.firstName;
        },
      });
      @field primaryAddress = contains(Address);
      @field additionalAddresses = containsMany(Address);

      static isolated = class Isolated extends Component<typeof this> {
        <template>
          <h2 data-test-person={{@model.firstName}}>
            <@fields.firstName />
          </h2>
          <p data-test-first-letter-of-the-name={{@model.firstLetterOfTheName}}>
            <@fields.firstLetterOfTheName />
          </p>
          Pet:
          <@fields.pet />
          Friends:
          <@fields.friends />
          Primary Address:
          <@fields.primaryAddress />
          Additional Adresses:
          <@fields.additionalAddresses />
        </template>
      };
    }

    let mangoPet = new Pet({ name: 'Mango' });

    ({ realm } = await setupAcceptanceTestRealm({
      contents: {
        'address.gts': { Address },
        'person.gts': { Person },
        'pet.gts': { Pet },
        'shipping-info.gts': { ShippingInfo },
        'README.txt': `Hello World`,
        'person-entry.json': new CatalogEntry({
          title: 'Person Card',
          description: 'Catalog entry for Person Card',
          isField: false,
          ref: {
            module: `${testRealmURL}person`,
            name: 'Person',
          },
        }),
        'Pet/mango.json': mangoPet,
        'Pet/vangogh.json': new Pet({ name: 'Van Gogh' }),
        'Person/fadhlan.json': new Person({
          firstName: 'Fadhlan',
          address: new Address({
            city: 'Bandung',
            country: 'Indonesia',
            shippingInfo: new ShippingInfo({
              preferredCarrier: 'DHL',
              remarks: `Don't let bob deliver the package--he's always bringing it to the wrong address`,
            }),
          }),
          additionalAddresses: [
            new Address({
              city: 'Jakarta',
              country: 'Indonesia',
              shippingInfo: new ShippingInfo({
                preferredCarrier: 'FedEx',
                remarks: `Make sure to deliver to the back door`,
              }),
            }),
            new Address({
              city: 'Bali',
              country: 'Indonesia',
              shippingInfo: new ShippingInfo({
                preferredCarrier: 'UPS',
                remarks: `Call ahead to make sure someone is home`,
              }),
            }),
          ],
          pet: mangoPet,
          friends: [mangoPet],
        }),
        'grid.json': new CardsGrid(),
        'index.json': new CardsGrid(),
        '.realm.json': {
          name: 'Test Workspace B',
          backgroundURL:
            'https://i.postimg.cc/VNvHH93M/pawel-czerwinski-Ly-ZLa-A5jti-Y-unsplash.jpg',
          iconURL: 'https://i.postimg.cc/L8yXRvws/icon.png',
        },
      },
    }));
    await setupAcceptanceTestRealm({
      realmURL: testRealm2URL,
      contents: {
        'index.json': new CardsGrid(),
        '.realm.json': {
          name: 'Test Workspace A',
          backgroundURL:
            'https://i.postimg.cc/tgRHRV8C/pawel-czerwinski-h-Nrd99q5pe-I-unsplash.jpg',
          iconURL: 'https://i.postimg.cc/d0B9qMvy/icon.png',
        },
        'Pet/ringo.json': new Pet({ name: 'Ringo' }),
        'Person/hassan.json': new Person({
          firstName: 'Hassan',
          pet: mangoPet,
          additionalAddresses: [
            new Address({
              city: 'New York',
              country: 'USA',
              shippingInfo: new ShippingInfo({
                preferredCarrier: 'DHL',
                remarks: `Don't let bob deliver the package--he's always bringing it to the wrong address`,
              }),
            }),
          ],
          friends: [mangoPet],
        }),
      },
    });
  });

  module('0 stacks', function () {
    test('Clicking card in search panel opens card on a new stack', async function (assert) {
      await visitOperatorMode({});

      await waitFor('[data-test-search-sheet="closed"]');
      assert.dom('[data-test-operator-mode-stack]').doesNotExist();
      assert.dom('[data-test-search-sheet]').doesNotHaveClass('prompt'); // Search closed

      // Click on search-input
      await click('[data-test-search-field]');

      assert.dom('[data-test-search-sheet]').hasClass('prompt'); // Search opened

      await fillIn('[data-test-search-field]', 'Mango');

      assert.dom('[data-test-search-sheet]').hasClass('results'); // Search open

      await waitFor(`[data-test-search-result="${testRealmURL}Pet/mango"]`, {
        timeout: 2000,
      });

      // Click on search result
      await click(`[data-test-search-result="${testRealmURL}Pet/mango"]`);

      assert.dom('[data-test-search-sheet]').doesNotHaveClass('results'); // Search closed

      // The card appears on a new stack
      await waitFor('[data-test-operator-mode-stack]');

      assert.dom('[data-test-operator-mode-stack]').exists({ count: 1 });
      assert
        .dom(
          '[data-test-operator-mode-stack="0"] [data-test-stack-card-index="0"]',
        )
        .includesText('Mango');
      assert
        .dom(
          '[data-test-operator-mode-stack="0"] [data-test-stack-card-index="1"]',
        )
        .doesNotExist();
      assert.dom('[data-test-search-field]').hasValue('');
    });

    test('Can add a card by URL using the add button', async function (assert) {
      await visitOperatorMode({});

      assert.dom('[data-test-operator-mode-stack]').doesNotExist();

      await waitFor('[data-test-add-card-button]');
      await click('[data-test-add-card-button]');
      await waitFor('[data-test-card-catalog]');
      await fillIn(
        '[data-test-card-catalog-modal] [data-test-search-field]',
        `${testRealmURL}index`,
      );

      await waitFor(`[data-test-card-catalog-item="${testRealmURL}index"]`, {
        timeout: 2000,
      });
      assert.dom('[data-test-card-catalog-item]').hasText('Test Workspace B');

      await click(`[data-test-select="${testRealmURL}index"]`);
      await click('[data-test-card-catalog-go-button]');
      await waitFor('[data-test-card-catalog]', { count: 0 });
      assert.dom('[data-test-operator-mode-stack]').exists({ count: 1 });
      assert.dom('[data-test-stack-card-index]').exists({ count: 1 });
      assert.dom('[data-test-stack-card-header]').hasText('Test Workspace B');
    });

    test('Can add an index card by URL (without "index" in path) using the add button', async function (assert) {
      const wrongURL = 'https://example.test/this/is/a/wrong/url';
      await visitOperatorMode({});

      assert.dom('[data-test-operator-mode-stack]').doesNotExist();

      await waitFor('[data-test-add-card-button]');
      await click('[data-test-add-card-button]');
      await waitFor('[data-test-card-catalog]');
      await fillIn(
        '[data-test-card-catalog-modal] [data-test-search-field]',
        wrongURL,
      );

      await waitFor('[data-test-boxel-input-error-message]', {
        timeout: 2000,
      });
      assert
        .dom('[data-test-boxel-input-error-message]')
        .hasText(`Could not find card at ${wrongURL}`);
      assert.dom('[data-test-boxel-input-validation-state="invalid"]').exists();

      await fillIn(
        '[data-test-card-catalog-modal] [data-test-search-field]',
        baseRealm.url.slice(0, -1),
      );
      await waitFor(`[data-test-card-catalog-item="${baseRealm.url}index"]`, {
        timeout: 2000,
      });
      assert.dom('[data-test-card-catalog-item]').hasText('Base Workspace');

      await fillIn(
        '[data-test-card-catalog-modal] [data-test-search-field]',
        testRealmURL,
      );
      await waitFor(`[data-test-card-catalog-item="${testRealmURL}index"]`, {
        timeout: 2000,
      });
      assert.dom('[data-test-card-catalog-item]').hasText('Test Workspace B');
      assert.dom('[data-test-boxel-input-error-message]').doesNotExist();
      assert
        .dom('[data-test-boxel-input-validation-state="invalid"]')
        .doesNotExist();

      await click(`[data-test-select="${testRealmURL}index"]`);
      await click('[data-test-card-catalog-go-button]');
      await waitFor('[data-test-card-catalog]', { count: 0 });
      assert.dom('[data-test-operator-mode-stack]').exists({ count: 1 });
      assert.dom('[data-test-stack-card-index]').exists({ count: 1 });
      assert.dom('[data-test-stack-card-header]').hasText('Test Workspace B');
    });

    test('Can open a recent card in empty stack', async function (assert) {
      await visitOperatorMode({});

      await waitFor('[data-test-add-card-button]');
      await click('[data-test-add-card-button]');

      await waitFor('[data-test-search-field]');
      await click('[data-test-search-field]');
      await fillIn('[data-test-search-field]', `${testRealmURL}person-entry`);

      await waitFor(
        `[data-test-card-catalog-item="${testRealmURL}person-entry"]`,
      );
      await waitFor('[data-test-card-catalog-item]', {
        count: 1,
      });

      assert.dom('[data-test-realm-filter-button]').isDisabled();

      assert
        .dom(`[data-test-realm="Test Workspace B"] [data-test-results-count]`)
        .hasText('1 result');

      assert.dom('[data-test-card-catalog-item]').exists({ count: 1 });
      await click('[data-test-select]');

      await waitFor('[data-test-card-catalog-go-button][disabled]', {
        count: 0,
      });
      await click('[data-test-card-catalog-go-button]');
      await waitFor(`[data-test-stack-card="${testRealmURL}person-entry"]`);

      assert
        .dom(`[data-test-stack-card="${testRealmURL}person-entry"]`)
        .containsText('Test Workspace B');

      // Close the card, find it in recent cards, and reopen it
      await click(
        `[data-test-stack-card="${testRealmURL}person-entry"] [data-test-close-button]`,
      );
      await waitFor(`[data-test-stack-card="${testRealmURL}person-entry"]`, {
        count: 0,
      });
      assert.dom('[data-test-add-card-button]').exists('stack is empty');

      await click('[data-test-search-field]');
      assert.dom('[data-test-search-sheet]').hasClass('prompt');

      await waitFor(`[data-test-search-result="${testRealmURL}person-entry"]`);
      await click(`[data-test-search-result="${testRealmURL}person-entry"]`);

      await waitFor(`[data-test-stack-card="${testRealmURL}person-entry"]`);
      assert
        .dom(`[data-test-stack-card="${testRealmURL}person-entry"]`)
        .exists();
    });

    test('Handles a URL with no results', async function (assert) {
      await visitOperatorMode({});

      await waitFor('[data-test-add-card-button]');
      await click('[data-test-add-card-button]');

      await waitFor('[data-test-search-field]');
      await fillIn(
        '[data-test-search-field]',
        `${testRealmURL}xyz-does-not-exist`,
      );

      await waitFor('[data-test-card-catalog]');
      await waitFor('[data-test-card-catalog-item]', { count: 0 });
      assert.dom(`[data-test-card-catalog]`).hasText('No cards available');
    });
  });

  module('1 stack', function () {
    test('restoring the stack from query param', async function (assert) {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}Person/fadhlan`,
              format: 'isolated',
            },
            {
              id: `${testRealmURL}Pet/mango`,
              format: 'isolated',
            },
          ],
        ],
      });

      await percySnapshot(assert);

      assert
        .dom('[data-test-stack-card-index="0"] [data-test-boxel-header-title]')
        .includesText('Person');

      assert
        .dom('[data-test-stack-card-index="1"] [data-test-boxel-header-title]')
        .includesText('Pet');

      // Remove mango (the dog) from the stack
      await click('[data-test-stack-card-index="1"] [data-test-close-button]');

      assert.operatorModeParametersMatch(currentURL(), {
        stacks: [
          [
            {
              id: `${testRealmURL}Person/fadhlan`,
              format: 'isolated',
            },
          ],
        ],
      });

      await waitFor('[data-test-operator-mode-stack] [data-test-pet="Mango"]');
      await click('[data-test-operator-mode-stack] [data-test-pet="Mango"]');
      let expectedURL = `/?operatorModeEnabled=true&operatorModeState=${encodeURIComponent(
        stringify({
          stacks: [
            [
              {
                id: `${testRealmURL}Person/fadhlan`,
                format: 'isolated',
              },
              {
                id: `${testRealmURL}Pet/mango`,
                format: 'isolated',
              },
            ],
          ],
          submode: 'interact',
          fileView: 'inspector',
          openDirs: {},
        })!,
      )}`;
      // There is some additional thing we are waiting on here, probably the
      // card to load in the card resource, but I'm not too sure so using waitUntil instead
      await waitUntil(() => currentURL() === expectedURL);
      assert.strictEqual(currentURL(), expectedURL);

      // Click Edit on the top card
      await click('[data-test-stack-card-index="1"] [data-test-edit-button]');

      // The edit format should be reflected in the URL
      assert.strictEqual(
        currentURL(),
        `/?operatorModeEnabled=true&operatorModeState=${encodeURIComponent(
          stringify({
            stacks: [
              [
                {
                  id: `${testRealmURL}Person/fadhlan`,
                  format: 'isolated',
                },
                {
                  id: `${testRealmURL}Pet/mango`,
                  format: 'edit',
                },
              ],
            ],
            submode: 'interact',
            fileView: 'inspector',
            openDirs: {},
          })!,
        )}`,
      );
    });

    test('restoring the stack from query param when card is in edit format', async function (assert) {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}Person/fadhlan`,
              format: 'edit',
            },
          ],
        ],
      });

      await percySnapshot(assert);

      assert.dom('[data-test-field="firstName"] input').exists(); // Existence of an input field means it is in edit mode
    });

    test('click left or right add card button will open the search panel and then click on a recent card will open a new stack on the left or right', async function (assert) {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}Person/fadhlan`,
              format: 'isolated',
            },
            {
              id: `${testRealmURL}Pet/mango`,
              format: 'edit',
            },
          ],
        ],
      });

      let operatorModeStateService = this.owner.lookup(
        'service:operator-mode-state-service',
      ) as OperatorModeStateService;
      let recentCardsService = this.owner.lookup(
        'service:recent-cards-service',
      ) as RecentCardsService;

      let firstStack = operatorModeStateService.state.stacks[0];
      // @ts-ignore Property '#private' is missing in type 'Card[]' but required in type 'TrackedArray<Card>'.glint(2741) - don't care about this error here, just stubbing
      recentCardsService.recentCards = firstStack.map((item) => item.card);

      assert.dom('[data-test-operator-mode-stack]').exists({ count: 1 });
      assert.dom('[data-test-add-card-left-stack]').exists();
      assert.dom('[data-test-add-card-right-stack]').exists();
      assert.dom('[data-test-search-sheet]').doesNotHaveClass('prompt'); // Search closed

      // Add a card to the left stack
      await click('[data-test-add-card-left-stack]');

      assert.dom('[data-test-search-field]').isFocused();
      assert.dom('[data-test-search-sheet]').hasClass('prompt'); // Search opened

      await click(`[data-test-search-result="${testRealmURL}Pet/mango"]`);
      // There is some additional thing we are waiting on here, probably the
      // card to load in the card resource, but I'm not too sure so using waitUntil instead
      await waitUntil(() =>
        document
          .querySelector('[data-test-operator-mode-stack="0"]')
          ?.textContent?.includes('Mango'),
      );

      assert.dom('[data-test-search-sheet]').doesNotHaveClass('prompt'); // Search closed

      // There are now 2 stacks

      assert.dom('[data-test-operator-mode-stack]').exists({ count: 2 });
      assert.dom('[data-test-operator-mode-stack="0"]').includesText('Mango'); // Mango goes on the left stack
      assert.dom('[data-test-operator-mode-stack="1"]').includesText('Fadhlan');

      // Buttons to add a neighbor stack are gone
      assert.dom('[data-test-add-card-left-stack]').doesNotExist();
      assert.dom('[data-test-add-card-right-stack]').doesNotExist();

      // Close the only card in the 1st stack
      await click(
        '[data-test-operator-mode-stack="0"] [data-test-close-button]',
      );

      // There is now only 1 stack and the buttons to add a neighbor stack are back
      assert.dom('[data-test-operator-mode-stack]').exists({ count: 1 });
      assert.dom('[data-test-add-card-left-stack]').exists();
      assert.dom('[data-test-add-card-right-stack]').exists();

      // Add a card to the right stack
      await click('[data-test-add-card-left-stack]');

      assert.dom('[data-test-search-sheet]').hasClass('prompt'); // Search opened

      await click(`[data-test-search-result="${testRealmURL}Person/fadhlan"]`);

      assert.dom('[data-test-search-sheet]').doesNotHaveClass('prompt'); // Search closed

      // There are now 2 stacks
      await waitFor('[data-test-operator-mode-stack="0"]');
      assert.dom('[data-test-operator-mode-stack]').exists({ count: 2 });
      assert.dom('[data-test-operator-mode-stack="0"]').includesText('Fadhlan');
      assert.dom('[data-test-operator-mode-stack="1"]').includesText('Mango'); // Mango gets move onto the right stack

      // Buttons to add a neighbor stack are gone
      assert.dom('[data-test-add-card-left-stack]').doesNotExist();
      assert.dom('[data-test-add-card-right-stack]').doesNotExist();

      // Close the only card in the 1st stack
      await click(
        '[data-test-operator-mode-stack="0"] [data-test-close-button]',
      );
      // There is some additional thing we are waiting on here, probably the
      // card to load in the card resource, but I'm not too sure so using waitUntil instead
      await waitUntil(
        () =>
          document.querySelectorAll('[data-test-operator-mode-stack]')
            .length === 1,
      );

      // There is now only 1 stack and the buttons to add a neighbor stack are back
      assert.dom('[data-test-operator-mode-stack]').exists({ count: 1 });
      assert.dom('[data-test-add-card-left-stack]').exists();
      assert.dom('[data-test-add-card-right-stack]').exists();

      // Replace the current stack by interacting with search prompt directly
      // Click on search-input
      await click('[data-test-search-field]');

      assert.dom('[data-test-search-sheet]').hasClass('prompt'); // Search opened

      await click(`[data-test-search-result="${testRealmURL}Person/fadhlan"]`);

      assert.dom('[data-test-search-sheet]').doesNotHaveClass('prompt'); // Search closed

      // There is still only 1 stack
      assert.dom('[data-test-operator-mode-stack]').exists({ count: 1 });
    });

    test('Clicking search panel (without left and right buttons activated) replaces open card on existing stack', async function (assert) {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}Person/fadhlan`,
              format: 'isolated',
            },
            {
              id: `${testRealmURL}Pet/mango`,
              format: 'isolated',
            },
          ],
        ],
      });

      let operatorModeStateService = this.owner.lookup(
        'service:operator-mode-state-service',
      ) as OperatorModeStateService;
      let recentCardsService = this.owner.lookup(
        'service:recent-cards-service',
      ) as RecentCardsService;

      // @ts-ignore Property '#private' is missing in type 'Card[]' but required in type 'TrackedArray<Card>'.glint(2741) - don't care about this error here, just stubbing
      recentCardsService.recentCards =
        operatorModeStateService.state.stacks[0].map((item) => item.card);

      assert.dom('[data-test-operator-mode-stack]').exists({ count: 1 });
      assert.dom('[data-test-add-card-left-stack]').exists();
      assert.dom('[data-test-add-card-right-stack]').exists();
      assert.dom('[data-test-search-sheet]').doesNotHaveClass('prompt'); // Search closed

      // Click on search-input
      await click('[data-test-search-field]');

      assert.dom('[data-test-search-sheet]').hasClass('prompt'); // Search opened

      // Click on a recent search
      await click(`[data-test-search-result="${testRealmURL}Pet/mango"]`);
      // There is some additional thing we are waiting on here, probably the
      // card to load in the card resource, but I'm not too sure so using waitUntil instead
      await waitUntil(
        () =>
          document.querySelectorAll(
            '[data-test-operator-mode-stack="0"] [data-test-stack-card-index="1"]',
          ).length === 0,
      );

      assert.dom('[data-test-search-sheet]').doesNotHaveClass('prompt'); // Search closed

      // The recent card REPLACES onto on current stack
      assert.dom('[data-test-operator-mode-stack]').exists({ count: 1 });
      assert
        .dom(
          '[data-test-operator-mode-stack="0"] [data-test-stack-card-index="0"]',
        )
        .includesText('Mango');
      assert
        .dom(
          '[data-test-operator-mode-stack="0"] [data-test-stack-card-index="1"]',
        )
        .doesNotExist();
    });

    test('search can be dismissed with escape', async function (assert) {
      await visitOperatorMode({});
      await waitFor('[data-test-search-sheet="closed"]');
      await click('[data-test-search-field]');

      assert.dom('[data-test-search-sheet]').hasClass('prompt');

      await triggerKeyEvent(
        '[data-test-search-sheet] input',
        'keydown',
        'Escape',
      );

      assert.dom('[data-test-search-sheet]').hasClass('closed');
    });

    test<TestContextWithSave>('can create a card from the index stack item', async function (assert) {
      assert.expect(4);
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}index`,
              format: 'isolated',
            },
          ],
        ],
      });
      let deferred = new Deferred<void>();
      this.onSave((_, json) => {
        if (typeof json === 'string') {
          throw new Error('expected JSON save data');
        }
        if (json.data.attributes?.firstName === null) {
          // Because we create an empty card, upon choosing a catalog item, we must skip the scenario where attributes null
          return;
        }
        assert.strictEqual(json.data.attributes?.firstName, 'Hassan');
        assert.strictEqual(json.data.meta.realmURL, testRealmURL);
        deferred.fulfill();
      });
      await click('[data-test-create-new-card-button]');
      await waitFor(
        `[data-test-card-catalog-item="${testRealmURL}person-entry"]`,
      );
      await click(`[data-test-select="${testRealmURL}person-entry"]`);
      await click('[data-test-card-catalog-go-button]');

      await waitFor('[data-test-stack-card-index="1"]');
      await fillIn(`[data-test-field="firstName"] input`, 'Hassan');
      await click('[data-test-stack-card-index="1"] [data-test-close-button]');

      await deferred.promise;
    });

    test<TestContextWithSave>('duplicate card in a stack is not allowed', async function (assert) {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}index`,
              format: 'isolated',
            },
          ],
        ],
      });

      await waitFor(
        `[data-test-operator-mode-stack="0"] [data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`,
      );
      // Simulate simultaneous clicks for spam-clicking
      await Promise.all([
        click(
          `[data-test-operator-mode-stack="0"] [data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`,
        ),
        click(
          `[data-test-operator-mode-stack="0"] [data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`,
        ),
      ]);

      await waitFor(`[data-stack-card="${testRealmURL}Person/fadhlan"]`);
      assert
        .dom(`[data-stack-card="${testRealmURL}Person/fadhlan"]`)
        .exists({ count: 1 });
    });

    test('embedded card from writable realm shows pencil icon in edit mode', async (assert) => {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealm2URL}Person/hassan`,
              format: 'edit',
            },
          ],
        ],
      });
      assert
        .dom(
          `[data-test-overlay-card="${testRealmURL}Pet/mango"] [data-test-embedded-card-edit-button]`,
        )
        .exists();
      await click(
        `[data-test-overlay-card="${testRealmURL}Pet/mango"] [data-test-embedded-card-edit-button]`,
      );
      await waitFor(`[data-test-stack-card="${testRealmURL}Pet/mango"]`);
      assert
        .dom(
          `[data-test-stack-card="${testRealmURL}Pet/mango"] [data-test-card-format="edit"]`,
        )
        .exists('linked card now rendered as a stack item in edit format');
    });

    module('when the user lacks write permissions', function (hooks) {
      hooks.beforeEach(async function () {
        realmPermissions = {
          [testRealmURL]: ['read'],
          [testRealm2URL]: ['read', 'write'],
        };
      });

      test('the edit button is hidden when the user lacks permissions', async function (assert) {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${testRealmURL}Pet/mango`,
                format: 'isolated',
              },
            ],
          ],
        });

        assert.dom('[data-test-edit-button]').doesNotExist();
      });

      test('the card format components are informed whether it is editable', async function (assert) {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${testRealmURL}Pet/mango`,
                format: 'isolated',
              },
            ],
          ],
        });

        assert
          .dom('[data-test-editable-meta]')
          .containsText('Mango is NOT editable');

        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${testRealm2URL}Pet/ringo`,
                format: 'isolated',
              },
            ],
          ],
        });

        assert
          .dom('[data-test-editable-meta]')
          .containsText('Ringo is editable');

        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${testRealmURL}Person/fadhlan`,
                format: 'isolated',
              },
            ],
          ],
        });

        assert
          .dom('[data-test-editable-meta]')
          .containsText('address is NOT editable');

        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${testRealmURL}Person/fadhlan`,
                format: 'edit',
              },
            ],
          ],
        });

        assert
          .dom("[data-test-contains-many='additionalAddresses'] input:enabled")
          .doesNotExist();

        assert
          .dom(
            "[data-test-contains-many='additionalAddresses'] [data-test-remove]",
          )
          .doesNotExist();
        assert
          .dom(
            "[data-test-contains-many='additionalAddresses'] [data-test-add-new]",
          )
          .doesNotExist();

        assert
          .dom("[data-test-field='pet'] [data-test-remove-card]")
          .doesNotExist();

        assert
          .dom("[data-test-field='friends'] [data-test-add-new]")
          .doesNotExist();
        assert
          .dom("[data-test-field='friends'] [data-test-remove-card]")
          .doesNotExist();

        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${testRealm2URL}Person/hassan`,
                format: 'isolated',
              },
            ],
          ],
        });

        assert
          .dom('[data-test-editable-meta]')
          .containsText('address is editable');

        await click('[data-test-operator-mode-stack] [data-test-edit-button]');

        assert
          .dom("[data-test-contains-many='additionalAddresses'] input:disabled")
          .doesNotExist();

        assert
          .dom(
            "[data-test-contains-many='additionalAddresses'] [data-test-remove]",
          )
          .exists();

        assert
          .dom(
            "[data-test-contains-many='additionalAddresses'] [data-test-add-new]",
          )
          .exists();

        assert.dom("[data-test-field='pet'] [data-test-remove-card]").exists();
        assert.dom("[data-test-field='friends'] [data-test-add-new]").exists();
        assert
          .dom("[data-test-field='friends'] [data-test-remove-card]")
          .exists();
      });
      test('the delete item is not present in "..." menu of stack item', async function (assert) {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${testRealmURL}Pet/mango`,
                format: 'isolated',
              },
            ],
          ],
        });
        await waitFor('[data-test-more-options-button]');
        await click('[data-test-more-options-button]');
        assert
          .dom('[data-test-boxel-menu-item-text="Delete"]')
          .doesNotExist('delete menu item is not rendered');
      });

      test('the "..."" menu does not exist for card overlay in index view (since delete is the only item in this menu)', async function (assert) {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${testRealmURL}index`,
                format: 'isolated',
              },
            ],
          ],
        });
        await waitFor(
          `[data-test-operator-mode-stack="0"] [data-test-cards-grid-item="${testRealmURL}Pet/mango"]`,
        );
        assert
          .dom(
            `[data-test-overlay-card="${testRealmURL}Pet/mango"] button.more-actions`,
          )
          .doesNotExist('"..." menu does not exist');
      });

      test('embedded card from read-only realm does not show pencil icon in edit mode', async (assert) => {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${testRealm2URL}Person/hassan`,
                format: 'edit',
              },
            ],
          ],
        });
        assert
          .dom(`[data-test-overlay-card="${testRealmURL}Pet/mango"]`)
          .exists();
        assert
          .dom(
            `[data-test-overlay-card="${testRealmURL}Pet/mango"] [data-test-embedded-card-edit-button]`,
          )
          .doesNotExist('edit icon not displayed for linked card');
        await click(
          `[data-test-links-to-editor="pet"] [data-test-field-component-card]`,
        );
        await waitFor(`[data-test-stack-card="${testRealmURL}Pet/mango"]`);
        assert
          .dom(
            `[data-test-stack-card="${testRealmURL}Pet/mango"] [data-test-card-format="isolated"]`,
          )
          .exists(
            'linked card now rendered as a stack item in isolated (non-edit) format',
          );
      });
    });

    module(
      'when permission is updated after user has obtained the token',
      function (hooks) {
        hooks.beforeEach(async function () {
          realmPermissions = { [testRealmURL]: ['read'] };
        });

        test('retrieve a new JWT on 401 error', async function (assert) {
          let token = createJWT(
            {
              user: '@testuser:staging',
              realm: testRealmURL,
              permissions: ['read', 'write'],
            },
            '7d',
            testRealmSecretSeed,
          );
          let session = {
            [`${testRealmURL}`]: token,
          };
          window.localStorage.setItem('boxel-session', JSON.stringify(session));

          await visitOperatorMode({
            stacks: [
              [
                {
                  id: `${testRealmURL}Pet/mango`,
                  format: 'isolated',
                },
              ],
            ],
          });

          lookupLoaderService().virtualNetwork.mount(
            async (req) => {
              // Mock `Authentication` error response from the server.
              if (
                req.method !== 'GET' &&
                req.method !== 'HEAD' &&
                req.headers.get('Authorization') === token
              ) {
                return new Response(
                  AuthenticationErrorMessages.PermissionMismatch,
                  {
                    status: 401,
                  },
                );
              }
              return null;
            },
            { prepend: true },
          );
          assert
            .dom('[data-test-operator-mode-stack] [data-test-edit-button]')
            .exists();
          await click(
            '[data-test-operator-mode-stack] [data-test-edit-button]',
          );
          await fillIn(
            '[data-test-operator-mode-stack] [data-test-field="name"] [data-test-boxel-input]',
            'Updated Ringo',
          );
          await click(
            '[data-test-operator-mode-stack] [data-test-edit-button]',
          );

          let newToken = window.localStorage.getItem('boxel-session');
          let claims = claimsFromRawToken(newToken!);
          assert.notStrictEqual(newToken, token);
          assert.strictEqual(claims.user, '@testuser:staging');
          assert.deepEqual(claims.permissions, ['read']);
        });
      },
    );
  });

  module('2 stacks with differing permissions', function (hooks) {
    hooks.beforeEach(async function () {
      realmPermissions = {
        [testRealmURL]: ['read'],
        [testRealm2URL]: ['read', 'write'],
      };
    });

    test('the edit button respects the realm permissions of the cards in differing realms', async function (assert) {
      assert.expect(10);
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}Pet/mango`,
              format: 'isolated',
            },
          ],
          [
            {
              id: `${testRealm2URL}Pet/ringo`,
              format: 'isolated',
            },
          ],
        ],
      });

      lookupLoaderService().virtualNetwork.mount(
        async (req) => {
          if (req.method !== 'GET' && req.method !== 'HEAD') {
            let token = req.headers.get('Authorization');
            assert.notStrictEqual(token, null);

            let claims = claimsFromRawToken(token!);
            assert.deepEqual(claims.user, '@testuser:staging');
            assert.strictEqual(claims.realm, 'http://test-realm/test2/');
            assert.deepEqual(claims.permissions, ['read', 'write']);
          }
          return null;
        },
        { prepend: true },
      );

      assert
        .dom('[data-test-operator-mode-stack="0"] [data-test-edit-button]')
        .doesNotExist();
      assert
        .dom('[data-test-operator-mode-stack="1"] [data-test-edit-button]')
        .exists();
      await click(
        '[data-test-operator-mode-stack="1"] [data-test-edit-button]',
      );
      await fillIn(
        '[data-test-operator-mode-stack="1"] [data-test-field="name"] [data-test-boxel-input]',
        'Updated Ringo',
      );
      await click(
        '[data-test-operator-mode-stack="1"] [data-test-edit-button]',
      );
    });

    test('the delete item in "..." menu of stack item respects realm permissions of the cards in differing realms', async function (assert) {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}Pet/mango`,
              format: 'isolated',
            },
          ],
          [
            {
              id: `${testRealm2URL}Pet/ringo`,
              format: 'isolated',
            },
          ],
        ],
      });
      await waitFor(
        '[data-test-operator-mode-stack="0"] [data-test-more-options-button]',
      );
      await click(
        '[data-test-operator-mode-stack="0"] [data-test-more-options-button]',
      );
      assert
        .dom('[data-test-boxel-menu-item-text="Delete"]')
        .doesNotExist('delete menu item is not rendered');

      await waitFor(
        '[data-test-operator-mode-stack="1"] [data-test-more-options-button]',
      );
      await click(
        '[data-test-operator-mode-stack="1"] [data-test-more-options-button]',
      );
      assert
        .dom('[data-test-boxel-menu-item-text="Delete"]')
        .exists('delete menu is rendered');
    });

    test('the "..."" menu for card overlay in index view respects realm permissions of cards in differing realms', async function (assert) {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}index`,
              format: 'isolated',
            },
          ],
          [
            {
              id: `${testRealm2URL}index`,
              format: 'isolated',
            },
          ],
        ],
      });
      await waitFor(
        `[data-test-operator-mode-stack="0"] [data-test-cards-grid-item="${testRealmURL}Pet/mango"]`,
      );
      assert
        .dom(
          `[data-test-operator-mode-stack="0"] [data-test-overlay-card="${testRealmURL}Pet/mango"] button.more-actions`,
        )
        .doesNotExist('"..." menu does not exist');

      await waitFor(
        `[data-test-operator-mode-stack="1"] [data-test-cards-grid-item="${testRealm2URL}Pet/ringo"]`,
      );
      assert
        .dom(
          `[data-test-operator-mode-stack="1"] [data-test-overlay-card="${testRealm2URL}Pet/ringo"] button.more-actions`,
        )
        .exists('"..." menu exists');
    });
  });

  module('2 stacks', function () {
    test('restoring the stacks from query param', async function (assert) {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}Person/fadhlan`,
              format: 'isolated',
            },
          ],
          [
            {
              id: `${testRealmURL}Pet/mango`,
              format: 'isolated',
            },
          ],
        ],
      });

      await percySnapshot(assert); // 2 stacks from the same realm share the same background

      assert.dom('[data-test-operator-mode-stack]').exists({ count: 2 });
      assert.dom('[data-test-operator-mode-stack="0"]').includesText('Fadhlan');
      assert.dom('[data-test-operator-mode-stack="1"]').includesText('Mango');

      // Close the card in the 2nd stack
      await click(
        '[data-test-operator-mode-stack="1"] [data-test-close-button]',
      );
      assert.dom('[data-test-operator-mode-stack="0"]').exists();

      // 2nd stack is removed, 1st stack remains
      assert.dom('[data-test-operator-mode-stack="1"]').doesNotExist();
      assert.dom('[data-test-operator-mode-stack="0"]').includesText('Fadhlan');

      assert.operatorModeParametersMatch(currentURL(), {
        stacks: [
          [
            {
              id: `${testRealmURL}Person/fadhlan`,
              format: 'isolated',
            },
          ],
        ],
      });

      // Close the last card in the last stack that is left - should get the empty state
      await click(
        '[data-test-operator-mode-stack="0"] [data-test-close-button]',
      );

      assert.dom('.no-cards').includesText('Add a card to get started');
    });

    test('visiting 2 stacks from differing realms', async function (assert) {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}Person/fadhlan`,
              format: 'isolated',
            },
          ],
          [
            {
              id: 'http://localhost:4202/test/hassan',
              format: 'isolated',
            },
          ],
        ],
      });

      await percySnapshot(assert); // 2 stacks from the different realms have different backgrounds

      assert.dom('[data-test-operator-mode-stack]').exists({ count: 2 });
    });

    test('Clicking search panel (without left and right buttons activated) replaces all cards in the rightmost stack', async function (assert) {
      // creates a recent search
      window.localStorage.setItem(
        'recent-cards',
        JSON.stringify([`${testRealmURL}Person/fadhlan`]),
      );

      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${testRealmURL}Person/fadhlan`,
              format: 'isolated',
            },
          ],
          [
            {
              id: `${testRealmURL}index`,
              format: 'isolated',
            },
            {
              id: `${testRealmURL}Pet/mango`,
              format: 'isolated',
            },
          ],
        ],
      });

      assert.dom('[data-test-operator-mode-stack]').exists({ count: 2 });

      // Click on search-input
      await click('[data-test-search-field]');

      assert.dom('[data-test-search-sheet]').hasClass('prompt'); // Search opened

      // Click on a recent search
      await click(`[data-test-search-result="${testRealmURL}Person/fadhlan"]`);

      // We have to wait untill there is only one stack item in rightmost stack,
      // because that's the expected behaviour when we open a card from card search.
      await waitUntil(
        () =>
          document.querySelectorAll(
            '[data-test-operator-mode-stack="1"] [data-test-stack-card-index]',
          )?.length === 1,
      );

      assert.dom('[data-test-search-sheet]').doesNotHaveClass('prompt'); // Search closed

      assert.dom('[data-test-operator-mode-stack]').exists({ count: 2 });
      assert
        .dom(
          '[data-test-operator-mode-stack="0"] [data-test-stack-card-index="0"]',
        )
        .includesText('Fadhlan');
      assert
        .dom(
          '[data-test-operator-mode-stack="0"] [data-test-stack-card-index="1"]',
        )
        .doesNotExist();
      assert
        .dom(
          '[data-test-operator-mode-stack="1"] [data-test-stack-card-index="0"]',
        )
        .includesText('Fadhlan');
      assert
        .dom(
          '[data-test-operator-mode-stack="1"] [data-test-stack-card-index="1"]',
        )
        .doesNotExist();
    });
  });

  test<TestContextWithSSE>('stack item live updates when index changes', async function (assert) {
    assert.expect(3);
    let expectedEvents = [
      {
        type: 'index',
        data: {
          type: 'incremental',
          invalidations: [`${testRealmURL}Person/fadhlan`],
        },
      },
    ];
    await visitOperatorMode({
      stacks: [
        [
          {
            id: `${testRealmURL}Person/fadhlan`,
            format: 'isolated',
          },
        ],
      ],
    });
    assert
      .dom('[data-test-operator-mode-stack="0"] [data-test-person]')
      .hasText('Fadhlan');
    await this.expectEvents({
      assert,
      realm,
      expectedEvents,
      callback: async () => {
        await realm.write(
          'Person/fadhlan.json',
          JSON.stringify({
            data: {
              type: 'card',
              attributes: {
                firstName: 'FadhlanXXX',
              },
              meta: {
                adoptsFrom: {
                  module: '../person',
                  name: 'Person',
                },
              },
            },
          } as LooseSingleCardDocument),
        );
      },
    });

    await waitUntil(() =>
      document
        .querySelector('[data-test-operator-mode-stack="0"] [data-test-person]')
        ?.textContent?.includes('FadhlanXXX'),
    );
    assert
      .dom('[data-test-operator-mode-stack="0"] [data-test-person]')
      .hasText('FadhlanXXX');
  });
});
