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
  @field title = contains(StringField);
  @field description = contains(StringField);
  @field price = contains(MonetaryAmountField);
  @field compareAtPrice = contains(MonetaryAmountField);
  @field unitPrice = contains(MonetaryAmountField);
  @field profit = contains(MonetaryAmountField);
  @field margin = contains(NumberField);
  static displayName = 'Item Card';

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

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='item-card'>
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
          <FieldContainer @tag='label' @label='Price' data-test-field='price'>
            <@fields.price />
          </FieldContainer>
          <FieldContainer
            @tag='label'
            @label='Compare At Price'
            data-test-field='compareAtPrice'
          >
            <@fields.compareAtPrice />
          </FieldContainer>
          <FieldContainer
            @tag='label'
            @label='Price Per Item'
            data-test-field='unitPrice'
          >
            <@fields.unitPrice />
          </FieldContainer>
          <FieldContainer
            @tag='label'
            @label='Profit'
            data-test-field='profit'
          >
            <@fields.profit />
          </FieldContainer>
          <FieldContainer
            @tag='label'
            @label='Margin'
            data-test-field='margin'
          >
            <@fields.margin />%
          </FieldContainer>
        </ItemCardContainer>
      </div>
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
