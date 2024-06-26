import type { TemplateOnlyComponent } from '@ember/component/template-only';

import { element, cn } from '@cardstack/boxel-ui/helpers';

export interface PillSignature {
  Args: {
    inert?: boolean;
  };
  Blocks: {
    default: [];
    icon: [];
  };
  Element: HTMLButtonElement | HTMLDivElement;
}

const Pill: TemplateOnlyComponent<PillSignature> = <template>
  {{#let (element (if @inert 'div' 'button')) as |Tag|}}
    <Tag class={{cn 'pill' inert=@inert}} ...attributes>
      <figure class='icon'>
        {{yield to='icon'}}
      </figure>
      {{yield}}
    </Tag>
  {{/let}}

  <style>
    .pill {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      padding: var(--boxel-sp-5xs) var(--boxel-sp-xxxs) var(--boxel-sp-5xs)
        var(--boxel-sp-5xs);
      background-color: var(--boxel-light);
      border: 1px solid var(--boxel-400);
      border-radius: var(--boxel-border-radius-sm);
      font: 700 var(--boxel-font-sm);
      letter-spacing: var(--boxel-lsp-xs);
    }

    .inert {
      border: 0;
      background-color: var(--boxel-100);
      color: inherit;
    }

    .pill:not(.inert):hover {
      background-color: var(--boxel-100);
    }

    .icon {
      display: flex;
      margin-block: 0;
      margin-inline: 0;
    }

    .icon > :deep(*) {
      height: var(--pill-icon-size, 1.25rem);
    }
  </style>
</template>;

export default Pill;
