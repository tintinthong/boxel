import {
  visit,
  currentURL,
  click,
  triggerEvent,
  waitFor,
  fillIn,
  waitUntil,
} from '@ember/test-helpers';

import { setupApplicationTest } from 'ember-qunit';

import window from 'ember-window-mock';
import { setupWindowMock } from 'ember-window-mock/test-support';
import { module, test } from 'qunit';

import { FieldContainer } from '@cardstack/boxel-ui/components';

import { baseRealm, primitive } from '@cardstack/runtime-common';

import { Submodes } from '@cardstack/host/components/submode-switcher';
import {
  tokenRefreshPeriodSec,
  sessionLocalStorageKey,
} from '@cardstack/host/resources/realm-session';

import {
  percySnapshot,
  setupLocalIndexing,
  setupServerSentEvents,
  setupOnSave,
  testRealmURL,
  setupAcceptanceTestRealm,
  visitOperatorMode,
  lookupLoaderService,
} from '../helpers';
import {
  MockMatrixService,
  setupMatrixServiceMock,
} from '../helpers/mock-matrix-service';

let sessionExpirationSec: number;

module('Acceptance | operator mode tests', function (hooks) {
  setupApplicationTest(hooks);
  setupLocalIndexing(hooks);
  setupServerSentEvents(hooks);
  setupOnSave(hooks);
  setupWindowMock(hooks);
  setupMatrixServiceMock(hooks, { expiresInSec: () => sessionExpirationSec });

  hooks.beforeEach(async function () {
    sessionExpirationSec = 60 * 60;

    let loader = lookupLoaderService().loader;
    let cardApi: typeof import('https://cardstack.com/base/card-api');
    let string: typeof import('https://cardstack.com/base/string');
    cardApi = await loader.import(`${baseRealm.url}card-api`);
    string = await loader.import(`${baseRealm.url}string`);

    let {
      field,
      contains,
      deserialize,
      linksTo,
      linksToMany,
      BaseDef,
      CardDef,
      Component,
      FieldDef,
    } = cardApi;
    let { default: StringField } = string;
    type BaseDefConstructor = typeof BaseDef;
    type BaseInstanceType<T extends BaseDefConstructor> = T extends {
      [primitive]: infer P;
    }
      ? P
      : InstanceType<T>;

    class Pet extends CardDef {
      static displayName = 'Pet';
      @field name = contains(StringField);
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

    class CountryWithNoEmbedded extends CardDef {
      static displayName = 'Country';
      @field name = contains(StringField);
      @field title = contains(StringField, {
        computeVia(this: CountryWithNoEmbedded) {
          return this.name;
        },
      });
    }

    class AddressWithNoEmbedded extends FieldDef {
      static displayName = 'Address';
      @field city = contains(StringField);
      @field country = contains(StringField);
      @field shippingInfo = contains(ShippingInfo);

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
      @field address = contains(Address);
      @field addressWithNoEmbedded = contains(AddressWithNoEmbedded);
      @field countryWithNoEmbedded = linksTo(CountryWithNoEmbedded);
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
          Address:
          <@fields.address />
          <div data-test-address-with-no-embedded>
            Address With No Embedded:
            <@fields.addressWithNoEmbedded />
          </div>
          <div data-test-country-with-no-embedded>Country With No Embedded:
            <@fields.countryWithNoEmbedded />
          </div>
        </template>
      };
    }

    class BoomField extends FieldDef {
      static [primitive]: string;
      static async [deserialize]<T extends BaseDefConstructor>(
        this: T,
      ): Promise<BaseInstanceType<T>> {
        throw new Error('Boom!');
      }
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          {{@model}}
        </template>
      };
    }

    class BoomPerson extends CardDef {
      static displayName = 'Boom Person';
      @field firstName = contains(StringField);
      @field boom = contains(BoomField);
      @field title = contains(StringField, {
        computeVia: function (this: BoomPerson) {
          return this.firstName;
        },
      });
    }

    await setupAcceptanceTestRealm({
      contents: {
        'address.gts': { Address },
        'boom-field.gts': { BoomField },
        'boom-person.gts': { BoomPerson },
        'country-with-no-embedded-template.gts': { CountryWithNoEmbedded },
        'address-with-no-embedded-template.gts': { AddressWithNoEmbedded },
        'person.gts': { Person },
        'pet.gts': { Pet },
        'shipping-info.gts': { ShippingInfo },
        'README.txt': `Hello World`,
        'person-entry.json': {
          data: {
            type: 'card',
            attributes: {
              title: 'Person Card',
              description: 'Catalog entry for Person Card',
              isField: false,
              ref: {
                module: `${testRealmURL}person`,
                name: 'Person',
              },
            },
            meta: {
              adoptsFrom: {
                module: 'https://cardstack.com/base/catalog-entry',
                name: 'CatalogEntry',
              },
            },
          },
        },
        'Pet/mango.json': {
          data: {
            attributes: {
              name: 'Mango',
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}pet`,
                name: 'Pet',
              },
            },
          },
        },
        'Pet/vangogh.json': {
          data: {
            attributes: {
              name: 'Van Gogh',
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}pet`,
                name: 'Pet',
              },
            },
          },
        },

        'Person/fadhlan.json': {
          data: {
            attributes: {
              firstName: 'Fadhlan',
              address: {
                city: 'Bandung',
                country: 'Indonesia',
                shippingInfo: {
                  preferredCarrier: 'DHL',
                  remarks: `Don't let bob deliver the package--he's always bringing it to the wrong address`,
                },
              },
            },
            relationships: {
              pet: {
                links: {
                  self: `${testRealmURL}Pet/mango`,
                },
              },
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}person`,
                name: 'Person',
              },
            },
          },
        },
        'boom.json': {
          data: {
            attributes: {
              firstName: 'Boom!',
            },
            meta: {
              adoptsFrom: {
                module: './boom-person',
                name: 'BoomPerson',
              },
            },
          },
        },
        'grid.json': {
          data: {
            type: 'card',
            attributes: {},
            meta: {
              adoptsFrom: {
                module: 'https://cardstack.com/base/cards-grid',
                name: 'CardsGrid',
              },
            },
          },
        },
        'index.json': {
          data: {
            type: 'card',
            attributes: {},
            meta: {
              adoptsFrom: {
                module: 'https://cardstack.com/base/cards-grid',
                name: 'CardsGrid',
              },
            },
          },
        },
        '.realm.json': {
          name: 'Test Workspace B',
          backgroundURL:
            'https://i.postimg.cc/VNvHH93M/pawel-czerwinski-Ly-ZLa-A5jti-Y-unsplash.jpg',
          iconURL: 'https://i.postimg.cc/L8yXRvws/icon.png',
        },
      },
    });
  });

  test('visiting index card and entering operator mode', async function (assert) {
    await visit('/');

    assert.strictEqual(currentURL(), '/');

    // Enter operator mode
    await triggerEvent(document.body, 'keydown', {
      code: 'Key.',
      key: '.',
      ctrlKey: true,
    });

    await waitFor('[data-test-operator-mode-stack]');
    assert.dom('[data-test-operator-mode-stack]').exists();
    assert.dom('[data-test-stack-card-index="0"]').exists(); // Index card opens in the stack

    await waitFor(`[data-test-cards-grid-item="${testRealmURL}Pet/mango"]`);

    assert
      .dom(`[data-test-cards-grid-item="${testRealmURL}Pet/mango"]`)
      .exists();
    assert
      .dom(`[data-test-cards-grid-item="${testRealmURL}Pet/vangogh"]`)
      .exists();
    assert
      .dom(`[data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`)
      .exists();
    assert
      .dom(`[data-test-cards-grid-item="${testRealmURL}index"]`)
      .doesNotExist('grid cards do not show other grid cards');
    // this was an unspelled, but very valid assertion that percy is making
    // that I'm now making concrete
    assert
      .dom(`[data-test-cards-grid-item="${testRealmURL}grid"]`)
      .doesNotExist('grid cards do not show other grid cards');
    // this asserts that cards that throw errors during search
    // query deserialization (boom.json) are handled gracefully
    assert
      .dom(`[data-test-cards-grid-item="${testRealmURL}boom"]`)
      .doesNotExist('card with deserialization errors is skipped');
    await percySnapshot(assert);

    assert.operatorModeParametersMatch(currentURL(), {
      stacks: [
        [
          {
            id: `${testRealmURL}index`,
            format: 'isolated',
          },
        ],
      ],
      submode: Submodes.Interact,
    });
  });

  test('can logout via profile info popover', async function (assert) {
    await visitOperatorMode({
      submode: 'code',
      codePath: `${testRealmURL}employee.gts`,
    });

    await waitFor('[data-test-profile-icon-button]');
    assert.dom('[data-test-profile-icon]').hasText('T');
    assert
      .dom('[data-test-profile-icon]')
      .hasStyle({ backgroundColor: 'rgb(94, 173, 107)' });

    assert.dom('[data-test-profile-popover]').doesNotExist();

    await click('[data-test-profile-icon-button]');

    assert.dom('[data-test-profile-popover]').exists();

    await click('[data-test-profile-icon-button]');

    assert.dom('[data-test-profile-popover]').doesNotExist(); // Clicking again closes the popover

    await click('[data-test-profile-icon-button]');

    assert.dom('[data-test-profile-icon-handle]').hasText('@testuser:staging');

    await click('[data-test-signout-button]');

    assert.dom('[data-test-login-btn]').exists();
  });

  test('can access and save settings via profile info popover', async function (assert) {
    await visitOperatorMode({
      stacks: [
        [
          {
            id: `${testRealmURL}Person/fadhlan`,
            format: 'isolated',
          },
        ],
      ],
    })!;

    let matrixService = this.owner.lookup(
      'service:matrixService',
    ) as MockMatrixService;

    await click('[data-test-profile-icon-button]');
    await click('[data-test-settings-button]');

    assert.dom('[data-test-profile-popover]').doesNotExist();
    assert.dom('[data-test-settings-modal]').exists();

    assert.dom('[data-test-profile-icon]').hasText('T'); // "T", from first letter of: @testuser:staging
    assert.dom('[data-test-profile-display-name]').hasText(''); // No display name set yet

    assert
      .dom('[data-test-profile-icon]')
      .hasStyle({ backgroundColor: 'rgb(94, 173, 107)' });
    assert.dom('[data-test-profile-icon-handle]').hasText('@testuser:staging');

    await fillIn('[data-test-display-name-field]', '');
    assert
      .dom('[data-test-boxel-input-error-message]')
      .hasText('Name is required');

    await fillIn('[data-test-display-name-field]', 'John');

    assert.dom('[data-test-boxel-input-error-message]').doesNotExist();

    let setDisplayNameOriginal = matrixService.setDisplayName;

    matrixService.setDisplayName = async function () {
      throw new Error('Boom!');
    };

    await click('[data-test-profile-settings-save-button]');

    assert
      .dom('[data-test-profile-save-error]')
      .hasText('Failed to save profile. Please try again.');

    matrixService.setDisplayName = setDisplayNameOriginal;

    await click('[data-test-profile-settings-save-button]');

    assert.dom('[data-test-profile-save-error]').doesNotExist();

    await waitUntil(
      () =>
        // @ts-ignore
        document
          .querySelector('[data-test-profile-display-name]')
          .textContent.trim() === 'John',
    );

    assert.dom('[data-test-profile-icon]').hasText('J'); // From display name "John"
  });

  test('can open code submode when card or field has no embedded template', async function (assert) {
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

    await waitFor(
      '[data-test-stack-card="http://test-realm/test/Person/fadhlan"]',
    );
    await waitFor('[data-test-address-with-no-embedded]');
    await waitFor(
      '[data-test-address-with-no-embedded] [data-test-open-code-submode]',
    );
    await percySnapshot(assert);
    assert
      .dom(
        '[data-test-address-with-no-embedded] [data-test-missing-embedded-template-text]',
      )
      .hasText('Missing embedded component for FieldDef: Address');
    assert
      .dom(
        '[data-test-country-with-no-embedded] [data-test-missing-embedded-template-text]',
      )
      .hasText('Missing embedded component for CardDef: Country');

    await click(
      '[data-test-address-with-no-embedded] [data-test-open-code-submode]',
    );
    await waitUntil(() =>
      currentURL().includes('address-with-no-embedded-template.gts'),
    );
    assert.operatorModeParametersMatch(currentURL(), {
      codePath: `${testRealmURL}address-with-no-embedded-template.gts`,
    });

    // Toggle back to interactive mode
    await waitFor('[data-test-submode-switcher]');
    await click('[data-test-submode-switcher] button');
    await click('[data-test-boxel-menu-item-text="Interact"]');

    await waitFor(
      '[data-test-address-with-no-embedded] [data-test-open-code-submode]',
    );
    await click(
      '[data-test-country-with-no-embedded] [data-test-open-code-submode]',
    );
    await waitUntil(() =>
      currentURL().includes('country-with-no-embedded-template.gts'),
    );
    assert.operatorModeParametersMatch(currentURL(), {
      submode: Submodes.Code,
      codePath: `${testRealmURL}country-with-no-embedded-template.gts`,
    });
  });

  module('2 stacks', function () {
    test('Toggling submode will open code submode and toggling back will restore the stack', async function (assert) {
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

      // Toggle from interact (default) to code submode
      await waitFor('[data-test-submode-switcher]');
      await click('[data-test-submode-switcher] button');
      await click('[data-test-boxel-menu-item-text="Code"]');

      await waitFor('[data-test-submode-switcher]');
      assert.dom('[data-test-code-mode]').exists();
      assert.dom('[data-test-submode-switcher] button').hasText('Code');

      // Submode is reflected in the URL
      assert.operatorModeParametersMatch(currentURL(), {
        submode: Submodes.Code,
        codePath: `${testRealmURL}Pet/mango.json`,
        fileView: 'inspector',
        openDirs: { [testRealmURL]: ['Pet/'] },
      });

      // Toggle back to interactive mode
      await waitFor('[data-test-submode-switcher]');
      await click('[data-test-submode-switcher] button');
      await click('[data-test-boxel-menu-item-text="Interact"]');

      // Stacks are restored
      await waitFor('[data-test-operator-mode-stack]');
      assert.dom('[data-test-operator-mode-stack]').exists({ count: 2 });

      // Submode is reflected in the URL
      assert.operatorModeParametersMatch(currentURL(), {
        submode: Submodes.Interact,
      });
    });
  });

  module('realm session expiration', function (hooks) {
    let refreshInSec = 2;

    hooks.beforeEach(async function () {
      sessionExpirationSec = tokenRefreshPeriodSec + refreshInSec;
    });

    test('realm session refreshes within 5 minute window of expiration', async function (assert) {
      await visit('/');

      // Enter operator mode
      await triggerEvent(document.body, 'keydown', {
        code: 'Key.',
        key: '.',
        ctrlKey: true,
      });

      await waitFor('[data-test-operator-mode-stack]');
      let originalToken = window.localStorage.getItem(sessionLocalStorageKey);
      await waitUntil(
        () =>
          window.localStorage.getItem(sessionLocalStorageKey) !== originalToken,
        { timeout: refreshInSec * 3 * 1000 },
      );

      let newToken = window.localStorage.getItem(sessionLocalStorageKey);
      assert.ok(newToken, 'new session token obtained');
      assert.notEqual(
        originalToken,
        newToken,
        'new session token is different than original session token',
      );
    });
  });
});
