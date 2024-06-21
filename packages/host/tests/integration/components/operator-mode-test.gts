import {
  waitFor,
  waitUntil,
  click,
  fillIn,
  focus,
  blur,
  setupOnerror,
  triggerEvent,
  triggerKeyEvent,
  typeIn,
} from '@ember/test-helpers';
import GlimmerComponent from '@glimmer/component';

import { setupRenderingTest } from 'ember-qunit';
import window from 'ember-window-mock';
import { setupWindowMock } from 'ember-window-mock/test-support';
import { EventStatus } from 'matrix-js-sdk';
import { module, test } from 'qunit';

import { FieldContainer } from '@cardstack/boxel-ui/components';

import { baseRealm, Deferred } from '@cardstack/runtime-common';
import { Loader } from '@cardstack/runtime-common/loader';

import CardPrerender from '@cardstack/host/components/card-prerender';
import OperatorMode from '@cardstack/host/components/operator-mode/container';

import {
  addRoomEvent,
  updateRoomEvent,
} from '@cardstack/host/lib/matrix-handlers';

import OperatorModeStateService from '@cardstack/host/services/operator-mode-state-service';

import { CardDef } from '../../../../drafts-realm/re-export';
import {
  percySnapshot,
  testRealmURL,
  setupCardLogs,
  setupIntegrationTestRealm,
  setupLocalIndexing,
  setupServerSentEvents,
  setupOnSave,
  showSearchResult,
  type TestContextWithSave,
  getMonacoContent,
  waitForCodeEditor,
  lookupLoaderService,
} from '../../helpers';
import { TestRealmAdapter } from '../../helpers/adapter';
import {
  setupMatrixServiceMock,
  MockMatrixService,
} from '../../helpers/mock-matrix-service';
import { renderComponent } from '../../helpers/render-component';

let cardApi: typeof import('https://cardstack.com/base/card-api');
const realmName = 'Operator Mode Workspace';
let setCardInOperatorModeState: (
  cardURL?: string,
  format?: 'isolated' | 'edit',
) => Promise<void>;
let loader: Loader;

