import { on } from '@ember/modifier';
import { action } from '@ember/object';
import Component from '@glimmer/component';

import onKeyMod from 'ember-keyboard/modifiers/on-key';

import { BoxelInput, IconButton } from '@cardstack/boxel-ui/components';
import { not } from '@cardstack/boxel-ui/helpers';
import { Send } from '@cardstack/boxel-ui/icons';
import { setCssVar } from '@cardstack/boxel-ui/modifiers';

interface Signature {
  Element: HTMLDivElement;
  Args: {
    value: string;
    onInput: (val: string) => void;
    onSend: (val: string) => void;
    canSend: boolean;
  };
}

export default class AiAssistantChatInput extends Component<Signature> {
  <template>
    <div class='chat-input-container'>
      <label for='ai-chat-input' class='boxel-sr-only'>
        Enter text to chat with AI Assistant
      </label>
      <BoxelInput
        class='chat-input'
        @id='ai-chat-input'
        @type='textarea'
        @value={{@value}}
        @onInput={{@onInput}}
        @placeholder='Enter a prompt'
        {{onKeyMod 'Shift+Enter' this.insertNewLine}}
        {{onKeyMod 'Enter' this.onSend}}
        {{setCssVar chat-input-height=this.height}}
        ...attributes
      />
      <IconButton
        {{on 'click' this.onSend}}
        {{! TODO we should visually surface this loading state }}
        disabled={{not @canSend}}
        data-test-can-send-msg={{@canSend}}
        class='send-button'
        @icon={{Send}}
        @height='20'
        @width='25'
        aria-label='Send'
        data-test-send-message-btn
      />
    </div>
    <style>
      .chat-input-container {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: var(--boxel-sp-xxs);
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xxs) var(--boxel-sp-xxs)
          var(--boxel-sp-xs);
        background-color: var(--boxel-light);
      }
      .chat-input {
        height: var(--chat-input-height);
        min-height: var(--chat-input-height);
        border-color: transparent;
        font-weight: 500;
        padding: var(--boxel-sp-4xs);
        resize: none;
        outline: 0;
      }
      .chat-input::placeholder {
        color: var(--boxel-400);
      }
      .chat-input:hover:not(:disabled) {
        border-color: transparent;
      }
      .send-button {
        width: var(--boxel-icon-med);
        height: var(--boxel-icon-med);
        background-color: var(--boxel-highlight);
        border-radius: var(--boxel-border-radius-sm);
        align-self: flex-end;
      }
      .send-button:hover:not(:disabled),
      .send-button:focus:not(:disabled) {
        background-color: var(--boxel-highlight-hover);
      }
      .send-button:disabled {
        --icon-color: var(--boxel-450);
        background-color: var(--boxel-300);
        pointer-events: none;
      }
      .send-button :deep(svg) {
        padding-top: var(--boxel-sp-5xs);
      }
    </style>
  </template>

  @action onSend(ev: Event) {
    ev.preventDefault();
    if ('shiftKey' in ev && ev.shiftKey) {
      return;
    }
    if (!this.args.canSend) {
      return;
    }
    this.args.onSend(this.args.value);
  }

  @action insertNewLine() {
    this.args.onInput(`${this.args.value}\n\n`);
  }

  get height() {
    const lineHeight = 20;
    const padding = 8;

    let lineCount = (this.args.value.match(/\n/g) ?? []).length + 1;
    let count = 1;

    if (lineCount > 5) {
      count = 5;
    } else if (lineCount > 1) {
      count = lineCount;
    }

    let height = count * lineHeight + 2 * padding;
    return `${height}px`;
  }
}
