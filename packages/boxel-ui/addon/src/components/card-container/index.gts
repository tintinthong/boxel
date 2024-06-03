import type { TemplateOnlyComponent } from '@ember/component/template-only';

import cn from '../../helpers/cn.ts';
import element from '../../helpers/element.ts';
import { bool, or } from '../../helpers/truth-helpers.ts';
import Header from '../header/index.gts';
import cssVar from '../../helpers/css-var.ts';

interface Signature {
  Args: {
    backgroundColor?: string;
    displayBoundaries?: boolean;
    isHighlighted?: boolean;
    label?: string;
    tag?: keyof HTMLElementTagNameMap;
    title?: string;
  };
  Blocks: {
    default: [];
    header: [];
  };
  Element: HTMLElement;
}

const CardContainer: TemplateOnlyComponent<Signature> = <template>
  {{#let (element @tag) as |Tag|}}
    <Tag
      class={{cn
        'boxel-card-container'
        backgroundColor=@backgroundColor
        highlighted=@isHighlighted
        boundaries=@displayBoundaries
      }}
      style={{cssVar
        bg-color=(if @backgroundColor @backgroundColor 'transparent')
      }}
      data-test-boxel-card-container
      ...attributes
    >
      {{#if (or (has-block 'header') (bool @label) (bool @title))}}
        <Header @label={{@label}} @title={{@title}}>
          {{yield to='header'}}
        </Header>
      {{/if}}

      {{yield}}
    </Tag>
  {{/let}}
  <style>
    .boxel-card-container {
      position: relative;
      border-radius: var(--boxel-border-radius);
      transition:
        max-width var(--boxel-transition),
        box-shadow var(--boxel-transition);
    }
    .backgroundColor {
      background-color: var(--bg-color);
    }
    .boundaries {
      box-shadow: 0 0 0 1px var(--boxel-light-500);
    }
    .highlighted {
      box-shadow: 0 0 0 2px var(--boxel-highlight);
    }
  </style>
</template>;

export default CardContainer;
