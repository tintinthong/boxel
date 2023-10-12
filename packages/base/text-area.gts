import { Component } from './card-api';
import StringField from './string';
import BoxelInput from '@cardstack/boxel-ui/components/input';

export default class TextAreaCard extends StringField {
  static displayName = 'TextArea';
  static edit = class Edit extends Component<typeof this> {
    <template>
      <BoxelInput
        class='boxel-text-area'
        @value={{@model}}
        @onInput={{@set}}
        @multiline={{true}}
      />
    </template>
  };
}
