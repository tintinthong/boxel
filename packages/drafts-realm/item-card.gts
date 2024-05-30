import {
  CardDef,
  field,
  contains,
  StringField,
  Component,
} from 'https://cardstack.com/base/card-api';

import { FieldContainer } from '@cardstack/boxel-ui/components';
import GlimmerComponent from '@glimmer/component';

export class ItemCard extends CardDef {
  @field title = contains(StringField);
  @field description = contains(StringField);
  static displayName = 'Item Card';

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <ItemCardContainer>
        <h2><@fields.title /></h2>
        <@fields.description />
      </ItemCardContainer>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <ItemCardContainer>
        <@fields.title />
      </ItemCardContainer>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <ItemCardContainer>
        <@fields.title />
      </ItemCardContainer>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      <ItemCardContainer>
        <FieldContainer @tag='label' @label='Title' data-test-field='title'>
          <@fields.title />
        </FieldContainer>
        <FieldContainer
          @tag='label'
          @label='Description'
          data-test-field='description'
        >
          <@fields.description />
        </FieldContainer>
      </ItemCardContainer>
    </template>
  };
}

interface Signature {
  Element: HTMLElement;
  Blocks: {
    default: [];
  };
}

class ItemCardContainer extends GlimmerComponent<Signature> {
  <template>
    <div class='entry' ...attributes>
      {{yield}}
    </div>
    <style>
      .entry {
        display: grid;
        gap: 3px;
        font: var(--boxel-font-sm);
      }
    </style>
  </template>
}
