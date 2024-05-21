import MarkdownField from 'https://cardstack.com/base/markdown';
import BooleanField from 'https://cardstack.com/base/boolean';
import NumberField from 'https://cardstack.com/base/number';
import {
  CardDef,
  field,
  linksTo,
  contains,
  containsMany,
  StringField,
  FieldsTypeFor,
} from 'https://cardstack.com/base/card-api';
import { Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import TextAreaCard from 'https://cardstack.com/base/text-area';
export class Product extends CardDef {
  static displayName = 'Product';
  @field title = contains(StringCard);
  @field description = contains(TextAreaCard);

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='container'>
        <h1><@fields.title /></h1>
        <p><@fields.description /></p>
      </div>
      <style>
        .container {
          padding: var(--boxel-sp-xl);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <em><@fields.title /></em>
    </template>
  };

  /*
  static atom = class Atom extends Component<typeof this> {
    <template></template>
  }

  static edit = class Edit extends Component<typeof this> {
    <template></template>
  }




  */
}
