declare module 'ember-focus-trap/modifiers/focus-trap' {
  import type { FunctionBasedModifier } from 'ember-modifier';
  import type { Options } from 'focus-trap';

  const focusTrap: FunctionBasedModifier<{
    Args: {
      // https://ember-focus-trap.netlify.app/docs/arguments/
      Named: {
        focusTrapOptions?: Partial<Options>;
        isActive?: boolean;
        isPaused?: boolean;
        shouldSelfFocus?: boolean;
      };
      Positional: Record<string, never>;
    };
    Element: HTMLElement;
  }>;

  export default focusTrap;
}
