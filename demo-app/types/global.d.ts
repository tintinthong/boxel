import '@glint/environment-ember-loose';
import '@cardstack/boxel-motion/glint';

import { HelperLike } from '@glint/template';
import EqHelper from 'ember-truth-helpers/helpers/eq';
import AndHelper from 'ember-truth-helpers/helpers/and';
import OrHelper from 'ember-truth-helpers/helpers/or';
import NotHelper from 'ember-truth-helpers/helpers/not';
import PickHelper from 'ember-composable-helpers/helpers/pick';

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    eq: typeof EqHelper;
    and: typeof AndHelper;
    or: typeof OrHelper;
    not: typeof NotHelper;
    pick: typeof PickHelper;
    'page-title': HelperLike<{
      Args: { Positional: [title: string] };
      Return: void;
    }>;
    'on-key': HelperLike<{
      Args: {
        Positional: [keyCombo: string, callback: () => void];
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        Named: { event: any };
      };
      Return: void;
    }>;
  }
}
