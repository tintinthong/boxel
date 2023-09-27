import type { Signature } from './types.ts';
import type { TemplateOnlyComponent } from '@ember/component/template-only';

const IconComponent: TemplateOnlyComponent<Signature> = <template>
  <svg
    height='17.5'
    viewBox='0 0 17.5 17.5'
    width='17.5'
    xmlns='http://www.w3.org/2000/svg'
    ...attributes
  ><g
      stroke-linecap='round'
      stroke-linejoin='round'
      stroke-width='1.5'
      transform='translate(.75 .75)'
    ><circle
        cx='8'
        cy='8'
        fill='var(--icon-bg, none)'
        r='8'
        stroke='var(--icon-border, #000)'
      /><g
        fill='none'
        stroke='var(--icon-color, #000)'
        transform='translate(-4 -4)'
      ><path d='m12 8v8' /><path d='m8 12h8' /></g></g></svg>
</template>;

export default IconComponent;
