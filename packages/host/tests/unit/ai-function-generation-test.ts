import { RenderingTestContext } from '@ember/test-helpers';

import { setupRenderingTest } from 'ember-qunit';

import { module, test } from 'qunit';

import { baseRealm } from '@cardstack/runtime-common';
import {
  generateCardPatchCallSpecification,
  basicMappings,
  type RelationshipSchema,
  type RelationshipsSchema,
  type ObjectSchema,
} from '@cardstack/runtime-common/helpers/ai';
import { Loader } from '@cardstack/runtime-common/loader';

import type LoaderService from '@cardstack/host/services/loader-service';

import { primitive as primitiveType } from 'https://cardstack.com/base/card-api';

import {
  setupLocalIndexing,
  setupServerSentEvents,
  setupOnSave,
  setupCardLogs,
} from '../helpers';

let cardApi: typeof import('https://cardstack.com/base/card-api');
let string: typeof import('https://cardstack.com/base/string');
let number: typeof import('https://cardstack.com/base/number');
let biginteger: typeof import('https://cardstack.com/base/big-integer');
let date: typeof import('https://cardstack.com/base/date');
let datetime: typeof import('https://cardstack.com/base/datetime');
let boolean: typeof import('https://cardstack.com/base/boolean');
let primitive: typeof primitiveType;
let mappings: Map<typeof cardApi.FieldDef, any>;

let loader: Loader;

