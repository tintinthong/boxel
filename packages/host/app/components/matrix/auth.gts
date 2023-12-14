import { action } from '@ember/object';
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';

import Login from './login';
import RegisterUser from './register-user';

export default class Auth extends Component {
  <template>
    <div class='auth'>
      <div class='container'>
        {{#if this.isRegistrationMode}}
          <RegisterUser @onCancel={{this.toggleRegistrationMode}} />
        {{else}}
          <Login @onRegistration={{this.toggleRegistrationMode}} />
        {{/if}}
      </div>
    </div>

    <style>
      .auth {
        height: 100%;
        overflow: auto;
      }

      .container {
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: center;
        min-height: 100%;
        padding: var(--boxel-sp-lg);
      }
    </style>
  </template>

  @tracked isRegistrationMode = false;

  @action
  toggleRegistrationMode() {
    this.isRegistrationMode = !this.isRegistrationMode;
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Login {
    'Matrix::Login': typeof Login;
  }
}