module('Integration | operator-mode', function (hooks) {
  let matrixService: MockMatrixService;
  let testRealmAdapter: TestRealmAdapter;

  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    loader = lookupLoaderService().loader;
  });

  setupLocalIndexing(hooks);
  setupOnSave(hooks);
  setupCardLogs(
    hooks,
    async () => await loader.import(`${baseRealm.url}card-api`),
  );
  setupServerSentEvents(hooks);
  setupMatrixServiceMock(hooks);
  setupWindowMock(hooks);
  let noop = () => {};

  hooks.beforeEach(async function () {
    cardApi = await loader.import(`${baseRealm.url}card-api`);
    matrixService = this.owner.lookup(
      'service:matrixService',
    ) as MockMatrixService;
    matrixService.cardAPI = cardApi;
    matrixService.getRoomModule = async function () {
      return await loader.import(`${baseRealm.url}room`);
    };

    //Generate 11 person card to test recent card menu in card sheet
    let personCards: Map<String, any> = new Map<String, any>();
    for (let i = 1; i <= 11; i++) {
      personCards.set(`Person/${i}.json`, {
        data: {
          type: 'card',
          id: `${testRealmURL}Person/${i}`,
          attributes: {
            firstName: `${i}`,
            address: {
              city: 'Bandung',
              country: 'Indonesia',
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
      });
    }

    let string: typeof import('https://cardstack.com/base/string');
    let textArea: typeof import('https://cardstack.com/base/text-area');

    string = await loader.import(`${baseRealm.url}string`);
    textArea = await loader.import(`${baseRealm.url}text-area`);

    let {
      field,
      contains,
      linksTo,
      linksToMany,
      serialize,
      CardDef,
      Component,
      FieldDef,
    } = cardApi;
    let { default: StringField } = string;
    let { default: TextAreaField } = textArea;

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
          <span data-test-preferredCarrier={{@model.preferredCarrier}}>
            <@fields.preferredCarrier />
          </span>
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
          <div data-test-address>
            <h3 data-test-city={{@model.city}}>
              <@fields.city />
            </h3>
            <h3 data-test-country={{@model.country}}>
              <@fields.country />
            </h3>
            <div data-test-shippingInfo-field><@fields.shippingInfo /></div>
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

    class Country extends CardDef {
      static displayName = 'Country';
      @field name = contains(StringField);
      @field title = contains(StringField, {
        computeVia(this: Country) {
          return this.name;
        },
      });
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          <@fields.name />
        </template>
      };
    }
    class Trips extends FieldDef {
      static displayName = 'Trips';
      @field tripTitle = contains(StringField);
      @field homeCountry = linksTo(Country);
      @field countriesVisited = linksToMany(Country);
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          {{#if @model.tripTitle}}
            <h3 data-test-tripTitle><@fields.tripTitle /></h3>
          {{/if}}
          <div>
            Home Country:
            <@fields.homeCountry />
          </div>
          <div>
            Countries Visited:
            <@fields.countriesVisited />
          </div>
        </template>
      };
    }

    // Friend card that can link to another friend
    class Friend extends CardDef {
      static displayName = 'Friend';
      @field name = contains(StringField);
      @field friend = linksTo(() => Friend);
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          <@fields.name />
        </template>
      };
    }

    class Person extends CardDef {
      static displayName = 'Person';
      @field firstName = contains(StringField);
      @field pet = linksTo(Pet);
      @field friends = linksToMany(Pet);
      @field trips = contains(Trips);
      @field firstLetterOfTheName = contains(StringField, {
        computeVia: function (this: Person) {
          return this.firstName[0];
        },
      });
      @field title = contains(StringField, {
        computeVia: function (this: Person) {
          return this.firstName;
        },
      });
      @field address = contains(Address);
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
          <div data-test-addresses>Address: <@fields.address /></div>
          <div>Trips: <span data-test-trips><@fields.trips /></span></div>
        </template>
      };
    }

    // this field explodes when serialized (saved)
    class BoomField extends StringField {
      static [serialize](_boom: any) {
        throw new Error('Boom!');
      }
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          {{@model}}
        </template>
      };
    }
    class BoomPet extends Pet {
      static displayName = 'Boom Pet';
      @field boom = contains(BoomField);

      static isolated = class Isolated extends Component<typeof this> {
        <template>
          <h2 data-test-pet={{@model.name}}>
            <@fields.name />
            <@fields.boom />
          </h2>
        </template>
      };
    }

    class Author extends CardDef {
      static displayName = 'Author';
      @field firstName = contains(StringField);
      @field lastName = contains(StringField);
      @field title = contains(StringField, {
        computeVia: function (this: Author) {
          return [this.firstName, this.lastName].filter(Boolean).join(' ');
        },
      });
      static isolated = class Isolated extends Component<typeof this> {
        <template>
          <div data-test-isolated-author>
            <@fields.title />
            <@fields.firstName />
            <@fields.lastName />
          </div>
        </template>
      };
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          <span data-test-author='{{@model.firstName}}'>
            <@fields.firstName />
            <@fields.lastName />
          </span>
        </template>
      };
    }

    class BlogPost extends CardDef {
      static displayName = 'Blog Post';
      @field title = contains(StringField);
      @field slug = contains(StringField);
      @field body = contains(TextAreaField);
      @field authorBio = linksTo(Author);
      static embedded = class Embedded extends Component<typeof this> {
        <template>
          <@fields.title /> by <@fields.authorBio />
        </template>
      };
      static isolated = class Isolated extends Component<typeof this> {
        <template>
          <div data-test-blog-post-isolated>
            <@fields.title />
            by
            <@fields.authorBio />
          </div>
        </template>
      };
    }

    class PublishingPacket extends CardDef {
      static displayName = 'Publishing Packet';
      @field blogPost = linksTo(BlogPost);
      @field socialBlurb = contains(TextAreaField);
    }

    class PetRoom extends CardDef {
      static displayName = 'Pet Room';
      @field name = contains(StringField);
      @field title = contains(StringField, {
        computeVia: function (this: PetRoom) {
          return this.name;
        },
      });
    }

    ({ adapter: testRealmAdapter } = await setupIntegrationTestRealm({
      loader,
      contents: {
        'pet.gts': { Pet },
        'shipping-info.gts': { ShippingInfo },
        'address.gts': { Address },
        'person.gts': { Person },
        'boom-field.gts': { BoomField },
        'boom-pet.gts': { BoomPet },
        'blog-post.gts': { BlogPost },
        'author.gts': { Author },
        'friend.gts': { Friend },
        'publishing-packet.gts': { PublishingPacket },
        'pet-room.gts': { PetRoom },
        'country.gts': { Country },
        'Pet/mango.json': {
          data: {
            type: 'card',
            id: `${testRealmURL}Pet/mango`,
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
        'BoomPet/paper.json': {
          data: {
            type: 'card',
            id: `${testRealmURL}BoomPet/paper`,
            attributes: {
              name: 'Paper',
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}boom-pet`,
                name: 'BoomPet',
              },
            },
          },
        },
        'Pet/jackie.json': {
          data: {
            type: 'card',
            id: `${testRealmURL}Pet/jackie`,
            attributes: {
              name: 'Jackie',
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}pet`,
                name: 'Pet',
              },
            },
          },
        },
        'Pet/woody.json': {
          data: {
            type: 'card',
            id: `${testRealmURL}Pet/woody`,
            attributes: {
              name: 'Woody',
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}pet`,
                name: 'Pet',
              },
            },
          },
        },
        'Pet/buzz.json': {
          data: {
            type: 'card',
            id: `${testRealmURL}Pet/buzz`,
            attributes: {
              name: 'Buzz',
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
            type: 'card',
            id: `${testRealmURL}Person/fadhlan`,
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
        'Person/burcu.json': {
          data: {
            type: 'card',
            id: `${testRealmURL}Person/burcu`,
            attributes: {
              firstName: 'Burcu',
            },
            relationships: {
              'friends.0': {
                links: {
                  self: `${testRealmURL}Pet/jackie`,
                },
              },
              'friends.1': {
                links: {
                  self: `${testRealmURL}Pet/woody`,
                },
              },
              'friends.2': {
                links: {
                  self: `${testRealmURL}Pet/buzz`,
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
        'Country/usa.json': {
          data: {
            type: 'card',
            id: `${testRealmURL}Country/usa`,
            attributes: {
              name: 'USA',
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}country`,
                name: 'Country',
              },
            },
          },
        },
        'Country/japan.json': {
          data: {
            type: 'card',
            id: `${testRealmURL}Country/japan`,
            attributes: {
              name: 'Japan',
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}country`,
                name: 'Country',
              },
            },
          },
        },
        'Person/mickey.json': {
          data: {
            type: 'card',
            id: `${testRealmURL}Person/mickey`,
            attributes: {
              firstName: 'Mickey',
              trips: {
                tripTitle: 'Summer Vacation',
              },
            },
            relationships: {
              'trips.homeCountry': {
                links: {
                  self: `${testRealmURL}Country/usa`,
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
        'Friend/friend-a.json': {
          data: {
            type: 'card',
            attributes: {
              name: 'Friend A',
            },
            relationships: {
              friend: {
                links: {
                  self: `${testRealmURL}Friend/friend-b`,
                },
              },
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}friend`,
                name: 'Friend',
              },
            },
          },
        },
        'Friend/friend-b.json': {
          data: {
            type: 'card',
            attributes: {
              name: 'Friend B',
            },
            relationships: {
              friend: {
                links: {
                  self: null,
                },
              },
            },
            meta: {
              adoptsFrom: {
                module: `${testRealmURL}friend`,
                name: 'Friend',
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
        'CatalogEntry/publishing-packet.json': {
          data: {
            type: 'card',
            attributes: {
              title: 'Publishing Packet',
              description: 'Catalog entry for PublishingPacket',
              isField: false,
              ref: {
                module: `${testRealmURL}publishing-packet`,
                name: 'PublishingPacket',
              },
              demo: {
                socialBlurb: null,
              },
            },
            relationships: {
              'demo.blogPost': {
                links: {
                  self: '../BlogPost/1',
                },
              },
            },
            meta: {
              fields: {
                demo: {
                  adoptsFrom: {
                    module: `../publishing-packet`,
                    name: 'PublishingPacket',
                  },
                },
              },
              adoptsFrom: {
                module: 'https://cardstack.com/base/catalog-entry',
                name: 'CatalogEntry',
              },
            },
          },
        },
        'CatalogEntry/pet-room.json': {
          data: {
            type: 'card',
            attributes: {
              title: 'General Pet Room',
              description: 'Catalog entry for Pet Room Card',
              isField: false,
              ref: {
                module: `${testRealmURL}pet-room`,
                name: 'PetRoom',
              },
            },
            meta: {
              fields: {
                demo: {
                  adoptsFrom: {
                    module: `../pet-room`,
                    name: 'PetRoom',
                  },
                },
              },
              adoptsFrom: {
                module: 'https://cardstack.com/base/catalog-entry',
                name: 'CatalogEntry',
              },
            },
          },
        },
        'CatalogEntry/pet-card.json': {
          data: {
            type: 'card',
            attributes: {
              title: 'Pet',
              description: 'Catalog entry for Pet',
              ref: {
                module: `${testRealmURL}pet`,
                name: 'Pet',
              },
              isField: false,
              demo: {
                name: 'Snoopy',
              },
            },
            meta: {
              fields: {
                demo: {
                  adoptsFrom: {
                    module: `../pet`,
                    name: 'Pet',
                  },
                },
              },
              adoptsFrom: {
                module: 'https://cardstack.com/base/catalog-entry',
                name: 'CatalogEntry',
              },
            },
          },
        },
        'BlogPost/1.json': {
          data: {
            type: 'card',
            attributes: {
              title: 'Outer Space Journey',
              body: 'Hello world',
            },
            relationships: {
              authorBio: {
                links: {
                  self: '../Author/1',
                },
              },
            },
            meta: {
              adoptsFrom: {
                module: '../blog-post',
                name: 'BlogPost',
              },
            },
          },
        },
        'BlogPost/2.json': {
          data: {
            type: 'card',
            attributes: {
              title: 'Beginnings',
            },
            relationships: {
              authorBio: {
                links: {
                  self: null,
                },
              },
            },
            meta: {
              adoptsFrom: {
                module: '../blog-post',
                name: 'BlogPost',
              },
            },
          },
        },
        'Author/1.json': {
          data: {
            type: 'card',
            attributes: {
              firstName: 'Alien',
              lastName: 'Bob',
            },
            meta: {
              adoptsFrom: {
                module: '../author',
                name: 'Author',
              },
            },
          },
        },
        'Author/2.json': {
          data: {
            type: 'card',
            attributes: {
              firstName: 'R2-D2',
            },
            meta: {
              adoptsFrom: {
                module: '../author',
                name: 'Author',
              },
            },
          },
        },
        'Author/mark.json': {
          data: {
            type: 'card',
            attributes: {
              firstName: 'Mark',
              lastName: 'Jackson',
            },
            meta: {
              adoptsFrom: {
                module: '../author',
                name: 'Author',
              },
            },
          },
        },
        '.realm.json': `{ "name": "${realmName}", "iconURL": "https://example-icon.test" }`,
        ...Object.fromEntries(personCards),
      },
    }));

    setCardInOperatorModeState = async (
      cardURL?: string,
      format: 'isolated' | 'edit' = 'isolated',
    ) => {
      let operatorModeStateService = this.owner.lookup(
        'service:operator-mode-state-service',
      ) as OperatorModeStateService;
      await operatorModeStateService.restore({
        stacks: cardURL ? [[{ id: cardURL, format }]] : [[]],
      });
    };
  });

  module('matrix', function () {
    async function openAiAssistant(): Promise<string> {
      await waitFor('[data-test-open-ai-assistant]');
      await click('[data-test-open-ai-assistant]');
      await waitFor('[data-test-room-settled]');
      let roomId = document
        .querySelector('[data-test-room]')
        ?.getAttribute('data-test-room');
      if (!roomId) {
        throw new Error('Expected a room ID');
      }
      return roomId;
    }

    test<TestContextWithSave>('it allows chat commands to change cards in the stack', async function (assert) {
      assert.expect(4);
      await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );

      await waitFor('[data-test-person]');
      assert.dom('[data-test-boxel-header-title]').hasText('Person');
      assert.dom('[data-test-person]').hasText('Fadhlan');

      let roomId = await openAiAssistant();
      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          body: 'i am the body',
          msgtype: 'org.boxel.command',
          formatted_body: 'A patch',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id: `${testRealmURL}Person/fadhlan`,
              patch: {
                attributes: { firstName: 'Dave' },
              },
              eventId: 'patch1',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'patch1',
          },
        },
        status: null,
      });

      await waitFor('[data-test-command-apply]');
      this.onSave((_, json) => {
        if (typeof json === 'string') {
          throw new Error('expected JSON save data');
        }
        assert.strictEqual(json.data.attributes?.firstName, 'Dave');
      });
      await click('[data-test-command-apply]');
      await waitFor('[data-test-patch-card-idle]');

      assert.dom('[data-test-person]').hasText('Dave');
    });

    test('it maintains status of apply buttons during a session when switching between rooms', async function (assert) {
      await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      await waitFor('[data-test-person="Fadhlan"]');
      await matrixService.createAndJoinRoom('room1', 'test room 1');
      await matrixService.createAndJoinRoom('room2', 'test room 2');
      await addRoomEvent(matrixService, {
        event_id: 'room1-event1',
        room_id: 'room1',
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Changing first name to Evie',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id: `${testRealmURL}Person/fadhlan`,
              patch: { attributes: { firstName: 'Evie' } },
              eventId: 'room1-event1',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'room1-event1',
          },
        },
        status: null,
      });
      await addRoomEvent(matrixService, {
        event_id: 'room1-event2',
        room_id: 'room1',
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Changing first name to Jackie',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id: `${testRealmURL}Person/fadhlan`,
              patch: { attributes: { firstName: 'Jackie' } },
              eventId: 'room1-event2',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'room1-event2',
          },
        },
        status: null,
      });
      await addRoomEvent(matrixService, {
        event_id: 'room2-event1',
        room_id: 'room2',
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Incorrect command',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id: `${testRealmURL}Person/fadhlan`,
              patch: { relationships: { pet: null } }, // this will error
              eventId: 'room2-event1',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'room2-event1',
          },
        },
        status: null,
      });

      await click('[data-test-open-ai-assistant]');
      await waitFor('[data-test-room-name="test room 1"]');
      await waitFor('[data-test-message-idx="1"] [data-test-command-apply]');
      await click('[data-test-message-idx="1"] [data-test-command-apply]');
      await waitFor('[data-test-patch-card-idle]');

      assert
        .dom('[data-test-message-idx="1"] [data-test-apply-state="applied"]')
        .exists();
      assert
        .dom('[data-test-message-idx="0"] [data-test-apply-state="ready"]')
        .exists();

      await click('[data-test-past-sessions-button]');
      await click(`[data-test-enter-room="room2"]`);
      await waitFor('[data-test-room-name="test room 2"]');
      await waitFor('[data-test-command-apply]');
      await click('[data-test-command-apply]');
      await waitFor('[data-test-patch-card-idle]');
      assert
        .dom('[data-test-message-idx="0"] [data-test-apply-state="failed"]')
        .exists();

      // reopen ai assistant panel
      await click('[data-test-close-ai-assistant]');
      await waitFor('[data-test-ai-assistant-panel]', { count: 0 });
      await click('[data-test-open-ai-assistant]');
      await waitFor('[data-test-ai-assistant-panel]');

      await click('[data-test-past-sessions-button]');
      await click(`[data-test-enter-room="room1"]`);
      await waitFor('[data-test-room-name="test room 1"]');
      assert
        .dom('[data-test-message-idx="1"] [data-test-apply-state="applied"]')
        .exists();
      assert
        .dom('[data-test-message-idx="0"] [data-test-apply-state="ready"]')
        .exists();

      await click('[data-test-past-sessions-button]');
      await click(`[data-test-enter-room="room2"]`);
      await waitFor('[data-test-room-name="test room 2"]');
      assert
        .dom('[data-test-message-idx="0"] [data-test-apply-state="failed"]')
        .exists();
    });

    test('it only applies changes from the chat if the stack contains a card with that ID', async function (assert) {
      await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );

      await waitFor('[data-test-person]');
      assert.dom('[data-test-boxel-header-title]').hasText('Person');
      assert.dom('[data-test-person]').hasText('Fadhlan');

      let roomId = await openAiAssistant();
      let otherCardID = `${testRealmURL}Person/burcu`;
      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          body: 'i am the body',
          msgtype: 'org.boxel.command',
          formatted_body: 'A patch',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id: otherCardID,
              patch: {
                attributes: { firstName: 'Dave' },
              },
              eventId: 'event1',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'event1',
          },
        },
        status: null,
      });

      await waitFor('[data-test-command-apply="ready"]');
      await click('[data-test-command-apply]');

      await waitFor('[data-test-patch-card-idle]');
      assert
        .dom('[data-test-card-error]')
        .containsText(
          `Please open card '${otherCardID}' to make changes to it.`,
        );
      assert.dom('[data-test-apply-state="failed"]').exists();
      assert.dom('[data-test-ai-bot-retry-button]').exists();
      assert.dom('[data-test-command-apply]').doesNotExist();
      assert.dom('[data-test-person]').hasText('Fadhlan');

      await waitFor('[data-test-embedded-card-options-button]');
      await percySnapshot(
        'Integration | operator-mode > matrix | it only applies changes from the chat if the stack contains a card with that ID | error',
      );

      await setCardInOperatorModeState(otherCardID);
      await waitFor('[data-test-person="Burcu"]');
      await click('[data-test-ai-bot-retry-button]'); // retry the command with correct card
      assert.dom('[data-test-apply-state="applying"]').exists();

      await waitFor('[data-test-patch-card-idle]');
      assert.dom('[data-test-apply-state="applied"]').exists();
      assert.dom('[data-test-person]').hasText('Dave');
      assert.dom('[data-test-command-apply]').doesNotExist();
      assert.dom('[data-test-ai-bot-retry-button]').doesNotExist();

      await waitUntil(
        () =>
          document.querySelectorAll('[data-test-embedded-card-options-button]')
            .length === 3,
      );
      await percySnapshot(
        'Integration | operator-mode > matrix | it only applies changes from the chat if the stack contains a card with that ID | error fixed',
      );
    });

    test('it can apply change to nested contains field', async function (assert) {
      await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      await waitFor('[data-test-person="Fadhlan"]');
      assert.dom(`[data-test-preferredcarrier="DHL"]`).exists();

      let roomId = await openAiAssistant();
      let payload = {
        type: 'patchCard',
        id: `${testRealmURL}Person/fadhlan`,
        patch: {
          attributes: {
            firstName: 'Joy',
            address: { shippingInfo: { preferredCarrier: 'UPS' } },
          },
        },
        eventId: 'event1',
      };
      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          body: 'A patch',
          msgtype: 'org.boxel.command',
          formatted_body: 'A patch',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({ command: payload }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'event1',
          },
        },
        status: null,
      });

      await waitFor('[data-test-view-code-button]');
      await click('[data-test-view-code-button]');

      await waitForCodeEditor();
      assert.deepEqual(
        JSON.parse(getMonacoContent()),
        {
          commandType: 'patchCard',
          payload,
        },
        'it can preview code when a change is proposed',
      );
      assert.dom('[data-test-copy-code]').isEnabled('copy button is available');

      await click('[data-test-view-code-button]');
      assert.dom('[data-test-code-editor]').doesNotExist();

      await click('[data-test-command-apply="ready"]');
      await waitFor('[data-test-patch-card-idle]');
      assert.dom('[data-test-apply-state="applied"]').exists();
      assert.dom('[data-test-person]').hasText('Joy');
      assert.dom(`[data-test-preferredcarrier]`).hasText('UPS');
      assert.dom(`[data-test-city="Bandung"]`).exists();
      assert.dom(`[data-test-country="Indonesia"]`).exists();
    });

    test('it can apply change to a linksTo field', async function (assert) {
      let id = `${testRealmURL}Person/fadhlan`;
      await setCardInOperatorModeState(id);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      await waitFor('[data-test-person="Fadhlan"]');

      let roomId = await openAiAssistant();
      await addRoomEvent(matrixService, {
        event_id: 'event0',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Removing pet and changing preferred carrier',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id,
              patch: {
                attributes: {
                  address: { shippingInfo: { preferredCarrier: 'Fedex' } },
                },
                relationships: {
                  pet: { links: { self: null } },
                },
              },
              eventId: 'patch0',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'patch0',
          },
        },
        status: null,
      });

      const stackCard = `[data-test-stack-card="${testRealmURL}Person/fadhlan"]`;

      await waitFor('[data-test-command-apply="ready"]');
      assert.dom(`${stackCard} [data-test-preferredcarrier="DHL"]`).exists();
      assert.dom(`${stackCard} [data-test-pet="Mango"]`).exists();

      await click('[data-test-command-apply]');
      await waitFor('[data-test-patch-card-idle]');
      assert.dom('[data-test-apply-state="applied"]').exists();
      assert.dom(`${stackCard} [data-test-preferredcarrier="Fedex"]`).exists();
      assert.dom(`${stackCard} [data-test-pet="Mango"]`).doesNotExist();

      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Link to pet and change preferred carrier',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id,
              patch: {
                attributes: {
                  address: { shippingInfo: { preferredCarrier: 'UPS' } },
                },
                relationships: {
                  pet: {
                    links: { self: `${testRealmURL}Pet/mango` },
                  },
                },
              },
              eventId: 'patch1',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'patch1',
          },
        },
        status: null,
      });
      await waitFor('[data-test-command-apply="ready"]');
      assert.dom(`${stackCard} [data-test-preferredcarrier="Fedex"]`).exists();
      assert.dom(`${stackCard} [data-test-pet]`).doesNotExist();

      await click('[data-test-command-apply]');
      await waitFor('[data-test-message-idx="1"] [data-test-patch-card-idle]');
      assert
        .dom('[data-test-message-idx="1"] [data-test-apply-state="applied"]')
        .exists();
      assert.dom(`${stackCard} [data-test-preferredcarrier="UPS"]`).exists();
      assert.dom(`${stackCard} [data-test-pet="Mango"]`).exists();
      assert.dom(`${stackCard} [data-test-city="Bandung"]`).exists();
      assert.dom(`${stackCard} [data-test-country="Indonesia"]`).exists();
    });

    test('it does not crash when applying change to a card with preexisting nested linked card', async function (assert) {
      let id = `${testRealmURL}Person/mickey`;
      await setCardInOperatorModeState(id);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      await waitFor('[data-test-person="Mickey"]');
      assert.dom('[data-test-tripTitle]').hasText('Summer Vacation');

      let roomId = await openAiAssistant();
      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Change tripTitle to Trip to Japan',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id,
              patch: {
                attributes: { trips: { tripTitle: 'Trip to Japan' } },
              },
              eventId: 'event1',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'event1',
          },
        },
        status: null,
      });

      await waitFor('[data-test-command-apply="ready"]');
      await click('[data-test-command-apply]');
      await waitFor('[data-test-patch-card-idle]');
      assert.dom('[data-test-apply-state="applied"]').exists();
      assert.dom('[data-test-tripTitle]').hasText('Trip to Japan');
    });

    test('button states only apply to a single button in a chat room', async function (assert) {
      let id = `${testRealmURL}Person/fadhlan`;
      await setCardInOperatorModeState(id);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      await waitFor('[data-test-person="Fadhlan"]');

      let roomId = await openAiAssistant();
      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Change first name to Dave',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id,
              patch: { attributes: { firstName: 'Dave' } },
              eventId: 'event1',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'event1',
          },
        },
        status: null,
      });
      await addRoomEvent(matrixService, {
        event_id: 'event2',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Incorrect patch command',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id,
              patch: { relationships: { pet: null } }, // this will error
              eventId: 'event2',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'event2',
          },
        },
        status: null,
      });
      await addRoomEvent(matrixService, {
        event_id: 'event3',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Change first name to Jackie',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id,
              patch: { attributes: { firstName: 'Jackie' } },
              eventId: 'event3',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'event3',
          },
        },
        status: null,
      });

      await waitFor('[data-test-command-apply="ready"]', { count: 3 });

      await click('[data-test-message-idx="2"] [data-test-command-apply]');
      assert.dom('[data-test-apply-state="applying"]').exists({ count: 1 });
      assert
        .dom('[data-test-message-idx="2"] [data-test-apply-state="applying"]')
        .exists();

      await waitFor('[data-test-message-idx="2"] [data-test-patch-card-idle]');
      assert.dom('[data-test-apply-state="applied"]').exists({ count: 1 });
      assert
        .dom('[data-test-message-idx="2"] [data-test-apply-state="applied"]')
        .exists();
      assert.dom('[data-test-command-apply="ready"]').exists({ count: 2 });
      assert.dom('[data-test-person]').hasText('Jackie');

      await click('[data-test-message-idx="1"] [data-test-command-apply]');
      await waitFor('[data-test-message-idx="1"] [data-test-patch-card-idle]');
      assert.dom('[data-test-apply-state="failed"]').exists({ count: 1 });
      assert
        .dom('[data-test-message-idx="1"] [data-test-apply-state="failed"]')
        .exists();
      assert.dom('[data-test-command-apply="ready"]').exists({ count: 1 });
      assert
        .dom('[data-test-message-idx="0"] [data-test-command-apply="ready"]')
        .exists();
    });

    test('assures applied state displayed as a check mark even eventId in command payload is undefined', async function (assert) {
      let id = `${testRealmURL}Person/fadhlan`;
      await setCardInOperatorModeState(id);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      await waitFor('[data-test-person="Fadhlan"]');

      let roomId = await openAiAssistant();
      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          msgtype: 'org.boxel.command',
          formatted_body: 'Change first name to Dave',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id,
              patch: { attributes: { firstName: 'Dave' } },
              eventId: undefined,
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'event1',
          },
        },
        status: null,
      });

      await waitFor('[data-test-command-apply="ready"]', { count: 1 });

      await click('[data-test-message-idx="0"] [data-test-command-apply]');
      assert.dom('[data-test-apply-state="applying"]').exists({ count: 1 });
      assert
        .dom('[data-test-message-idx="0"] [data-test-apply-state="applying"]')
        .exists();

      await waitFor('[data-test-message-idx="0"] [data-test-patch-card-idle]');
      assert.dom('[data-test-apply-state="applied"]').exists({ count: 1 });
      assert
        .dom('[data-test-message-idx="0"] [data-test-apply-state="applied"]')
        .exists();
      assert.dom('[data-test-person]').hasText('Dave');
    });

    test('it can handle an error in a card attached to a matrix message', async function (assert) {
      await setCardInOperatorModeState();
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );

      let roomId = await openAiAssistant();
      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(1994, 0, 1, 12, 30).getTime(),
        content: {
          body: '',
          formatted_body: '',
          msgtype: 'org.boxel.cardFragment',
          data: JSON.stringify({
            index: 0,
            totalParts: 1,
            cardFragment: JSON.stringify({
              data: {
                id: 'http://this-is-not-a-real-card.com',
                type: 'card',
                attributes: {
                  firstName: 'Boom',
                },
                meta: {
                  adoptsFrom: {
                    module: 'http://not-a-real-card.com',
                    name: 'Boom',
                  },
                },
              },
            }),
          }),
        },
        status: null,
      });
      await addRoomEvent(matrixService, {
        event_id: 'event2',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(1994, 0, 1, 12, 30).getTime(),
        content: {
          body: 'card with error',
          formatted_body: 'card with error',
          msgtype: 'org.boxel.message',
          data: JSON.stringify({
            attachedCardsEventIds: ['event1'],
          }),
        },
        status: null,
      });

      await waitFor('[data-test-card-error]');
      assert
        .dom('[data-test-card-error]')
        .containsText('Error rendering attached cards');
      await percySnapshot(assert);
    });

    test('it can handle an error during room creation', async function (assert) {
      await setCardInOperatorModeState();
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
            <div class='invisible' data-test-throw-room-error />
            <style>
              .invisible {
                display: none;
              }
            </style>
          </template>
        },
      );

      await waitFor('[data-test-open-ai-assistant]');
      await click('[data-test-open-ai-assistant]');
      await waitFor('[data-test-new-session]');
      assert.dom('[data-test-room-error]').exists();
      assert.dom('[data-test-room]').doesNotExist();
      assert.dom('[data-test-past-sessions-button]').isDisabled();
      await percySnapshot(
        'Integration | operator-mode > matrix | it can handle an error during room creation | error state',
      );

      document.querySelector('[data-test-throw-room-error]')?.remove();
      await click('[data-test-room-error] > button');
      await waitFor('[data-test-room]');
      assert.dom('[data-test-room-error]').doesNotExist();
      assert.dom('[data-test-past-sessions-button]').isEnabled();
      await percySnapshot(
        'Integration | operator-mode > matrix | it can handle an error during room creation | new room state',
      );
    });

    test('when opening ai panel it opens the most recent room', async function (assert) {
      await setCardInOperatorModeState(`${testRealmURL}Pet/mango`);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );

      let tinyDelay = () => new Promise((resolve) => setTimeout(resolve, 1)); // Add a tiny artificial delay to ensure rooms are created in the correct order with increasing timestamps
      await matrixService.createAndJoinRoom('test1', 'test room 1');
      await tinyDelay();
      const room2Id = await matrixService.createAndJoinRoom(
        'test2',
        'test room 2',
      );
      await tinyDelay();
      const room3Id = await matrixService.createAndJoinRoom(
        'test3',
        'test room 3',
      );

      await waitFor(`[data-test-open-ai-assistant]`);
      await click('[data-test-open-ai-assistant]');
      await waitFor(`[data-room-settled]`);

      assert
        .dom(`[data-test-room="${room3Id}"]`)
        .exists(
          "test room 3 is the most recently created room and it's opened initially",
        );

      await click('[data-test-past-sessions-button]');
      await click(`[data-test-enter-room="${room2Id}"]`);

      await click('[data-test-close-ai-assistant]');
      await click('[data-test-open-ai-assistant]');
      await waitFor(`[data-room-settled]`);
      assert
        .dom(`[data-test-room="${room2Id}"]`)
        .exists(
          "test room 2 is the most recently selected room and it's opened initially",
        );

      await click('[data-test-close-ai-assistant]');
      window.localStorage.setItem(
        'aiPanelCurrentRoomId',
        "room-id-that-doesn't-exist-and-should-not-break-the-implementation",
      );
      await click('[data-test-open-ai-assistant]');
      await waitFor(`[data-room-settled]`);
      assert
        .dom(`[data-test-room="${room3Id}"]`)
        .exists(
          "test room 3 is the most recently created room and it's opened initially",
        );

      window.localStorage.removeItem('aiPanelCurrentRoomId'); // Cleanup
    });

    test('can close past-sessions list on outside click', async function (assert) {
      await setCardInOperatorModeState();
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );

      let room = await openAiAssistant();
      await click('[data-test-past-sessions-button]');
      assert.dom('[data-test-past-sessions]').exists();
      assert.dom('[data-test-joined-room]').exists({ count: 1 });
      await click('.operator-mode__main');
      assert.dom('[data-test-past-sessions]').doesNotExist();

      await click('[data-test-past-sessions-button]');
      await click('[data-test-past-sessions]');
      assert.dom('[data-test-past-sessions]').exists();
      await click(`[data-test-past-session-options-button="${room}"]`);
      assert.dom('[data-test-past-sessions]').exists();
      await click('[data-test-message-field]');
      assert.dom('[data-test-past-sessions]').doesNotExist();
    });

    test('it can render a markdown message from ai bot', async function (assert) {
      await setCardInOperatorModeState();
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      let roomId = await openAiAssistant();
      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@aibot:localhost',
        content: {
          body: "# Beagles: Loyal Companions\n\nEnergetic and friendly, beagles are wonderful family pets. They _love_ company and always crave playtime.\n\nTheir keen noses lead adventures, unraveling scents. Always curious, they're the perfect mix of independence and affection.",
          msgtype: 'm.text',
          formatted_body:
            "# Beagles: Loyal Companions\n\nEnergetic and friendly, beagles are wonderful family pets. They _love_ company and always crave playtime.\n\nTheir keen noses lead adventures, unraveling scents. Always curious, they're the perfect mix of independence and affection.",
          format: 'org.matrix.custom.html',
        },
        origin_server_ts: 1709652566421,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });
      await waitFor(`[data-test-room="${roomId}"] [data-test-message-idx="0"]`);
      assert.dom('[data-test-message-idx="0"] h1').containsText('Beagles');
      assert.dom('[data-test-message-idx="0"]').doesNotContainText('# Beagles');
      assert.dom('[data-test-message-idx="0"] p').exists({ count: 2 });
      assert.dom('[data-test-message-idx="0"] em').hasText('love');
      assert.dom('[data-test-message-idx="0"]').doesNotContainText('_love_');
    });

    test('displays message slightly muted when it is being sent', async function (assert) {
      await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );

      let originalSendMessage = matrixService.sendMessage;
      let clientGeneratedId = '';
      let event: any;
      matrixService.sendMessage = async function (
        roomId: string,
        body: string,
        attachedCards: CardDef[],
        _clientGeneratedId: string,
        _context?: any,
      ) {
        let serializedCard = cardApi.serializeCard(attachedCards[0]);
        let cardFragmentEvent = {
          event_id: 'test-card-fragment-event-id',
          room_id: roomId,
          state_key: 'state',
          type: 'm.room.message',
          sender: matrixService.userId!,
          content: {
            msgtype: 'org.boxel.cardFragment' as const,
            format: 'org.boxel.card' as const,
            body: `card fragment 1 of 1`,
            formatted_body: `card fragment 1 of 1`,
            data: JSON.stringify({
              cardFragment: JSON.stringify(serializedCard),
              index: 0,
              totalParts: 1,
            }),
          },
          origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
          unsigned: {
            age: 105,
            transaction_id: '1',
          },
          status: null,
        };
        await addRoomEvent(this, cardFragmentEvent);

        clientGeneratedId = _clientGeneratedId;
        event = {
          event_id: 'test-event-id',
          room_id: roomId,
          state_key: 'state',
          type: 'm.room.message',
          sender: matrixService.userId!,
          content: {
            body,
            msgtype: 'org.boxel.message',
            formatted_body: body,
            format: 'org.matrix.custom.html',
            clientGeneratedId,
            data: JSON.stringify({
              attachedCardsEventIds: [cardFragmentEvent.event_id],
            }),
          },
          origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
          unsigned: {
            age: 105,
            transaction_id: '1',
          },
          status: EventStatus.SENDING,
        };
        await addRoomEvent(this, event);
      };
      await openAiAssistant();

      await fillIn('[data-test-message-field]', 'Test Message');
      assert.dom('[data-test-message-field]').hasValue('Test Message');
      assert.dom('[data-test-send-message-btn]').isEnabled();
      assert.dom('[data-test-ai-assistant-message]').doesNotExist();
      await click('[data-test-send-message-btn]');

      assert.dom('[data-test-message-field]').hasValue('');
      assert.dom('[data-test-send-message-btn]').isDisabled();
      assert.dom('[data-test-ai-assistant-message]').exists({ count: 1 });
      assert.dom('[data-test-ai-assistant-message]').hasClass('is-pending');
      await percySnapshot(assert);

      let newEvent = {
        ...event,
        event_id: 'updated-event-id',
        status: EventStatus.SENT,
      };
      await updateRoomEvent(matrixService, newEvent, event.event_id);
      await waitUntil(
        () =>
          !(
            document.querySelector(
              '[data-test-send-message-btn]',
            ) as HTMLButtonElement
          ).disabled,
      );
      assert.dom('[data-test-ai-assistant-message]').exists({ count: 1 });
      assert.dom('[data-test-ai-assistant-message]').hasNoClass('is-pending');
      matrixService.sendMessage = originalSendMessage;
    });

    test('displays retry button for message that failed to send', async function (assert) {
      await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );

      let originalSendMessage = matrixService.sendMessage;
      let clientGeneratedId = '';
      let event: any;
      matrixService.sendMessage = async function (
        roomId: string,
        body: string,
        _attachedCards: [],
        _clientGeneratedId: string,
        _context?: any,
      ) {
        clientGeneratedId = _clientGeneratedId;
        event = {
          event_id: 'test-event-id',
          room_id: roomId,
          state_key: 'state',
          type: 'm.room.message',
          sender: matrixService.userId!,
          content: {
            body,
            msgtype: 'org.boxel.message',
            formatted_body: body,
            format: 'org.matrix.custom.html',
            clientGeneratedId,
          },
          origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
          unsigned: {
            age: 105,
            transaction_id: '1',
          },
          status: EventStatus.SENDING,
        };
        await addRoomEvent(this, event);
      };
      await openAiAssistant();

      await fillIn('[data-test-message-field]', 'Test Message');
      assert.dom('[data-test-message-field]').hasValue('Test Message');
      assert.dom('[data-test-send-message-btn]').isEnabled();
      assert.dom('[data-test-ai-assistant-message]').doesNotExist();
      await click('[data-test-send-message-btn]');

      assert.dom('[data-test-message-field]').hasValue('');
      assert.dom('[data-test-send-message-btn]').isDisabled();
      assert.dom('[data-test-ai-assistant-message]').exists({ count: 1 });
      assert.dom('[data-test-ai-assistant-message]').hasClass('is-pending');

      let newEvent = {
        ...event,
        event_id: 'updated-event-id',
        status: EventStatus.NOT_SENT,
      };
      await updateRoomEvent(matrixService, newEvent, event.event_id);
      await waitUntil(
        () =>
          !(
            document.querySelector(
              '[data-test-send-message-btn]',
            ) as HTMLButtonElement
          ).disabled,
      );
      assert.dom('[data-test-ai-assistant-message]').exists({ count: 1 });
      assert.dom('[data-test-ai-assistant-message]').hasClass('is-error');
      assert.dom('[data-test-card-error]').containsText('Failed to send');
      assert.dom('[data-test-ai-bot-retry-button]').exists();
      await percySnapshot(assert);

      matrixService.sendMessage = async function (
        _roomId: string,
        _body: string,
        _attachedCards: [],
        _clientGeneratedId: string,
        _context?: any,
      ) {
        event = {
          ...event,
          status: null,
        };
        await addRoomEvent(this, event);
      };
      await click('[data-test-ai-bot-retry-button]');
      assert.dom('[data-test-ai-assistant-message]').exists({ count: 1 });
      assert.dom('[data-test-ai-assistant-message]').hasNoClass('is-error');
      matrixService.sendMessage = originalSendMessage;
    });

    test('it displays the streaming indicator when ai bot message is in progress (streaming words)', async function (assert) {
      await setCardInOperatorModeState();
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      let roomId = await openAiAssistant();

      await addRoomEvent(matrixService, {
        event_id: 'event0',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@matic:boxel',
        content: {
          body: 'Say one word.',
          msgtype: 'org.boxel.message',
          formatted_body: 'Say one word.',
          format: 'org.matrix.custom.html',
        },
        origin_server_ts: Date.now() - 100,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });

      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@aibot:localhost',
        content: {
          body: 'French.',
          msgtype: 'm.text',
          formatted_body: 'French.',
          format: 'org.matrix.custom.html',
          isStreamingFinished: true,
        },
        origin_server_ts: Date.now() - 99,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });

      await addRoomEvent(matrixService, {
        event_id: 'event2',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@matic:boxel',
        content: {
          body: 'What is a french bulldog?',
          msgtype: 'org.boxel.message',
          formatted_body: 'What is a french bulldog?',
          format: 'org.matrix.custom.html',
        },
        origin_server_ts: Date.now() - 98,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });

      await addRoomEvent(matrixService, {
        event_id: 'event3',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@aibot:localhost',
        content: {
          body: 'French bulldog is a',
          msgtype: 'm.text',
          formatted_body: 'French bulldog is a',
          format: 'org.matrix.custom.html',
        },
        origin_server_ts: Date.now() - 97,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });

      await waitFor('[data-test-message-idx="3"]');

      assert
        .dom('[data-test-message-idx="1"] [data-test-ai-avatar]')
        .doesNotHaveClass(
          'ai-avatar-animated',
          'Answer to my previous question is not in progress',
        );
      assert
        .dom('[data-test-message-idx="3"] [data-test-ai-avatar]')
        .hasClass(
          'ai-avatar-animated',
          'Answer to my current question is in progress',
        );

      await addRoomEvent(matrixService, {
        event_id: 'event4',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@aibot:localhost',
        content: {
          body: 'French bulldog is a French breed of companion dog or toy dog.',
          msgtype: 'm.text',
          formatted_body:
            'French bulldog is a French breed of companion dog or toy dog',
          format: 'org.matrix.custom.html',
          isStreamingFinished: true, // This is an indicator from the ai bot that the message is finalized and the openai is done streaming
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'event3',
          },
        },
        origin_server_ts: Date.now() - 96,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });

      await waitFor('[data-test-message-idx="3"]');
      assert
        .dom('[data-test-message-idx="1"] [data-test-ai-avatar]')
        .doesNotHaveClass(
          'ai-avatar-animated',
          'Answer to my previous question is not in progress',
        );
      assert
        .dom('[data-test-message-idx="3"] [data-test-ai-avatar]')
        .doesNotHaveClass(
          'ai-avatar-animated',
          'Answer to my last question is not in progress',
        );
    });

    test('it does not display the streaming indicator when ai bot sends an option', async function (assert) {
      await setCardInOperatorModeState();
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      let roomId = await openAiAssistant();

      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        sender: '@aibot:localhost',
        content: {
          body: 'i am the body',
          msgtype: 'org.boxel.command',
          formatted_body: 'A patch',
          format: 'org.matrix.custom.html',
          data: JSON.stringify({
            command: {
              type: 'patchCard',
              id: `${testRealmURL}Person/fadhlan`,
              patch: {
                attributes: { firstName: 'Dave' },
              },
              eventId: 'patch1',
            },
          }),
          'm.relates_to': {
            rel_type: 'm.replace',
            event_id: 'patch1',
          },
        },
        status: null,
      });

      await waitFor('[data-test-message-idx="0"]');
      assert
        .dom('[data-test-message-idx="0"] [data-test-ai-avatar]')
        .doesNotHaveClass(
          'ai-avatar-animated',
          'ai bot patch message does not have a spinner',
        );
    });

    test('it can retry a message when receiving an error from the AI bot', async function (assert) {
      await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      let roomId = await openAiAssistant();

      await addRoomEvent(matrixService, {
        event_id: 'event1',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@testuser:staging',
        content: {
          body: 'I have a feeling something will go wrong',
          msgtype: 'org.boxel.message',
          formatted_body: 'I have a feeling something will go wrong',
          format: 'org.matrix.custom.html',
        },
        origin_server_ts: Date.now() - 100,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });

      await addRoomEvent(matrixService, {
        event_id: 'event2',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@aibot:localhost',
        content: {
          body: 'There was an error processing your request, please try again later',
          msgtype: 'm.text',
          formatted_body:
            'There was an error processing your request, please try again later',
          format: 'org.matrix.custom.html',
          isStreamingFinished: true,
          errorMessage: 'AI bot error',
        },
        origin_server_ts: Date.now() - 99,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });

      await addRoomEvent(matrixService, {
        event_id: 'event3',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@testuser:staging',
        content: {
          body: 'I have a feeling something will go wrong',
          msgtype: 'org.boxel.message',
          formatted_body: 'I have a feeling something will go wrong',
          format: 'org.matrix.custom.html',
        },
        origin_server_ts: Date.now() - 98,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });

      await addRoomEvent(matrixService, {
        event_id: 'event4',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@aibot:localhost',
        content: {
          body: 'There was an error processing your request, please try again later',
          msgtype: 'm.text',
          formatted_body:
            'There was an error processing your request, please try again later',
          format: 'org.matrix.custom.html',
          isStreamingFinished: true,
          errorMessage: 'AI bot error',
        },
        origin_server_ts: Date.now() - 97,
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      });

      await waitFor('[data-test-message-idx="0"]');
      assert
        .dom('[data-test-message-idx="1"]')
        .containsText(
          'There was an error processing your request, please try again later',
        );
      assert
        .dom('[data-test-message-idx="1"] [data-test-ai-bot-retry-button]')
        .doesNotExist('Only last errored message has a retry button');

      assert
        .dom('[data-test-message-idx="3"]')
        .containsText(
          'There was an error processing your request, please try again later',
        );
      assert
        .dom('[data-test-message-idx="3"] [data-test-ai-bot-retry-button]')
        .exists('Only last errored message has a retry button');

      assert.dom('[data-test-message-idx="4"]').doesNotExist();

      await click('[data-test-ai-bot-retry-button]');

      // This below is user's previous message that is sent again after retry button is clicked
      assert
        .dom('[data-test-message-idx="4"]')
        .exists('Retry message is sent to the AI bot');

      assert
        .dom('[data-test-message-idx="4"]')
        .containsText('I have a feeling something will go wrong');
    });

    test('replacement message should use `created` from the oldest message', async function (assert) {
      await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
      await renderComponent(
        class TestDriver extends GlimmerComponent {
          <template>
            <OperatorMode @onClose={{noop}} />
            <CardPrerender />
          </template>
        },
      );
      let roomId = await openAiAssistant();

      let firstMessage = {
        event_id: 'first-message-event',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@aibot:localhost',
        content: {
          body: 'This is the first message',
          msgtype: 'org.text',
          formatted_body: 'This is the first message',
          format: 'org.matrix.custom.html',
          'm.new_content': {
            body: 'This is the first message replacement comes after second message, but must be displayed before second message because it will be used creted from the oldest',
            msgtype: 'org.text',
            formatted_body:
              'This is the first message replacement comes after second message, but must be displayed before second message because it will be used creted from the oldest',
            format: 'org.matrix.custom.html',
          },
        },
        origin_server_ts: new Date(2024, 0, 3, 12, 30).getTime(),
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      };
      let secondMessage = {
        event_id: 'second-message-event',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@aibot:localhost',
        content: {
          body: 'This is the second message comes after the first message and before the replacement of the first message',
          msgtype: 'org.text',
          formatted_body:
            'This is the second message comes after the first message and before the replacement of the first message',
          format: 'org.matrix.custom.html',
        },
        origin_server_ts: new Date(2024, 0, 3, 12, 31).getTime(),
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      };
      let firstMessageReplacement = {
        event_id: 'first-message-replacement-event',
        room_id: roomId,
        state_key: 'state',
        type: 'm.room.message',
        sender: '@aibot:localhost',
        content: {
          body: 'This is the first message replacement comes after second message, but must be displayed before second message because it will be used creted from the oldest',
          msgtype: 'org.text',
          formatted_body:
            'This is the first message replacement comes after second message, but must be displayed before second message because it will be used creted from the oldest',
          format: 'org.matrix.custom.html',
          ['m.new_content']: {
            body: 'This is the first message replacement comes after second message, but must be displayed before second message because it will be used creted from the oldest',
            msgtype: 'org.text',
            formatted_body:
              'This is the first message replacement comes after second message, but must be displayed before second message because it will be used creted from the oldest',
            format: 'org.matrix.custom.html',
          },
          ['m.relates_to']: {
            event_id: 'first-message-event',
            rel_type: 'm.replace',
          },
        },
        origin_server_ts: new Date(2024, 0, 3, 12, 32).getTime(),
        unsigned: {
          age: 105,
          transaction_id: '1',
        },
        status: null,
      };

      await addRoomEvent(matrixService, firstMessage);

      await addRoomEvent(matrixService, secondMessage);

      await addRoomEvent(matrixService, firstMessageReplacement);

      await waitFor('[data-test-message-idx="0"]');

      assert
        .dom('[data-test-message-idx="0"]')
        .containsText(
          'Wednesday Jan 3, 2024, 12:30 PM This is the first message replacement comes after second message, but must be displayed before second message because it will be used creted from the oldest',
        );
      assert
        .dom('[data-test-message-idx="1"]')
        .containsText(
          'Wednesday Jan 3, 2024, 12:31 PM This is the second message comes after the first message and before the replacement of the first message',
        );
    });
  });

  test('it loads a card and renders its isolated view', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor('[data-test-person]');
    assert.dom('[data-test-boxel-header-title]').hasText('Person');
    assert
      .dom(`[data-test-boxel-header-icon="https://example-icon.test"]`)
      .exists();
    assert.dom('[data-test-person]').hasText('Fadhlan');
    assert.dom('[data-test-first-letter-of-the-name]').hasText('F');
    assert.dom('[data-test-city]').hasText('Bandung');
    assert.dom('[data-test-country]').hasText('Indonesia');
    assert.dom('[data-test-stack-card]').exists({ count: 1 });
    await waitFor('[data-test-pet="Mango"]');
    await click('[data-test-pet="Mango"]');
    await waitFor(`[data-test-stack-card="${testRealmURL}Pet/mango"]`);
    assert.dom('[data-test-stack-card]').exists({ count: 2 });
    assert.dom('[data-test-stack-card-index="1"]').includesText('Mango');
  });

  test<TestContextWithSave>('it auto saves the field value', async function (assert) {
    assert.expect(3);
    await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor('[data-test-person]');
    await click('[data-test-edit-button]');
    this.onSave((_, json) => {
      if (typeof json === 'string') {
        throw new Error('expected JSON save data');
      }
      assert.strictEqual(json.data.attributes?.firstName, 'EditedName');
    });
    await fillIn('[data-test-boxel-input]', 'EditedName');
    await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);

    await waitFor('[data-test-person="EditedName"]');
    assert.dom('[data-test-person]').hasText('EditedName');
    assert.dom('[data-test-first-letter-of-the-name]').hasText('E');
  });

  // TODO CS-6268 visual indicator for failed auto-save should build off of this test
  test('an error in auto-save is handled gracefully', async function (assert) {
    let done = assert.async();

    setupOnerror(function (error) {
      assert.ok(error, 'expected a global error');
      done();
    });

    await setCardInOperatorModeState(`${testRealmURL}BoomPet/paper`);

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor('[data-test-pet]');
    await click('[data-test-edit-button]');
    await fillIn('[data-test-field="boom"] input', 'Bad cat!');
    await setCardInOperatorModeState(`${testRealmURL}BoomPet/paper`);

    await waitFor('[data-test-pet]');
    // Card still runs (our error was designed to only fire during save)
    // despite save error
    assert.dom('[data-test-pet]').includesText('Paper Bad cat!');
  });

  test('displays add card button if user closes the only card in the stack and opens a card from card chooser', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor('[data-test-person]');
    assert.dom('[data-test-person]').isVisible();

    await click('[data-test-close-button]');
    await waitUntil(() => !document.querySelector('[data-test-stack-card]'));
    assert.dom('[data-test-person]').isNotVisible();
    assert.dom('[data-test-add-card-button]').isVisible();

    await click('[data-test-add-card-button]');
    assert.dom('[data-test-card-catalog-modal]').isVisible();

    await waitFor(`[data-test-select]`);
    await showSearchResult(
      'Operator Mode Workspace',
      `${testRealmURL}Person/fadhlan`,
    );

    await percySnapshot(assert);

    await click(`[data-test-select="${testRealmURL}Person/fadhlan"]`);
    await click('[data-test-card-catalog-go-button]');

    await waitFor(`[data-test-stack-card="${testRealmURL}Person/fadhlan"]`);
  });

  test('displays cards on cards-grid and includes `catalog-entry` instances', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);

    assert.dom(`[data-test-stack-card-index="0"]`).exists();
    assert.dom(`[data-test-cards-grid-item]`).exists();
    assert
      .dom(
        `[data-test-cards-grid-item="${testRealmURL}BlogPost/1"] [data-test-cards-grid-item-thumbnail-text]`,
      )
      .hasText('Blog Post');
    assert
      .dom(
        `[data-test-cards-grid-item="${testRealmURL}BlogPost/1"] [data-test-cards-grid-item-title]`,
      )
      .hasText('Outer Space Journey');
    assert
      .dom(
        `[data-test-cards-grid-item="${testRealmURL}BlogPost/1"] [data-test-cards-grid-item-display-name]`,
      )
      .hasText('Blog Post');
    assert
      .dom(
        `[data-test-cards-grid-item="${testRealmURL}CatalogEntry/publishing-packet"]`,
      )
      .exists('publishing-packet catalog-entry is displayed on cards-grid');
    assert
      .dom(`[data-test-cards-grid-item="${testRealmURL}CatalogEntry/pet-room"]`)
      .exists('pet-room catalog-entry instance is displayed on cards-grid');
  });

  test<TestContextWithSave>('can create a card using the cards-grid', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    let saved = new Deferred<void>();
    let savedCards = new Set<string>();
    this.onSave((url) => {
      savedCards.add(url.href);
      saved.fulfill();
    });

    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    assert.dom(`[data-test-stack-card-index="0"]`).exists();

    await click('[data-test-create-new-card-button]');
    assert
      .dom('[data-test-card-catalog-modal] [data-test-boxel-header-title]')
      .containsText('Choose a Catalog Entry card');
    await waitFor(
      `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/publishing-packet"]`,
    );
    assert.dom('[data-test-card-catalog-item]').exists({ count: 4 });

    await click(
      `[data-test-select="${testRealmURL}CatalogEntry/publishing-packet"]`,
    );
    await click('[data-test-card-catalog-go-button]');
    await waitFor('[data-test-stack-card-index="1"]');
    assert
      .dom('[data-test-stack-card-index="1"] [data-test-field="blogPost"]')
      .exists();
    await click(
      '[data-test-stack-card-index="1"] [data-test-more-options-button]',
    );
    await fillIn(`[data-test-field="title"] input`, 'New Post');
    await saved.promise;
    let packetId = [...savedCards].find((k) => k.includes('PublishingPacket'))!;
    await setCardInOperatorModeState(packetId);

    await waitFor(`[data-test-stack-card="${packetId}"]`);
    assert.dom(`[data-test-stack-card="${packetId}"]`).exists();
  });

  test('can open a card from the cards-grid and close it', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-stack-card-index]`);
    assert.dom(`[data-test-stack-card-index="0"]`).exists();

    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}Person/burcu"]`);

    await waitFor(`[data-test-stack-card-index="1"]`);
    assert.dom(`[data-test-stack-card-index="1"]`).exists(); // Opens card on the stack
    assert
      .dom(`[data-test-stack-card-index="1"] [data-test-boxel-header-title]`)
      .includesText('Person');

    await click('[data-test-stack-card-index="1"] [data-test-close-button]');
    assert.dom(`[data-test-stack-card-index="1"]`).doesNotExist();
  });

  test<TestContextWithSave>('create new card editor opens in the stack at each nesting level', async function (assert) {
    assert.expect(9);
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    let savedCards = new Set<string>();
    this.onSave((url) => savedCards.add(url.href));

    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    assert.dom(`[data-test-stack-card-index="0"]`).exists();

    await click('[data-test-create-new-card-button]');
    await waitFor(
      `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/publishing-packet"]`,
    );
    assert
      .dom('[data-test-card-catalog-modal] [data-test-boxel-header-title]')
      .containsText('Choose a Catalog Entry card');
    assert.dom('[data-test-card-catalog-item]').exists({ count: 4 });

    await click(
      `[data-test-select="${testRealmURL}CatalogEntry/publishing-packet"]`,
    );
    await click('[data-test-card-catalog-go-button]');
    await waitFor('[data-test-stack-card-index="1"]');
    assert
      .dom('[data-test-stack-card-index="1"] [data-test-field="blogPost"]')
      .exists();

    await click('[data-test-add-new]');
    await waitFor(`[data-test-card-catalog-modal]`);
    await click(`[data-test-card-catalog-create-new-button]`);

    await waitFor(`[data-test-stack-card-index="2"]`);
    assert.dom('[data-test-stack-card-index]').exists({ count: 3 });
    assert
      .dom('[data-test-stack-card-index="2"] [data-test-field="authorBio"]')
      .exists();

    // Update the blog post card first to trigger auto-save.
    // This allows us to simulate a scenario where the non-top item in the card-catalog-modal stack is saved before the top item.
    await fillIn(
      '[data-test-stack-card-index="2"] [data-test-field="title"] [data-test-boxel-input]',
      'Mad As a Hatter',
    );

    await click(
      '[data-test-stack-card-index="2"] [data-test-field="authorBio"] [data-test-add-new]',
    );
    await waitFor(`[data-test-card-catalog-modal]`);
    await click(`[data-test-card-catalog-create-new-button]`);

    await waitFor(`[data-test-stack-card-index="3"]`);

    assert
      .dom('[data-test-field="firstName"] [data-test-boxel-input]')
      .exists();
    await fillIn(
      '[data-test-field="firstName"] [data-test-boxel-input]',
      'Alice',
    );
    let authorId = [...savedCards].find((k) => k.includes('Author'))!;
    await waitFor(
      `[data-test-stack-card-index="3"][data-test-stack-card="${authorId}"]`,
    );
    await fillIn(
      '[data-test-field="lastName"] [data-test-boxel-input]',
      'Enwunder',
    );

    await click('[data-test-stack-card-index="3"] [data-test-close-button]');
    await waitFor('[data-test-stack-card-index="3"]', { count: 0 });

    await waitUntil(() =>
      /Alice\s*Enwunder/.test(
        document.querySelector(
          '[data-test-stack-card-index="2"] [data-test-field="authorBio"]',
        )!.textContent!,
      ),
    );

    await click('[data-test-stack-card-index="2"] [data-test-close-button]');
    await waitFor('[data-test-stack-card-index="2"]', { count: 0 });
    let packetId = [...savedCards].find((k) => k.includes('PublishingPacket'))!;
    await waitFor(
      `[data-test-stack-card-index="1"][data-test-stack-card="${packetId}"]`,
    );
    await fillIn(
      '[data-test-stack-card-index="1"] [data-test-field="socialBlurb"] [data-test-boxel-input]',
      `Everyone knows that Alice ran the show in the Brady household. But when Alice’s past comes to light, things get rather topsy turvy…`,
    );
    assert
      .dom('[data-test-stack-card-index="1"] [data-test-field="blogPost"]')
      .containsText('Mad As a Hatter by Alice Enwunder');

    this.onSave((_, json) => {
      if (typeof json === 'string') {
        throw new Error('expected JSON save data');
      }
      assert.strictEqual(
        json.data.attributes!.socialBlurb,
        `Everyone knows that Alice ran the show in the Brady household. But when Alice’s past comes to light, things get rather topsy turvy…`,
      );
    });

    await click('[data-test-stack-card-index="1"] [data-test-edit-button]');

    await waitUntil(() =>
      document
        .querySelector(`[data-test-stack-card="${packetId}"]`)
        ?.textContent?.includes(
          'Everyone knows that Alice ran the show in the Brady household.',
        ),
    );
  });

  test('can choose a card for a linksTo field that has an existing value', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/1`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}BlogPost/1"]`);
    await click('[data-test-edit-button]');

    assert.dom('[data-test-field="authorBio"]').containsText('Alien Bob');
    assert.dom('[data-test-add-new]').doesNotExist();

    await click('[data-test-remove-card]');
    assert.dom('[data-test-add-new]').exists();
    await click('[data-test-add-new]');
    await waitFor(`[data-test-card-catalog-modal]`);
    await click(`[data-test-card-catalog-create-new-button]`);

    await click('[data-test-add-new]');
    await waitFor(`[data-test-card-catalog-item="${testRealmURL}Author/2"]`);
    await click(`[data-test-select="${testRealmURL}Author/2"]`);
    assert
      .dom(
        `[data-test-card-catalog-item="${testRealmURL}Author/2"][data-test-card-catalog-item-selected]`,
      )
      .exists();

    await waitUntil(
      () =>
        (
          document.querySelector(`[data-test-card-catalog-go-button]`) as
            | HTMLButtonElement
            | undefined
        )?.disabled === false,
    );
    await click('[data-test-card-catalog-go-button]');

    await waitFor(`.operator-mode [data-test-author="R2-D2"]`);
    assert.dom('[data-test-field="authorBio"]').containsText('R2-D2');
  });

  test('can choose a card for a linksTo field that has no existing value', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/2`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}BlogPost/2"]`);
    await click('[data-test-edit-button]');
    assert.dom('[data-test-add-new]').exists();

    await click('[data-test-add-new]');
    await waitFor(`[data-test-card-catalog-item="${testRealmURL}Author/2"]`);
    await click(`[data-test-select="${testRealmURL}Author/2"]`);
    await click('[data-test-card-catalog-go-button]');

    await waitUntil(() => !document.querySelector('[card-catalog-modal]'));
    assert.dom('[data-test-field="authorBio"]').containsText('R2-D2');

    await click('[data-test-edit-button]');
    await waitFor('.operator-mode [data-test-blog-post-isolated]');

    assert
      .dom('.operator-mode [data-test-blog-post-isolated]')
      .hasText('Beginnings by R2-D2');
  });

  test<TestContextWithSave>('can create a new card to populate a linksTo field', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/2`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    let savedCards = new Set<string>();
    this.onSave((url) => savedCards.add(url.href));

    await waitFor(`[data-test-stack-card="${testRealmURL}BlogPost/2"]`);
    await click('[data-test-edit-button]');
    assert.dom('[data-test-add-new]').exists();

    await click('[data-test-add-new]');
    await waitFor(`[data-test-card-catalog-modal]`);
    await click(`[data-test-card-catalog-create-new-button]`);
    await waitFor('[data-test-stack-card-index="1"]');

    assert
      .dom('[data-test-stack-card-index="1"] [data-test-field="firstName"]')
      .exists();
    await fillIn(
      '[data-test-stack-card-index="1"] [data-test-field="firstName"] [data-test-boxel-input]',
      'Alice',
    );

    let authorId = [...savedCards].find((k) => k.includes('Author'))!;
    await waitFor(
      `[data-test-stack-card-index="1"][data-test-stack-card="${authorId}"]`,
    );

    await click('[data-test-stack-card-index="1"] [data-test-close-button]');
    await waitFor('[data-test-stack-card-index="1"]', { count: 0 });
    assert.dom('[data-test-add-new]').doesNotExist();
    assert.dom('[data-test-field="authorBio"]').containsText('Alice');

    await click('[data-test-stack-card-index="0"] [data-test-edit-button]');
    assert.dom('[data-test-blog-post-isolated]').hasText('Beginnings by Alice');
  });

  test('can remove the link for a linksTo field', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/1`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}BlogPost/1"]`);
    await click('[data-test-edit-button]');

    assert.dom('[data-test-field="authorBio"]').containsText('Alien Bob');
    await click('[data-test-field="authorBio"] [data-test-remove-card]');
    await click('[data-test-edit-button]');

    await waitFor('.operator-mode [data-test-blog-post-isolated]');
    assert
      .dom('.operator-mode [data-test-blog-post-isolated]')
      .hasText('Outer Space Journey by');
  });

  test('can add a card to a linksToMany field with existing values', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/burcu`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}Person/burcu"]`);
    await click('[data-test-edit-button]');

    assert.dom('[data-test-field="friends"]').containsText('Jackie Woody');
    assert.dom('[data-test-field="friends"] [data-test-add-new]').exists();

    await click('[data-test-links-to-many="friends"] [data-test-add-new]');
    await waitFor(`[data-test-card-catalog-item="${testRealmURL}Pet/mango"]`);
    await click(`[data-test-select="${testRealmURL}Pet/mango"]`);
    await click('[data-test-card-catalog-go-button]');

    await waitUntil(() => !document.querySelector('[card-catalog-modal]'));
    assert
      .dom('[data-test-field="friends"]')
      .containsText('Jackie Woody Buzz Mango');
  });

  test('can add a card to a linksTo field creating a loop', async function (assert) {
    // Friend A already links to friend B.
    // This test links B back to A
    await setCardInOperatorModeState(`${testRealmURL}Friend/friend-b`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}Friend/friend-b"]`);
    await click('[data-test-edit-button]');
    assert.dom('[data-test-field="friend"] [data-test-add-new]').exists();

    await click('[data-test-field="friend"] [data-test-add-new]');

    await waitFor(
      `[data-test-card-catalog-item="${testRealmURL}Friend/friend-a"]`,
    );
    await click(`[data-test-select="${testRealmURL}Friend/friend-a"]`);
    await click('[data-test-card-catalog-go-button]');

    await waitUntil(() => !document.querySelector('[card-catalog-modal]'));

    // Normally we'd only have an assert like this at the end that may work,
    // but the rest of the application may be broken.

    assert
      .dom('[data-test-stack-card] [data-test-field="friend"]')
      .containsText('Friend A');

    // Instead try and go somewhere else in the application to see if it's broken
    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').exists();
    assert.dom('[data-test-submode-switcher]').hasText('Interact');

    await click(
      '[data-test-submode-switcher] .submode-switcher-dropdown-trigger',
    );
    await click('[data-test-boxel-menu-item-text="Code"]');
    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').hasText('Code');
  });

  test('can add a card to linksToMany field that has no existing values', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}Person/fadhlan"]`);
    await click('[data-test-edit-button]');

    assert.dom('[data-test-field="friends"] [data-test-pet]').doesNotExist();
    assert.dom('[data-test-add-new]').hasText('Add Pets');
    await click('[data-test-add-new]');
    await waitFor(`[data-test-card-catalog-item="${testRealmURL}Pet/mango"]`);
    await click(`[data-test-select="${testRealmURL}Pet/jackie"]`);
    await click('[data-test-card-catalog-go-button]');

    await waitUntil(() => !document.querySelector('[card-catalog-modal]'));
    assert.dom('[data-test-field="friends"]').containsText('Jackie');
  });

  test('can change the item selection in a linksToMany field', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/burcu`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}Person/burcu"]`);
    await click('[data-test-edit-button]');

    assert.dom('[data-test-field="friends"]').containsText('Jackie Woody');
    await click(
      '[data-test-links-to-many="friends"] [data-test-item="1"] [data-test-remove-card]',
    );
    assert.dom('[data-test-field="friends"]').containsText('Jackie');

    await click('[data-test-links-to-many="friends"] [data-test-add-new]');
    await waitFor(`[data-test-card-catalog-item="${testRealmURL}Pet/mango"]`);
    await click(`[data-test-select="${testRealmURL}Pet/mango"]`);
    await click('[data-test-card-catalog-go-button]');

    await waitUntil(() => !document.querySelector('[card-catalog-modal]'));
    assert.dom('[data-test-field="friends"]').containsText('Mango');
  });

  test<TestContextWithSave>('can create a new card to add to a linksToMany field from card chooser', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    let savedCards = new Set<string>();
    this.onSave((url) => savedCards.add(url.href));

    await waitFor(`[data-test-stack-card="${testRealmURL}Person/fadhlan"]`);
    await click('[data-test-edit-button]');

    assert.dom('[data-test-field="friends"] [data-test-pet]').doesNotExist();
    await click('[data-test-links-to-many="friends"] [data-test-add-new]');

    await waitFor(`[data-test-card-catalog-modal]`);
    assert
      .dom('[data-test-card-catalog-create-new-button]')
      .hasText('Create New Pet');
    await click('[data-test-card-catalog-create-new-button]');

    await waitFor(`[data-test-stack-card-index="1"]`);
    await fillIn(
      '[data-test-stack-card-index="1"] [data-test-field="name"] [data-test-boxel-input]',
      'Woodster',
    );
    let petId = [...savedCards].find((k) => k.includes('Pet'))!;
    await waitFor(
      `[data-test-stack-card-index="1"][data-test-stack-card="${petId}"]`,
    );
    await click('[data-test-stack-card-index="1"] [data-test-close-button]');
    await waitUntil(
      () => !document.querySelector('[data-test-stack-card-index="1"]'),
    );
    assert.dom('[data-test-field="friends"]').containsText('Woodster');
  });

  test<TestContextWithSave>('does not create a new card to add to a linksToMany field from card chooser, if user cancel the edit view', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/burcu`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    let savedCards = new Set<string>();
    this.onSave((url) => savedCards.add(url.href));

    await waitFor(`[data-test-stack-card="${testRealmURL}Person/burcu"]`);
    await click('[data-test-edit-button]');

    assert.dom('[data-test-field="friends"]').containsText('Jackie Woody');
    await click('[data-test-links-to-many="friends"] [data-test-add-new]');

    await waitFor(`[data-test-card-catalog-modal]`);
    assert
      .dom('[data-test-card-catalog-create-new-button]')
      .hasText('Create New Pet');
    await click('[data-test-card-catalog-create-new-button]');

    await waitFor(`[data-test-stack-card-index="1"]`);
    await fillIn(
      '[data-test-stack-card-index="1"] [data-test-field="name"] [data-test-boxel-input]',
      'Woodster',
    );
    let petId = [...savedCards].find((k) => k.includes('Pet'))!;
    await waitFor(
      `[data-test-stack-card-index="1"][data-test-stack-card="${petId}"]`,
    );
    await click('[data-test-stack-card-index="1"] [data-test-close-button]');
    await waitUntil(
      () => !document.querySelector('[data-test-stack-card-index="1"]'),
    );
    assert.dom('[data-test-field="friends"]').containsText('Jackie Woody');

    //Ensuring the card chooser modal doesn't get stuck
    await click('[data-test-links-to-many="friends"] [data-test-add-new]');
    await waitFor(`[data-test-card-catalog-modal]`);
    assert
      .dom('[data-test-card-catalog-create-new-button]')
      .hasText('Create New Pet');
  });

  test('can remove all items of a linksToMany field', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/burcu`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}Person/burcu"]`);
    assert.dom(`[data-test-plural-view-item]`).exists({ count: 3 });
    await click('[data-test-edit-button]');
    assert.dom('[data-test-field="friends"]').containsText('Jackie Woody');

    await click(
      '[data-test-links-to-many="friends"] [data-test-item="1"] [data-test-remove-card]',
    );
    await click(
      '[data-test-links-to-many="friends"] [data-test-item="0"] [data-test-remove-card]',
    );
    await click(
      '[data-test-links-to-many="friends"] [data-test-item="0"] [data-test-remove-card]',
    );

    await click('[data-test-edit-button]');
    await waitFor(`[data-test-person="Burcu"]`);
    assert
      .dom(`[data-test-stack-card="${testRealmURL}Person/burcu"]`)
      .doesNotContainText('Jackie');
    assert.dom(`[data-test-plural-view-item]`).doesNotExist();
  });

  test('can close cards by clicking the header of a card deeper in the stack', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`);
    await waitFor(`[data-test-stack-card-index="1"]`);
    assert.dom(`[data-test-stack-card-index="1"]`).exists();
    await waitFor('[data-test-person]');

    await waitFor('[data-test-cards-grid-item]');
    await click('[data-test-cards-grid-item]');
    assert.dom(`[data-test-stack-card-index="2"]`).exists();
    await click('[data-test-stack-card-index="0"] [data-test-boxel-header]');
    assert.dom(`[data-test-stack-card-index="2"]`).doesNotExist();
    assert.dom(`[data-test-stack-card-index="1"]`).doesNotExist();
    assert.dom(`[data-test-stack-card-index="0"]`).exists();
  });

  test(`displays realm name as cards grid card title and card's display name as other card titles`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    assert.dom(`[data-test-stack-card-header]`).containsText(realmName);

    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`);
    await waitFor(`[data-test-stack-card-index="1"]`);
    assert.dom(`[data-test-stack-card-index="1"]`).exists();
    assert
      .dom(
        `[data-test-stack-card="${testRealmURL}Person/fadhlan"] [data-test-boxel-header-title]`,
      )
      .containsText('Person');

    assert.dom(`[data-test-cards-grid-cards]`).isNotVisible();
    assert.dom(`[data-test-create-new-card-button]`).isNotVisible();
  });

  test(`displays recently accessed card`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    assert.dom(`[data-test-stack-card-header]`).containsText(realmName);

    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`);
    await waitFor(`[data-test-stack-card-index="1"]`);

    assert
      .dom(
        `[data-test-stack-card="${testRealmURL}Person/fadhlan"] [data-test-boxel-header-title]`,
      )
      .containsText('Person');

    assert.dom(`[data-test-cards-grid-cards]`).isNotVisible();
    assert.dom(`[data-test-create-new-card-button]`).isNotVisible();

    await focus(`[data-test-search-field]`);
    assert
      .dom(`[data-test-search-result="${testRealmURL}Person/fadhlan"]`)
      .exists();
    await click(`[data-test-search-sheet-cancel-button]`);
    await click(`[data-test-stack-card-index="1"] [data-test-close-button]`);

    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}Person/burcu"]`);
    await waitFor(`[data-test-stack-card-index="1"]`);

    await focus(`[data-test-search-field]`);
    assert.dom(`[data-test-search-sheet-recent-card]`).exists({ count: 2 });
    assert
      .dom(
        `[data-test-search-sheet-recent-card="0"][data-test-search-result="${testRealmURL}Person/burcu"]`,
      )
      .exists();
    assert
      .dom(
        `[data-test-search-sheet-recent-card="1"][data-test-search-result="${testRealmURL}Person/fadhlan"]`,
      )
      .exists();
  });

  test(`displays recently accessed card, maximum 10 cards`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    assert.dom(`[data-test-stack-card-header]`).containsText(realmName);

    await waitFor(`[data-test-cards-grid-item]`);
    for (let i = 1; i <= 11; i++) {
      await click(`[data-test-cards-grid-item="${testRealmURL}Person/${i}"]`);
      await waitFor(
        `[data-test-stack-card-index="1"][data-test-stack-card="${testRealmURL}Person/${i}"]`,
      );
      await click(
        `[data-test-stack-card-index="1"][data-test-stack-card="${testRealmURL}Person/${i}"] [data-test-close-button]`,
      );
      await waitFor(
        `[data-test-stack-card-index="1"][data-test-stack-card="${testRealmURL}Person/${i}"]`,
        { count: 0 },
      );
    }

    await focus(`[data-test-search-field]`);
    await waitFor(`[data-test-search-result]`);
    assert.dom(`[data-test-search-result]`).exists({ count: 10 });
  });

  test(`displays searching results`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    assert.dom(`[data-test-stack-card-header]`).containsText(realmName);

    await waitFor(`[data-test-cards-grid-item]`);

    await focus(`[data-test-search-field]`);
    await typeIn(`[data-test-search-field]`, 'Ma');
    assert.dom(`[data-test-search-label]`).containsText('Searching for “Ma”');

    await waitFor(`[data-test-search-sheet-search-result]`);
    assert.dom(`[data-test-search-label]`).containsText('3 Results for “Ma”');
    assert.dom(`[data-test-search-sheet-search-result]`).exists({ count: 3 });
    assert.dom(`[data-test-search-result="${testRealmURL}Pet/mango"]`).exists();
    assert
      .dom(`[data-test-search-result="${testRealmURL}Author/mark"]`)
      .exists();

    await click(`[data-test-search-sheet-cancel-button]`);

    await focus(`[data-test-search-field]`);
    await typeIn(`[data-test-search-field]`, 'Mark J');
    await waitFor(`[data-test-search-sheet-search-result]`);
    assert
      .dom(`[data-test-search-label]`)
      .containsText('1 Result for “Mark J”');

    //Ensures that there is no cards when reopen the search sheet
    await click(`[data-test-search-sheet-cancel-button]`);
    await focus(`[data-test-search-field]`);
    assert.dom(`[data-test-search-label]`).doesNotExist();
    assert.dom(`[data-test-search-sheet-search-result]`).doesNotExist();

    //No cards match
    await focus(`[data-test-search-field]`);
    await typeIn(`[data-test-search-field]`, 'No Cards');
    assert
      .dom(`[data-test-search-label]`)
      .containsText('Searching for “No Cards”');

    await waitUntil(
      () =>
        (
          document.querySelector('[data-test-search-label]') as HTMLElement
        )?.innerText.includes('0'),
      {
        timeoutMessage: 'timed out waiting for search label to show 0 results',
      },
    );
    assert
      .dom(`[data-test-search-label]`)
      .containsText('0 Results for “No Cards”');
    assert.dom(`[data-test-search-sheet-search-result]`).doesNotExist();
  });

  test(`can specify a card by URL in the card chooser`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-create-new-card-button]`);
    await waitFor(`[data-test-card-catalog-item]`);
    await fillIn(
      `[data-test-search-field]`,
      `https://cardstack.com/base/types/card`,
    );

    await waitFor('[data-test-card-catalog-item]', {
      count: 1,
    });

    assert
      .dom(`[data-test-realm="Base Workspace"] [data-test-results-count]`)
      .hasText('1 result');

    assert.dom('[data-test-card-catalog-item]').exists({ count: 1 });
    await click('[data-test-select]');

    await waitFor('[data-test-card-catalog-go-button][disabled]', {
      count: 0,
    });
    await click('[data-test-card-catalog-go-button]');

    await waitFor(`[data-test-stack-card-index="1"] [data-test-field="title"]`);
    assert
      .dom(`[data-test-stack-card-index="1"] [data-test-field="title"]`)
      .exists();
    assert
      .dom(`[data-test-stack-card-index="1"] [data-test-field="description"]`)
      .exists();
    assert
      .dom(`[data-test-stack-card-index="1"] [data-test-field="thumbnailURL"]`)
      .exists();
  });

  test(`can search by card title in card chooser`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-create-new-card-button]`);
    await waitFor('[data-test-card-catalog-item]');
    assert
      .dom(
        `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/publishing-packet"]`,
      )
      .exists();

    await fillIn(`[data-test-search-field]`, `pet`);
    await waitFor(
      `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/publishing-packet"]`,
      { count: 0 },
    );
    assert.dom(`[data-test-card-catalog-item]`).exists({ count: 2 });

    await fillIn(`[data-test-search-field]`, `publishing packet`);
    await waitUntil(
      () =>
        !document.querySelector(
          `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/pet-card"]`,
        ),
    );
    assert.dom(`[data-test-card-catalog-item]`).exists({ count: 1 });

    await click(
      `[data-test-select="${testRealmURL}CatalogEntry/publishing-packet"]`,
    );
    await waitUntil(
      () =>
        (
          document.querySelector(`[data-test-card-catalog-go-button]`) as
            | HTMLButtonElement
            | undefined
        )?.disabled === false,
    );
    await click(`[data-test-card-catalog-go-button]`);
    await waitFor('[data-test-stack-card-index="1"]');
    assert.dom('[data-test-stack-card-index="1"]').exists();
    assert
      .dom('[data-test-stack-card-index="1"] [data-test-boxel-header-title]')
      .hasText('Publishing Packet');
  });

  test(`can search by card title when opening card chooser from a field editor`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/2`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}BlogPost/2"]`);
    assert.dom(`[data-test-stack-card="${testRealmURL}BlogPost/2"]`).exists();
    await click(
      `[data-test-stack-card="${testRealmURL}BlogPost/2"] [data-test-edit-button]`,
    );
    await waitFor(`[data-test-field="authorBio"]`);
    await click('[data-test-add-new]');

    await waitFor('[data-test-card-catalog-item]');
    assert
      .dom('[data-test-card-catalog-modal] [data-test-boxel-header-title]')
      .hasText('Choose an Author card');
    assert.dom('[data-test-results-count]').hasText('3 results');

    await fillIn(`[data-test-search-field]`, `alien`);
    await waitFor('[data-test-card-catalog-item]');
    assert.dom(`[data-test-select="${testRealmURL}Author/1"]`).exists();
  });

  test(`displays no cards available message if search result does not exist`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-create-new-card-button]`);
    await waitFor('[data-test-card-catalog-item]');

    await fillIn(`[data-test-search-field]`, `friend`);
    await waitFor('[data-test-card-catalog-item]', { count: 0 });
    assert.dom(`[data-test-card-catalog]`).hasText('No cards available');
  });

  test(`can filter by realm after searching in card catalog`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-create-new-card-button]`);
    await waitFor('[data-test-card-catalog-item]');
    assert.dom(`[data-test-card-catalog-item]`).exists({ count: 4 });

    await fillIn(`[data-test-search-field]`, `general`);
    await waitFor(
      `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/pet-card"]`,
      { count: 0 },
    );
    assert.dom(`[data-test-card-catalog-item]`).exists({ count: 2 });
    assert.dom(`[data-test-realm]`).exists({ count: 2 });
    assert.dom('[data-test-realm="Operator Mode Workspace"]').exists();
    assert
      .dom(
        '[data-test-realm="Operator Mode Workspace"] [data-test-results-count]',
      )
      .hasText('1 result');
    assert
      .dom(
        `[data-test-realm="Operator Mode Workspace"] [data-test-select="${testRealmURL}CatalogEntry/pet-room"]`,
      )
      .exists();
    assert.dom('[data-test-realm="Base Workspace"]').exists();
    assert
      .dom('[data-test-realm="Base Workspace"] [data-test-results-count]')
      .hasText('1 result');
    assert
      .dom(
        `[data-test-realm="Base Workspace"] [data-test-select="${baseRealm.url}types/card"]`,
      )
      .exists();

    await click('[data-test-realm-filter-button]');
    await click('[data-test-boxel-menu-item-text="Base Workspace"]');
    assert.dom(`[data-test-realm]`).exists({ count: 1 });
    assert.dom('[data-test-realm="Operator Mode Workspace"]').doesNotExist();
    assert.dom('[data-test-realm="Base Workspace"]').exists();
    assert.dom(`[data-test-select="${baseRealm.url}types/card"]`).exists();

    await click('[data-test-realm-filter-button]');
    await click('[data-test-boxel-menu-item-text="Operator Mode Workspace"]');
    assert.dom('[data-test-realm="Operator Mode Workspace"]').exists();
    assert.dom('[data-test-realm="Base Workspace"]').exists();
    assert.dom(`[data-test-card-catalog-item]`).exists({ count: 2 });

    await fillIn(`[data-test-search-field]`, '');
    await waitFor(
      `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/pet-card"]`,
    );
    assert
      .dom(`[data-test-card-catalog-item]`)
      .exists({ count: 4 }, 'can clear search input');

    await fillIn(`[data-test-search-field]`, 'pet');
    await waitFor(
      `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/pet-card"]`,
    );
    await click('[data-test-realm-filter-button]');
    await click('[data-test-boxel-menu-item-text="Operator Mode Workspace"]');
    await waitFor('[data-test-card-catalog-item]', { count: 0 });
    assert.dom('[data-test-card-catalog]').hasText('No cards available');
  });

  test(`can open new card editor in the stack after searching in card catalog`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-create-new-card-button]`);
    await waitFor('[data-test-card-catalog-item]');

    await typeIn(`[data-test-search-field]`, `pet`);
    await waitFor(
      `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/publishing-packet"]`,
      { count: 0 },
    );
    assert.dom(`[data-test-card-catalog-item]`).exists({ count: 2 });

    await click(`[data-test-select="${testRealmURL}CatalogEntry/pet-card"]`);
    assert
      .dom(
        `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/pet-card"][data-test-card-catalog-item-selected]`,
      )
      .exists({ count: 1 });

    await click('[data-test-card-catalog-go-button]');
    await waitFor('[data-test-stack-card-index="1"]');
    assert
      .dom('[data-test-stack-card-index="1"] [data-test-boxel-header-title]')
      .hasText('Pet');
  });

  test(`cancel button closes the catalog-entry card picker`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-create-new-card-button]`);

    await typeIn(`[data-test-search-field]`, `pet`);
    assert.dom(`[data-test-search-field]`).hasValue('pet');
    await waitFor('[data-test-card-catalog-item]', { count: 2 });
    await click(`[data-test-select="${testRealmURL}CatalogEntry/pet-room"]`);
    assert
      .dom(
        `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/pet-room"][data-test-card-catalog-item-selected]`,
      )
      .exists({ count: 1 });

    await click('[data-test-card-catalog-cancel-button]');
    await waitFor('[data-test-card-catalog]', { count: 0 });

    assert.dom('[data-test-operator-mode-stack="0"]').exists();
    assert
      .dom('[data-test-operator-mode-stack="1"]')
      .doesNotExist('no cards are added');

    await click(`[data-test-create-new-card-button]`);
    await waitFor('[data-test-card-catalog-item]');
    assert
      .dom(`[data-test-search-field]`)
      .hasNoValue('Card picker state is reset');
    assert.dom('[data-test-card-catalog-item-selected]').doesNotExist();
  });

  test(`cancel button closes the field picker`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/2`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}BlogPost/2"]`);
    await click('[data-test-edit-button]');
    await click(`[data-test-field="authorBio"] [data-test-add-new]`);

    await waitFor('[data-test-card-catalog-modal]');
    await waitFor('[data-test-card-catalog-item]', { count: 3 });
    await typeIn(`[data-test-search-field]`, `bob`);
    assert.dom(`[data-test-search-field]`).hasValue('bob');
    await waitFor('[data-test-card-catalog-item]', { count: 1 });
    await click(`[data-test-select="${testRealmURL}Author/1"]`);
    assert
      .dom(
        `[data-test-card-catalog-item="${testRealmURL}Author/1"][data-test-card-catalog-item-selected]`,
      )
      .exists({ count: 1 });

    await click('[data-test-card-catalog-cancel-button]');
    await waitFor('[data-test-card-catalog]', { count: 0 });

    assert
      .dom(`[data-test-field="authorBio"] [data-test-add-new]`)
      .exists('no card is chosen');

    await click(`[data-test-field="authorBio"] [data-test-add-new]`);
    assert
      .dom(`[data-test-search-field]`)
      .hasNoValue('Field picker state is reset');
    assert.dom('[data-test-card-catalog-item-selected]').doesNotExist();
  });

  test(`can add a card to the stack by URL from search sheet`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);
    await focus(`[data-test-search-field]`);

    await click('[data-test-search-field]');

    assert
      .dom(`[data-test-boxel-input-validation-state="invalid"]`)
      .doesNotExist('invalid state is not shown');

    await fillIn('[data-test-search-field]', 'http://localhost:4202/test/man');
    await waitFor(`[data-test-boxel-input-validation-state="invalid"]`);

    assert
      .dom('[data-test-search-label]')
      .containsText('No card found at http://localhost:4202/test/man');
    assert.dom('[data-test-search-sheet-search-result]').doesNotExist();
    assert.dom('[data-test-boxel-input-validation-state="invalid"]').exists();

    await fillIn(
      '[data-test-search-field]',
      'http://localhost:4202/test/mango',
    );
    await waitFor('[data-test-search-sheet-search-result]');

    assert
      .dom('[data-test-search-label]')
      .containsText('Card found at http://localhost:4202/test/mango');
    assert.dom('[data-test-search-sheet-search-result]').exists({ count: 1 });
    assert
      .dom(`[data-test-boxel-input-validation-state="invalid"]`)
      .doesNotExist();

    await fillIn('[data-test-search-field]', 'http://localhost:4202/test/man');
    await waitFor(`[data-test-boxel-input-validation-state="invalid"]`);

    assert
      .dom('[data-test-search-label]')
      .containsText('No card found at http://localhost:4202/test/man');
    assert.dom('[data-test-search-sheet-search-result]').doesNotExist();
    assert.dom('[data-test-boxel-input-validation-state="invalid"]').exists();

    await fillIn(
      '[data-test-search-field]',
      'http://localhost:4202/test/mango',
    );
    await waitFor('[data-test-search-sheet-search-result]');

    await click('[data-test-search-sheet-search-result]');

    await waitFor(`[data-test-stack-card="http://localhost:4202/test/mango"]`);
    assert
      .dom(
        `[data-test-stack-card="http://localhost:4202/test/mango"] [data-test-field-component-card]`,
      )
      .containsText('Mango', 'the card is rendered in the stack');
  });

  test(`can select one or more cards on cards-grid and unselect`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    assert.dom(`[data-test-cards-grid-cards]`).exists();

    await waitFor(
      `[data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`,
    );
    assert.dom('[data-test-overlay-selected]').doesNotExist();

    await click(`[data-test-overlay-select="${testRealmURL}Person/fadhlan"]`);
    assert
      .dom(`[data-test-overlay-selected="${testRealmURL}Person/fadhlan"]`)
      .exists();
    assert.dom('[data-test-overlay-selected]').exists({ count: 1 });

    await click(`[data-test-overlay-select="${testRealmURL}Pet/jackie"]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}Author/1"]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}BlogPost/2"]`);
    assert.dom('[data-test-overlay-selected]').exists({ count: 4 });

    await click(`[data-test-cards-grid-item="${testRealmURL}Pet/jackie"]`);
    assert.dom('[data-test-overlay-selected]').exists({ count: 3 });

    await click(`[data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}BlogPost/2"]`);
    await click(`[data-test-overlay-select="${testRealmURL}Author/1"]`);
    assert.dom('[data-test-overlay-selected]').doesNotExist();

    await click(`[data-test-cards-grid-item="${testRealmURL}Person/fadhlan"]`);
    await waitFor(`[data-test-stack-card-index="1"]`, { count: 1 });
  });

  test('displays realm name as header title when hovering realm icon', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/fadhlan`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor('[data-test-person]');
    assert.dom('[data-test-boxel-header-title]').hasText('Person');
    assert
      .dom(`[data-test-boxel-header-icon="https://example-icon.test"]`)
      .exists();
    await triggerEvent(`[data-test-boxel-header-icon]`, 'mouseenter');
    assert
      .dom('[data-test-boxel-header-title]')
      .hasText('In Operator Mode Workspace');
    await triggerEvent(`[data-test-boxel-header-icon]`, 'mouseleave');
    assert.dom('[data-test-boxel-header-title]').hasText('Person');
  });

  test(`it has an option to copy the card url`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}Person/burcu`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor('[data-test-more-options-button]');
    await click('[data-test-more-options-button]');
    await click('[data-test-boxel-menu-item-text="Copy Card URL"]');
    assert.dom('[data-test-boxel-menu-item]').doesNotExist();
  });

  test(`"links to" field has an overlay header and click on the embedded card will open it on the stack`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/1`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    // Linked cards have the realm's icon in the overlaid header title
    await waitFor('[data-test-overlay-card-display-name="Author"]');
    assert
      .dom('[data-test-overlay-card-display-name="Author"] .header-title img')
      .hasAttribute('src', 'https://example-icon.test');

    await click('[data-test-author]');
    await waitFor('[data-test-stack-card-index="1"]');
    assert.dom('[data-test-stack-card-index]').exists({ count: 2 });
    assert
      .dom('[data-test-stack-card-index="1"] [data-test-boxel-header-title]')
      .includesText('Author');
  });

  test(`toggles mode switcher`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/1`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').exists();
    assert.dom('[data-test-submode-switcher]').hasText('Interact');

    await click('[data-test-submode-switcher] > [data-test-boxel-button]');

    await click('[data-test-boxel-menu-item-text="Code"]');
    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').hasText('Code');
    assert.dom('[data-test-submode-arrow-direction="down"]').exists();

    await click('[data-test-submode-switcher] > [data-test-boxel-button]');
    await click('[data-test-boxel-menu-item-text="Interact"]');
    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').hasText('Interact');
    assert.dom('[data-test-submode-arrow-direction="down"]').exists();
  });

  test(`card url bar shows realm info of valid URL`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/1`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').exists();
    assert.dom('[data-test-submode-switcher]').hasText('Interact');

    await click(
      '[data-test-submode-switcher] .submode-switcher-dropdown-trigger',
    );
    await click('[data-test-boxel-menu-item-text="Code"]');
    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').hasText('Code');
    await waitUntil(() =>
      document
        .querySelector('[data-test-card-url-bar-realm-info]')
        ?.textContent?.includes('Operator Mode Workspace'),
    );

    assert.dom('[data-test-card-url-bar]').exists();
    assert
      .dom('[data-test-card-url-bar-realm-info]')
      .hasText('in Operator Mode Workspace');
    assert
      .dom('[data-test-card-url-bar-input]')
      .hasValue(`${testRealmURL}BlogPost/1.json`);

    await fillIn(
      '[data-test-card-url-bar-input]',
      `${testRealmURL}Pet/mango.json`,
    );
    await triggerKeyEvent(
      '[data-test-card-url-bar-input]',
      'keypress',
      'Enter',
    );
    await blur('[data-test-card-url-bar-input]');
    assert
      .dom('[data-test-card-url-bar-realm-info]')
      .hasText('in Operator Mode Workspace');
    assert
      .dom('[data-test-card-url-bar-input]')
      .hasValue(`${testRealmURL}Pet/mango.json`);
    assert.dom('[data-test-card-url-bar-error]').doesNotExist();
  });

  test(`card url bar shows error message when URL is invalid`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/1`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor('[data-test-submode-switcher]');
    await click(
      '[data-test-submode-switcher] .submode-switcher-dropdown-trigger',
    );
    await click('[data-test-boxel-menu-item-text="Code"]');

    await waitUntil(() =>
      document
        .querySelector('[data-test-card-url-bar-realm-info]')
        ?.textContent?.includes('Operator Mode Workspace'),
    );
    assert.dom('[data-test-card-url-bar]').exists();
    assert
      .dom('[data-test-card-url-bar-realm-info]')
      .hasText('in Operator Mode Workspace');
    assert
      .dom('[data-test-card-url-bar-input]')
      .hasValue(`${testRealmURL}BlogPost/1.json`);

    await fillIn(
      '[data-test-card-url-bar-input]',
      `${testRealmURL}Pet/NotFoundCard`,
    );
    await triggerKeyEvent(
      '[data-test-card-url-bar-input]',
      'keypress',
      'Enter',
    );
    assert
      .dom('[data-test-card-url-bar-error]')
      .containsText('This resource does not exist');

    await percySnapshot(assert);

    await fillIn('[data-test-card-url-bar-input]', `Wrong URL`);
    await triggerKeyEvent(
      '[data-test-card-url-bar-input]',
      'keypress',
      'Enter',
    );
    assert
      .dom('[data-test-card-url-bar-error]')
      .containsText('Not a valid URL');
  });

  test('user can dismiss url bar error message', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/1`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor('[data-test-submode-switcher]');
    await click(
      '[data-test-submode-switcher] .submode-switcher-dropdown-trigger',
    );
    await click('[data-test-boxel-menu-item-text="Code"]');
    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').hasText('Code');

    await waitUntil(() =>
      document
        .querySelector('[data-test-card-url-bar-realm-info]')
        ?.textContent?.includes('Operator Mode Workspace'),
    );
    await fillIn(
      '[data-test-card-url-bar-input]',
      `${testRealmURL}Pet/NotFoundCard`,
    );
    await triggerKeyEvent(
      '[data-test-card-url-bar-input]',
      'keypress',
      'Enter',
    );
    assert.dom('[data-test-card-url-bar-error]').exists();

    await click('[data-test-dismiss-url-error-button]');
    assert.dom('[data-test-card-url-bar-error]').doesNotExist();

    await fillIn(
      '[data-test-card-url-bar-input]',
      `${testRealmURL}Pet/NotFoundCard_2`,
    );
    await triggerKeyEvent(
      '[data-test-card-url-bar-input]',
      'keypress',
      'Enter',
    );
    assert.dom('[data-test-card-url-bar-error]').exists();

    await fillIn(
      '[data-test-card-url-bar-input]',
      `${testRealmURL}Pet/mango.json`,
    );
    await triggerKeyEvent(
      '[data-test-card-url-bar-input]',
      'keypress',
      'Enter',
    );
    assert.dom('[data-test-card-url-bar-error]').doesNotExist();
  });

  test(`card url bar URL reacts to external changes of code path when user is not editing`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/1`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').exists();
    assert.dom('[data-test-submode-switcher]').hasText('Interact');

    await click(
      '[data-test-submode-switcher] .submode-switcher-dropdown-trigger',
    );
    await waitFor('[data-test-boxel-menu-item-text]');
    await click('[data-test-boxel-menu-item-text="Code"]');
    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').hasText('Code');
    await waitUntil(() =>
      document
        .querySelector('[data-test-card-url-bar-realm-info]')
        ?.textContent?.includes('Operator Mode Workspace'),
    );

    assert
      .dom('[data-test-card-url-bar-input]')
      .hasValue(`${testRealmURL}BlogPost/1.json`);

    let operatorModeStateService = this.owner.lookup(
      'service:operator-mode-state-service',
    ) as OperatorModeStateService;
    operatorModeStateService.updateCodePath(
      new URL(`${testRealmURL}person.gts`),
    );

    await waitUntil(() =>
      document
        .querySelector('[data-test-card-url-bar-realm-info]')
        ?.textContent?.includes('Operator Mode Workspace'),
    );
    assert
      .dom('[data-test-card-url-bar-input]')
      .hasValue(`${testRealmURL}person.gts`);
  });

  test(`card url bar URL does not react to external changes when user is editing`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/1`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').exists();
    assert.dom('[data-test-submode-switcher]').hasText('Interact');

    await click(
      '[data-test-submode-switcher] .submode-switcher-dropdown-trigger',
    );
    await click('[data-test-boxel-menu-item-text="Code"]');
    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').hasText('Code');
    await waitUntil(() =>
      document
        .querySelector('[data-test-card-url-bar-realm-info]')
        ?.textContent?.includes('Operator Mode Workspace'),
    );

    assert
      .dom('[data-test-card-url-bar-input]')
      .hasValue(`${testRealmURL}BlogPost/1.json`);

    let someRandomText = 'I am still typing a url';
    await typeIn('[data-test-card-url-bar-input]', someRandomText);

    let operatorModeStateService = this.owner.lookup(
      'service:operator-mode-state-service',
    ) as OperatorModeStateService;
    operatorModeStateService.updateCodePath(
      new URL(`${testRealmURL}person.gts`),
    );

    assert
      .dom('[data-test-card-url-bar-input]')
      .hasValue(`${testRealmURL}BlogPost/1.json${someRandomText}`);

    blur('[data-test-card-url-bar-input]');

    assert
      .dom('[data-test-card-url-bar-input]')
      .hasValue(`${testRealmURL}BlogPost/1.json${someRandomText}`);
  });

  test(`can open and close search sheet`, async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    await waitFor(`[data-test-cards-grid-item]`);

    await focus(`[data-test-search-field]`);
    assert.dom(`[data-test-search-sheet="search-prompt"]`).exists();

    await click(`[data-test-search-sheet] .search-sheet-content`);
    assert.dom(`[data-test-search-sheet="search-prompt"]`).exists();

    await typeIn(`[data-test-search-field]`, 'A');
    await click(
      `[data-test-search-sheet] .search-sheet-content .search-result-section`,
    );
    assert.dom(`[data-test-search-sheet="search-results"]`).exists();

    await click(
      `[data-test-search-sheet] .search-sheet-content .search-result-section`,
    );
    assert.dom(`[data-test-search-sheet="search-results"]`).exists();

    await click(`[data-test-operator-mode-stack]`);
    assert.dom(`[data-test-search-sheet="closed"]`).exists();
  });

  test<TestContextWithSave>('Choosing a new catalog entry card automatically saves the card with empty values before popping the card onto the stack in "edit" view', async function (assert) {
    assert.expect(5);
    await setCardInOperatorModeState(`${testRealmURL}grid`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    let savedCards = new Set<string>();
    this.onSave((url) => {
      savedCards.add(url.href);
    });
    await waitFor(`[data-test-stack-card="${testRealmURL}grid"]`);
    assert.dom(`[data-test-stack-card-index="0"]`).exists();

    await click('[data-test-create-new-card-button]');
    assert
      .dom('[data-test-card-catalog-modal] [data-test-boxel-header-title]')
      .containsText('Choose a Catalog Entry card');
    await waitFor(
      `[data-test-card-catalog-item="${testRealmURL}CatalogEntry/publishing-packet"]`,
    );
    assert.dom('[data-test-card-catalog-item]').exists({ count: 4 });

    await click(
      `[data-test-select="${testRealmURL}CatalogEntry/publishing-packet"]`,
    );
    await click('[data-test-card-catalog-go-button]');
    await waitFor('[data-test-stack-card-index="1"]');

    let paths = Array.from(savedCards).map(
      (url) => url.substring(testRealmURL.length) + '.json',
    );
    let fileRef = await testRealmAdapter.openFile(paths[0]);
    assert.deepEqual(
      JSON.parse(fileRef!.content as string),
      {
        data: {
          attributes: {
            description: null,
            socialBlurb: null,
            thumbnailURL: null,
            title: null,
          },
          meta: {
            adoptsFrom: {
              module: '../publishing-packet',
              name: 'PublishingPacket',
            },
          },
          relationships: {
            blogPost: {
              links: {
                self: null,
              },
            },
          },
          type: 'card',
        },
      },
      'file contents were saved correctly',
    );
    assert.dom('[data-test-last-saved]').doesNotExist();
  });

  test<TestContextWithSave>('Creating a new card from a linksTo field automatically saves the card with empty values before popping the card onto the stack in "edit" view', async function (assert) {
    assert.expect(5);
    await setCardInOperatorModeState(`${testRealmURL}Person/1`, 'edit');
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );
    let savedCards = new Set<string>();
    this.onSave((url) => {
      savedCards.add(url.href);
    });
    await waitFor(`[data-test-stack-card="${testRealmURL}Person/1"]`);
    await waitFor('[data-test-links-to-editor="pet"] [data-test-remove-card]');
    await click('[data-test-links-to-editor="pet"] [data-test-remove-card]');
    await waitFor('[data-test-add-new]');
    assert.dom('[data-test-add-new]').exists();
    assert
      .dom('[data-test-links-to-editor="pet"] [data-test-boxel-card-container]')
      .doesNotExist();
    await click('[data-test-add-new]');
    await waitFor(`[data-test-card-catalog-modal]`);
    await waitFor(`[data-test-card-catalog-create-new-button]`);
    await click(`[data-test-card-catalog-create-new-button]`);
    await waitFor('[data-test-stack-card-index="1"]');
    assert.dom(`[data-test-stack-card-index="1"]`).exists();
    let ids = Array.from(savedCards);
    let paths = ids.map((url) => url.substring(testRealmURL.length) + '.json');
    let path = paths.find((p) => p.includes('Pet/'));
    let id = ids.find((p) => p.includes('Pet/'));
    let fileRef = await testRealmAdapter.openFile(path!);
    assert.deepEqual(
      JSON.parse(fileRef!.content as string),
      {
        data: {
          attributes: {
            description: null,
            name: null,
            thumbnailURL: null,
          },
          meta: {
            adoptsFrom: {
              module: '../pet',
              name: 'Pet',
            },
          },
          type: 'card',
        },
      },
      'file contents were saved correctly',
    );
    assert
      .dom(`[data-test-stack-card="${id}"] [data-test-last-saved]`)
      .doesNotExist();
  });

  test<TestContextWithSave>('Clicking on "Finish Editing" after creating a card from linksTo field will switch the card into isolated mode', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}BlogPost/2`);
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-stack-card="${testRealmURL}BlogPost/2"]`);
    await click('[data-test-edit-button]');
    assert.dom('[data-test-add-new]').exists();
    await click('[data-test-add-new]');
    await waitFor(`[data-test-card-catalog-modal]`);
    await click(`[data-test-card-catalog-create-new-button]`);
    await waitFor('[data-test-stack-card-index="1"]');

    await click('[data-test-stack-card-index="1"] [data-test-edit-button]');

    await waitFor('[data-test-isolated-author]');
    assert.dom('[data-test-isolated-author]').exists();
  });

  test('displays card in interact mode when clicking `Open in Interact Mode` menu in preview panel', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}BlogPost/1"]`);

    await waitFor(`[data-test-stack-card="${testRealmURL}BlogPost/1"]`);
    await click(
      `[data-test-stack-card="${testRealmURL}BlogPost/1"] [data-test-edit-button]`,
    );

    await click(
      `[data-test-links-to-editor="authorBio"] [data-test-author="Alien"]`,
    );
    await waitFor(`[data-test-stack-card="${testRealmURL}Author/1"]`);

    assert.dom(`[data-test-stack-card]`).exists({ count: 3 });
    assert.dom(`[data-test-stack-card="${testRealmURL}grid"]`).exists();
    assert.dom(`[data-test-stack-card="${testRealmURL}BlogPost/1"]`).exists();
    assert.dom(`[data-test-stack-card="${testRealmURL}Author/1"]`).exists();

    await click(
      '[data-test-submode-switcher] .submode-switcher-dropdown-trigger',
    );
    await click('[data-test-boxel-menu-item-text="Code"]');
    await waitFor('[data-test-submode-switcher]');
    assert.dom('[data-test-submode-switcher]').hasText('Code');

    await fillIn(
      '[data-test-card-url-bar-input]',
      `${testRealmURL}Pet/mango.json`,
    );
    await triggerKeyEvent(
      '[data-test-card-url-bar-input]',
      'keypress',
      'Enter',
    );
    await blur('[data-test-card-url-bar-input]');
    assert
      .dom('[data-test-card-url-bar-realm-info]')
      .hasText('in Operator Mode Workspace');
    assert
      .dom('[data-test-card-url-bar-input]')
      .hasValue(`${testRealmURL}Pet/mango.json`);
    await click(`[data-test-more-options-button]`);
    await click(`[data-test-boxel-menu-item-text="Open in Interact Mode"]`);

    await waitFor(`[data-test-stack-card]`);
    assert.dom(`[data-test-stack-card]`).exists({ count: 1 });
    assert.dom(`[data-test-stack-card="${testRealmURL}Pet/mango"]`).exists();
  });

  test('can reorder linksToMany cards in edit view', async function (assert) {
    await setCardInOperatorModeState(`${testRealmURL}grid`);

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <OperatorMode @onClose={{noop}} />
          <CardPrerender />
        </template>
      },
    );

    await waitFor(`[data-test-cards-grid-item]`);
    await click(`[data-test-cards-grid-item="${testRealmURL}Person/burcu"]`);

    await waitFor(`[data-test-stack-card="${testRealmURL}Person/burcu"]`);
    assert.dom(`[data-test-plural-view-item]`).exists({ count: 3 });
    assert.dom(`[data-test-plural-view-item="0"]`).hasText('Jackie');
    assert.dom(`[data-test-plural-view-item="1"]`).hasText('Woody');
    assert.dom(`[data-test-plural-view-item="2"]`).hasText('Buzz');

    await click(
      `[data-test-stack-card="${testRealmURL}Person/burcu"] [data-test-edit-button]`,
    );

    assert.dom(`[data-test-item]`).exists({ count: 3 });
    assert.dom(`[data-test-item="0"]`).hasText('Jackie');
    assert.dom(`[data-test-item="1"]`).hasText('Woody');
    assert.dom(`[data-test-item="2"]`).hasText('Buzz');

    let dragAndDrop = async (itemSelector: string, targetSelector: string) => {
      let itemElement = document.querySelector(itemSelector);
      let targetElement = document.querySelector(targetSelector);

      if (!itemElement || !targetElement) {
        throw new Error('Item or target element not found');
      }

      let itemRect = itemElement.getBoundingClientRect();
      let targetRect = targetElement.getBoundingClientRect();

      await triggerEvent(itemElement, 'mousedown', {
        clientX: itemRect.left + itemRect.width / 2,
        clientY: itemRect.top + itemRect.height / 2,
      });

      await triggerEvent(document, 'mousemove', {
        clientX: itemRect.left + 1,
        clientY: itemRect.top + 1,
      });
      await triggerEvent(document, 'mousemove', {
        clientX: targetRect.left + targetRect.width / 2,
        clientY: targetRect.top - 100,
      });

      await triggerEvent(itemElement, 'mouseup', {
        clientX: targetRect.left + targetRect.width / 2,
        clientY: targetRect.top - 100,
      });
    };

    await dragAndDrop('[data-test-sort="1"]', '[data-test-sort="0"]');
    await dragAndDrop('[data-test-sort="2"]', '[data-test-sort="1"]');
    assert.dom(`[data-test-item]`).exists({ count: 3 });
    assert.dom(`[data-test-item="0"]`).hasText('Woody');
    assert.dom(`[data-test-item="1"]`).hasText('Buzz');
    assert.dom(`[data-test-item="2"]`).hasText('Jackie');

    let itemElement = document.querySelector('[data-test-item="0"]');
    let overlayButtonElements = document.querySelectorAll(
      `[data-test-overlay-card="${testRealmURL}Pet/woody"]`,
    );
    if (
      !itemElement ||
      !overlayButtonElements ||
      overlayButtonElements.length === 0
    ) {
      throw new Error('Item or overlay button element not found');
    }

    let itemRect = itemElement.getBoundingClientRect();
    let overlayButtonRect =
      overlayButtonElements[
        overlayButtonElements.length - 1
      ].getBoundingClientRect();

    assert.strictEqual(
      Math.round(itemRect.top),
      Math.round(overlayButtonRect.top),
    );
    assert.strictEqual(
      Math.round(itemRect.left),
      Math.round(overlayButtonRect.left),
    );

    await click(
      `[data-test-stack-card="${testRealmURL}Person/burcu"] [data-test-edit-button]`,
    );
    assert.dom(`[data-test-plural-view-item="0"]`).hasText('Woody');
    assert.dom(`[data-test-plural-view-item="1"]`).hasText('Buzz');
    assert.dom(`[data-test-plural-view-item="2"]`).hasText('Jackie');
  });
});
