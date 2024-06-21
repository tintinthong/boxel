import { fn } from '@ember/helper';
import { action } from '@ember/object';
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';

import { restartableTask, timeout } from 'ember-concurrency';

import FreestyleUsage from 'ember-freestyle/components/freestyle/usage';

import AiAssistantChatInput from './index';

export default class AiAssistantChatInputUsage extends Component {
  @tracked value = '';
  @tracked canSend = true;

  @action onSend(message: string) {
    console.log(`message sent: ${message}`);
    this.mockSend.perform();
  }

  mockSend = restartableTask(async () => {
    await timeout(2000);
  });

  <template>
    <FreestyleUsage @name='AiAssistant::ChatInput'>
      <:description>
        Chat input field for AI Assistant is a 'BoxelInput' component of type
        'textarea' with a send button. This component accepts all arguments that
        are accepted by 'BoxelInput' component in addition to an 'onSend'
        argument for action to take when message is submitted. A message can be
        submitted via pressing the 'Enter' key or by clicking on the send
        button.
      </:description>
      <:example>
        <AiAssistantChatInput
          @value={{this.value}}
          @onInput={{fn (mut this.value)}}
          @onSend={{this.onSend}}
          @canSend={{this.canSend}}
        />
      </:example>
      <:api as |Args|>
        <Args.String
          @name='value'
          @description='Chat input field'
          @onInput={{fn (mut this.value)}}
          @value={{this.value}}
        />
        <Args.Action
          @name='onInput'
          @description='Action to be called when input is entered'
        />
        <Args.Action
          @name='onSend'
          @description='Action to be called when "cmd+Enter" or "ctrl+Enter" keys are pressed or send button is clicked'
          @value={{this.onSend}}
        />
        <Args.Bool
          @name='canSend'
          @description='A boolean indicating whether the message can be sent'
          @onInput={{fn (mut this.canSend)}}
          @value={{this.canSend}}
        />
      </:api>
    </FreestyleUsage>
  </template>
}
