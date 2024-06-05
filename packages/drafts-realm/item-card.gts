import NumberField from 'https://cardstack.com/base/number';
import {
  CardDef,
  field,
  contains,
  StringField,
  BigIntField,
  Component,
} from 'https://cardstack.com/base/card-api';
import {
  MonetaryAmount as MonetaryAmountField,
  MonetaryAmountAtom,
} from './monetary-amount';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import GlimmerComponent from '@glimmer/component';

export class ItemCard extends CardDef {
  static displayName = 'Item Card';
  @field title = contains(StringField);
  @field description = contains(StringField);
  @field price = contains(MonetaryAmountField);
  @field compareAtPrice = contains(MonetaryAmountField);
  @field unitPrice = contains(MonetaryAmountField);
  @field profit = contains(MonetaryAmountField);
  @field margin = contains(NumberField);

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <ItemCardContainer>
        <h2><@attributes.title /></h2>
        <@attributes.description /><br />
        Price
        <@attributes.price /><br />
        Compare At Price
        <@attributes.compareAtPrice /><br />
        Profit
        <@attributes.profit /><br />
        Price per item
        <@attributes.unitPrice /><br />
        <@attributes.margin />%
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

}

interface Signature {
  Element: HTMLElement;
  Blocks: {
    default: [];
  };
}

class ItemCardContainer extends GlimmerComponent<Signature> {
  <template>
    <div class='item-card' ...attributes>
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