module('Unit | ai-function-generation-test', function (hooks) {
  setupRenderingTest(hooks);
  hooks.beforeEach(function (this: RenderingTestContext) {
    loader = (this.owner.lookup('service:loader-service') as LoaderService)
      .loader;
  });
  hooks.beforeEach(async function () {
    cardApi = await loader.import(`${baseRealm.url}card-api`);
    primitive = cardApi.primitive;
    string = await loader.import(`${baseRealm.url}string`);
    number = await loader.import(`${baseRealm.url}number`);
    biginteger = await loader.import(`${baseRealm.url}big-integer`);
    date = await loader.import(`${baseRealm.url}date`);
    datetime = await loader.import(`${baseRealm.url}datetime`);
    boolean = await loader.import(`${baseRealm.url}boolean`);
    mappings = await basicMappings(loader);
  });

  setupLocalIndexing(hooks);
  setupOnSave(hooks);
  setupCardLogs(
    hooks,
    async () => await loader.import(`${baseRealm.url}card-api`),
  );
  setupServerSentEvents(hooks);

  test(`generates a simple compliant schema for basic types`, async function (assert) {
    let { field, contains, CardDef } = cardApi;
    let { default: StringField } = string;
    let { default: NumberField } = number;
    let { default: BooleanField } = boolean;
    let { default: DateField } = date;
    let { default: DateTimeField } = datetime;
    let { default: BigIntegerField } = biginteger;
    class BasicCard extends CardDef {
      @field stringField = contains(StringField);
      @field numberField = contains(NumberField);
      @field booleanField = contains(BooleanField);
      @field dateField = contains(DateField);
      @field dateTimeField = contains(DateTimeField);
      @field bigIntegerField = contains(BigIntegerField);
    }

    let schema = generateCardPatchCallSpecification(
      BasicCard,
      cardApi,
      mappings,
    );
    assert.deepEqual(schema, {
      attributes: {
        type: 'object',
        properties: {
          thumbnailURL: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          stringField: { type: 'string' },
          numberField: { type: 'number' },
          booleanField: { type: 'boolean' },
          dateField: { type: 'string', format: 'date' },
          dateTimeField: { type: 'string', format: 'date-time' },
          bigIntegerField: { type: 'string', pattern: '^-?[0-9]+$' },
        },
      },
    });
  });

  test(`generates a simple compliant schema for nested types`, async function (assert) {
    let { field, contains, CardDef, FieldDef } = cardApi;
    let { default: StringField } = string;

    class InternalField extends FieldDef {
      @field innerStringField = contains(StringField);
    }
    class BasicCard extends CardDef {
      @field containerField = contains(InternalField);
    }

    let schema = generateCardPatchCallSpecification(
      BasicCard,
      cardApi,
      mappings,
    );
    assert.deepEqual(schema, {
      attributes: {
        type: 'object',
        properties: {
          thumbnailURL: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          containerField: {
            type: 'object',
            properties: {
              innerStringField: { type: 'string' },
            },
          },
        },
      },
    });
  });

  test(`should support contains many`, async function (assert) {
    let { field, contains, containsMany, CardDef, FieldDef } = cardApi;
    let { default: StringField } = string;

    class InternalField extends FieldDef {
      @field innerStringField = containsMany(StringField);
    }
    class TestCard extends CardDef {
      @field containerField = contains(InternalField);
    }

    let schema = generateCardPatchCallSpecification(
      TestCard,
      cardApi,
      mappings,
    );
    assert.deepEqual(schema, {
      attributes: {
        type: 'object',
        properties: {
          thumbnailURL: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          containerField: {
            type: 'object',
            properties: {
              innerStringField: { type: 'array', items: { type: 'string' } },
            },
          },
        },
      },
    });
  });

  test(`should support linksTo`, async function (assert) {
    let { field, contains, linksTo, CardDef } = cardApi;
    let { default: StringField } = string;
    class OtherCard extends CardDef {
      @field innerStringField = contains(StringField);
    }

    class TestCard extends CardDef {
      static displayName = 'TestCard';
      @field linkedCard = linksTo(OtherCard);
      @field simpleField = contains(StringField);
      @field linkedCard2 = linksTo(OtherCard);
    }

    let schema = generateCardPatchCallSpecification(
      TestCard,
      cardApi,
      mappings,
    );

    let attributes: ObjectSchema = {
      type: 'object',
      properties: {
        simpleField: { type: 'string' },
        title: { type: 'string' },
        description: { type: 'string' },
        thumbnailURL: { type: 'string' },
      },
    };
    let linkedRelationship: RelationshipSchema = {
      type: 'object',
      properties: {
        links: {
          type: 'object',
          properties: {
            self: { type: 'string' },
          },
          required: ['self'],
        },
      },
      required: ['links'],
    };
    let relationships: RelationshipsSchema = {
      type: 'object',
      properties: {
        linkedCard: linkedRelationship,
        linkedCard2: linkedRelationship,
      },
      required: ['linkedCard', 'linkedCard2'],
    };
    assert.deepEqual(schema, { attributes, relationships });
  });

  test(`should support linksToMany`, async function (assert) {
    let { field, contains, linksToMany, CardDef } = cardApi;
    let { default: StringField } = string;
    class OtherCard extends CardDef {
      @field innerStringField = contains(StringField);
    }
    class TestCard extends CardDef {
      static displayName = 'TestCard';
      @field simpleField = contains(StringField);
      @field linkedCards = linksToMany(OtherCard);
    }

    let schema = generateCardPatchCallSpecification(
      TestCard,
      cardApi,
      mappings,
    );

    let attributes: ObjectSchema = {
      type: 'object',
      properties: {
        simpleField: { type: 'string' },
        title: { type: 'string' },
        description: { type: 'string' },
        thumbnailURL: { type: 'string' },
      },
    };
    let linksToManyRelationship: RelationshipSchema = {
      type: 'object',
      properties: {
        links: {
          type: 'object',
          properties: {
            self: { type: 'string' },
          },
          required: ['self'],
        },
      },
      required: ['links'],
    };
    let relationships: RelationshipsSchema = {
      type: 'object',
      properties: {
        linkedCards: {
          type: 'array',
          items: linksToManyRelationship,
        },
      },
      required: ['linkedCards'],
    };
    assert.deepEqual(schema, { attributes, relationships });
  });

  test(`skips over fields that can't be recognised`, async function (assert) {
    let { field, contains, CardDef, FieldDef } = cardApi;
    let { default: StringField } = string;

    class NewField extends FieldDef {
      static displayName = 'NewField';
      static [primitive]: number;
    }

    class TestCard extends CardDef {
      static displayName = 'TestCard';
      @field keepField = contains(StringField);
      @field skipField = contains(NewField);
    }

    let schema = generateCardPatchCallSpecification(
      TestCard,
      cardApi,
      mappings,
    );
    assert.deepEqual(schema, {
      attributes: {
        type: 'object',
        properties: {
          thumbnailURL: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          keepField: { type: 'string' },
        },
      },
    });
  });

  test(`handles subclasses`, async function (assert) {
    let { field, contains, CardDef } = cardApi;
    let { default: StringField } = string;

    class NewField extends StringField {
      static displayName = 'NewField';
    }

    class TestCard extends CardDef {
      static displayName = 'TestCard';
      @field keepField = contains(NewField);
    }

    let schema = generateCardPatchCallSpecification(
      TestCard,
      cardApi,
      mappings,
    );
    assert.deepEqual(schema, {
      attributes: {
        type: 'object',
        properties: {
          thumbnailURL: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          keepField: { type: 'string' },
        },
      },
    });
  });

  test(`handles subclasses within nested fields`, async function (assert) {
    let { field, contains, containsMany, CardDef, FieldDef } = cardApi;
    let { default: StringField } = string;

    class NewField extends StringField {
      static displayName = 'NewField';
    }

    class ContainingField extends FieldDef {
      @field keepField = containsMany(NewField);
    }

    class TestCard extends CardDef {
      static displayName = 'TestCard';
      @field containingField = contains(ContainingField);
    }

    let schema = generateCardPatchCallSpecification(
      TestCard,
      cardApi,
      mappings,
    );

    assert.deepEqual(schema, {
      attributes: {
        type: 'object',
        properties: {
          thumbnailURL: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          containingField: {
            type: 'object',
            properties: {
              keepField: { type: 'array', items: { type: 'string' } },
            },
          },
        },
      },
    });
  });

  test(`supports descriptions on fields`, async function (assert) {
    let { field, contains, CardDef, FieldDef } = cardApi;
    let { default: StringField } = string;

    class InternalField extends FieldDef {
      @field innerStringField = contains(StringField);
    }
    class BasicCard extends CardDef {
      @field containerField = contains(InternalField, {
        description: 'Desc #1',
      });
    }

    let schema = generateCardPatchCallSpecification(
      BasicCard,
      cardApi,
      mappings,
    );
    assert.deepEqual(schema, {
      attributes: {
        type: 'object',
        properties: {
          thumbnailURL: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          containerField: {
            type: 'object',
            description: 'Desc #1',
            properties: {
              innerStringField: { type: 'string' },
            },
          },
        },
      },
    });
  });

  test(`supports descriptions on nested fields`, async function (assert) {
    let { field, contains, CardDef, FieldDef } = cardApi;
    let { default: StringField } = string;

    class InternalField extends FieldDef {
      @field innerStringField = contains(StringField, {
        description: 'Desc #2',
      });
    }
    class BasicCard extends CardDef {
      @field containerField = contains(InternalField, {
        description: 'Desc #1',
      });
    }

    let schema = generateCardPatchCallSpecification(
      BasicCard,
      cardApi,
      mappings,
    );
    assert.deepEqual(schema, {
      attributes: {
        type: 'object',
        properties: {
          thumbnailURL: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          containerField: {
            type: 'object',
            description: 'Desc #1',
            properties: {
              innerStringField: { type: 'string', description: 'Desc #2' },
            },
          },
        },
      },
    });
  });

  test(`supports descriptions in linksTo`, async function (assert) {
    let { field, contains, linksTo, CardDef } = cardApi;
    let { default: StringField } = string;
    class OtherCard extends CardDef {
      @field innerStringField = contains(StringField);
    }

    class TestCard extends CardDef {
      static displayName = 'TestCard';
      @field linkedCard = linksTo(OtherCard);
      @field simpleField = contains(StringField);
      @field linkedCard2 = linksTo(OtherCard, { description: 'linked card' });
    }

    let schema = generateCardPatchCallSpecification(
      TestCard,
      cardApi,
      mappings,
    );

    let attributes: ObjectSchema = {
      type: 'object',
      properties: {
        simpleField: { type: 'string' },
        title: { type: 'string' },
        description: { type: 'string' },
        thumbnailURL: { type: 'string' },
      },
    };
    let relationships: RelationshipsSchema = {
      type: 'object',
      properties: {
        linkedCard: {
          type: 'object',
          properties: {
            links: {
              type: 'object',
              properties: {
                self: { type: 'string' },
              },
              required: ['self'],
            },
          },
          required: ['links'],
        },
        linkedCard2: {
          type: 'object',
          description: 'linked card',
          properties: {
            links: {
              type: 'object',
              properties: {
                self: { type: 'string' },
              },
              required: ['self'],
            },
          },
          required: ['links'],
        },
      },
      required: ['linkedCard', 'linkedCard2'],
    };
    assert.deepEqual(schema, { attributes, relationships });
  });

  test(`supports descriptions in linksToMany`, async function (assert) {
    let { field, contains, linksToMany, CardDef } = cardApi;
    let { default: StringField } = string;
    class OtherCard extends CardDef {
      @field innerStringField = contains(StringField);
    }

    class TestCard extends CardDef {
      static displayName = 'TestCard';
      @field simpleField = contains(StringField);
      @field linkedCards = linksToMany(OtherCard, {
        description: 'linked cards',
      });
    }

    let schema = generateCardPatchCallSpecification(
      TestCard,
      cardApi,
      mappings,
    );

    let attributes: ObjectSchema = {
      type: 'object',
      properties: {
        simpleField: { type: 'string' },
        title: { type: 'string' },
        description: { type: 'string' },
        thumbnailURL: { type: 'string' },
      },
    };
    let relationships: RelationshipsSchema = {
      type: 'object',
      properties: {
        linkedCards: {
          type: 'array',
          description: 'linked cards',
          items: {
            type: 'object',
            properties: {
              links: {
                type: 'object',
                properties: {
                  self: { type: 'string' },
                },
                required: ['self'],
              },
            },
            required: ['links'],
          },
        },
      },
      required: ['linkedCards'],
    };
    assert.deepEqual(schema, { attributes, relationships });
  });

  test(`supports descriptions on containsMany fields`, async function (assert) {
    let { field, contains, containsMany, CardDef, FieldDef } = cardApi;
    let { default: StringField } = string;

    class InternalField extends FieldDef {
      @field innerStringField = contains(StringField);
    }
    class BasicCard extends CardDef {
      @field containerField = containsMany(InternalField, {
        description: 'Desc #1',
      });
    }

    let schema = generateCardPatchCallSpecification(
      BasicCard,
      cardApi,
      mappings,
    );
    assert.deepEqual(schema, {
      attributes: {
        type: 'object',
        properties: {
          thumbnailURL: { type: 'string' },
          title: { type: 'string' },
          description: { type: 'string' },
          containerField: {
            type: 'array',
            description: 'Desc #1',
            items: {
              type: 'object',
              properties: {
                innerStringField: { type: 'string' },
              },
            },
          },
        },
      },
    });
  });
});
