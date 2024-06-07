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
  MonetaryAmount,
} from './monetary-amount';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import GlimmerComponent from '@glimmer/component';

export function getProfit(price: MonetaryAmount, costPerItem: MonetaryAmount) {
  let calcProfit = Number(price) - Number(costPerItem);
  if (calcProfit > 0) {
    return calcProfit;
  }
  return 0;
}

export function getMargin(price: MonetaryAmount, theProfit: MonetaryAmount) {
  let calcMargin = (Number(theProfit) / Number(price)) * 100;
  if (calcMargin > 0) {
    return calcMargin;
  }
  return 0;
}

export class ItemCard extends CardDef {
  static displayName = 'Item Card';
  @field title = contains(StringField);
  @field description = contains(StringField);
  @field price = contains(MonetaryAmountField);
  @field compareAtPrice = contains(MonetaryAmountField);
  @field unitPrice = contains(MonetaryAmountField);
  //@field profit = contains(MonetaryAmountField);
  //@field margin = contains(NumberField);

  static isolated = class Isolated extends Component<typeof this> {
    get unitPrice() {
      return this.args.model.unitPrice;
    }

    get price() {
      return this.args.model.price;
    }

    get profit() {
      return getProfit(this.args.model.price, this.args.model.unitPrice);
    }

    get margin() {
      return getMargin(this.args.model.price, this.profit);
    }

    <template>
      <ItemCardContainer>
        <h2><@fields.title /></h2>
        <@fields.description /><br />
        Price
        <@fields.price /><br />
        Compare At Price
        <@fields.compareAtPrice /><br />
        Profit
        {{this.profit}}<br />
        Price per item
        <@fields.unitPrice /><br />
        {{this.margin}}%
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
