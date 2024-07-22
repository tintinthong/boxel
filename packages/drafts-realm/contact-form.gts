import { UserName } from './user-name';
import { UserEmail } from './user-email';
import { AddressInfo } from './address-info';
import {
  CardDef,
  field,
  contains,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import { Component } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { FieldContainer, CardContainer } from '@cardstack/boxel-ui/components';
import { MatrixUser } from './matrix-user';

class Isolated extends Component<typeof ContactForm> {
  <template>
    <div class='decorative-header'></div>

    <CardContainer @displayBoundaries={{false}} class='container'>
      <div class='card-form-display'>
        <div class='contact-form-details'>

          <div class='field-input'>
            <label>User: </label>
            <@fields.user />
          </div>

          <div class='field-input'>
            <label>Account Name: </label>
            <@fields.accountName />
          </div>

          <div class='field-input'>
            <label>Email: </label>
            <@fields.email />
          </div>

          <div class='field-input'>
            <label>Phone: </label>
            <@fields.phone />
          </div>

          <div class='field-input'>
            <label>Fax: </label>
            <@fields.fax />
          </div>

          <div class='field-input'>
            <label>Department: </label>
            <@fields.department />
          </div>

          <div class='field-input'>
            <label>AddressInfo: </label>
            <@fields.addressInfo />
          </div>

          <div class='field-input'>
            <label>Contact Owner: </label>
            <@fields.owner />
          </div>

        </div>

      </div>

    </CardContainer>

    <style>
      h2 {
        font-size: 2.2rem;
        margin: 0;
      }
      .container {
        width: 100%;
        padding: 1rem;
        display: grid;
        margin: auto;
        gap: var(--boxel-sp-lg);
      }
      .card-form-display {
        position: relative;
      }
      .icon-profile {
        position: absolute;
        top: 1px;
        right: 1px;
        width: 50px;
        height: 50px;
      }
      .contact-form-details {
        border: 1px solid var(--boxel-300);
        border-radius: var(--boxel-border-radius-xl);
        background-color: #eeeeee50;
        display: grid;
        grid-template-columns: 1fr;
        gap: var(--boxel-sp);
        justify-content: center;
        text-align: center;
        padding: 2.5rem 2rem;
        max-width: 800px;
        margin: auto;
      }

      .field-input {
        display: flex;
        gap: var(--boxel-sp-sm);
        font-size: 1rem;
        flex-wrap: wrap;
        min-width: 280px;
      }
      .field-input > label {
        font-weight: 700;
      }
      .decorative-header {
        background-image: url(https://i.imgur.com/PQuDAEo.jpg);
        height: var(--boxel-sp-xl);
        grid-column: 1 / span 2;
        margin-bottom: var(--boxel-sp);
      }
      h2 {
        margin-block-start: 0px;
        margin-block-end: 0px;
        margin: 0px;
        text-align: center;
      }
      @media (min-width: 767px) {
        .contact-form-details {
          gap: var(--boxel-sp-lg);
        }
        .field-input {
          display: flex;
          gap: var(--boxel-sp);
          font-size: 1rem;
          flex-wrap: wrap;
          min-width: 280px;
        }
      }
    </style>
  </template>
}

class View extends Component<typeof ContactForm> {
  <template>
    <div class='container'>
      <div class='field-input-group'>
        <FieldContainer @tag='label' @label='User' @vertical={{true}}>
          <@fields.user />
        </FieldContainer>

        <FieldContainer @tag='label' @label='Account Name' @vertical={{true}}>
          <@fields.accountName />
        </FieldContainer>

        <FieldContainer @tag='label' @label='Email' @vertical={{true}}>
          <@fields.email />
        </FieldContainer>

        <FieldContainer @tag='label' @label='Phone' @vertical={{true}}>
          <@fields.phone />
        </FieldContainer>

        <FieldContainer @tag='label' @label='Fax' @vertical={{true}}>
          <@fields.fax />
        </FieldContainer>

        <FieldContainer @tag='label' @label='Department' @vertical={{true}}>
          <@fields.department />
        </FieldContainer>

        <FieldContainer @tag='label' @label='Address Info' @vertical={{true}}>
          <@fields.addressInfo />
        </FieldContainer>
        {{! TODO: If this @model.owner check doesn't exist, we get Encountered error rendering HTML for card: Cannot read properties of null (reading 'title') }}
        {{! This applies to the embedded template }}
        {{! This also occurs during indexing }}
        {{#if @model.owner}}
          <FieldContainer
            @tag='label'
            @label='Contact Owner'
            @vertical={{true}}
          >
            <@fields.owner />
          </FieldContainer>
        {{/if}}

      </div>
    </div>

    <style>
      .container {
        display: grid;
        gap: var(--boxel-sp-lg);
        overflow: hidden;
      }
      .content {
        color: var(--boxel-700);
      }
      h2 {
        margin: 0px;
      }
      .field-input-group {
        overflow: overlay;
        display: flex;
        flex-direction: column;
        justify-content: space-evenly;
        gap: var(--boxel-sp);
      }
    </style>
  </template>
}

class Edit extends Component<typeof ContactForm> {
  <template>
    <CardContainer @displayBoundaries={{true}} class='container'>
      <FieldContainer
        @tag='label'
        @label='Title'
        @vertical={{true}}
      ><@fields.title /></FieldContainer>

      <FieldContainer @tag='label' @label='User' @vertical={{true}}>
        <@fields.user />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Account Name' @vertical={{true}}>
        <@fields.accountName />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Email' @vertical={{true}}>
        <@fields.email />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Phone' @vertical={{true}}>
        <@fields.phone />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Fax' @vertical={{true}}>
        <@fields.fax />
      </FieldContainer>

      <FieldContainer
        @tag='label'
        @label='Department'
        @vertical={{true}}
      ><@fields.department /></FieldContainer>

      <FieldContainer @tag='label' @label='Address Info' @vertical={{true}}>
        <@fields.addressInfo />
      </FieldContainer>
    </CardContainer>

    <style>
      .container {
        padding: var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp);
      }
    </style>
  </template>
}

export class ContactForm extends CardDef {
  @field title = contains(StringField, {
    computeVia: function (this: ContactForm) {
      const { salutation, firstName, lastName } = this.user;

      if (!salutation || !firstName || !lastName) return 'User Not Found';
      return `${salutation} ${firstName} ${lastName}`;
    },
  });
  @field user = contains(UserName, {
    description: `User's Full Name`,
  });
  @field accountName = contains(StringField, {
    description: `User's Account Name`,
  });
  @field email = contains(UserEmail, {
    description: `User's Email`,
  });
  @field phone = contains(StringField, {
    description: `User's phone number`,
  });
  @field fax = contains(StringField, {
    description: `User's Fax Number`,
  });
  @field department = contains(StringField, {
    description: `User's Department`,
  });
  @field addressInfo = contains(AddressInfo, {
    description: `User's AddressInfo`,
  });
  @field owner = linksTo(MatrixUser, {
    description: `Owner`,
  });

  static displayName = 'Contact Form';
  static isolated = Isolated;
  static embedded = View;
  static atom = View;
  static edit = Edit;
}
