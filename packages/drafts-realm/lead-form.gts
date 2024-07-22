import MarkdownField from 'https://cardstack.com/base/markdown';
import {
  CardDef,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import { UserName } from './user-name';
import { UserEmail } from './user-email';
import { AddressInfo } from './address-info';
import { Component } from 'https://cardstack.com/base/card-api';
import { CardContainer, FieldContainer } from '@cardstack/boxel-ui/components';
import { BoxelSelect } from '@cardstack/boxel-ui/components';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { BoxelInput } from '@cardstack/boxel-ui/components';
import { CurrencyAmount } from './currency-amount';
import { MatrixUser } from './matrix-user';
import { Company } from './crm/account';

interface CategorySignature {
  name: string;
}

class IsolatedSecForLeadForm extends Component<typeof LeadForm> {
  get getFormattedNoOfEmployees() {
    if (!this.args.model.noOfEmployees) return null;
    return Math.round(this.args.model.noOfEmployees);
  }

  <template>
    <CardContainer @displayBoundaries={{false}} class='container'>
      <section>
        <div class='field-group-title'>About</div>
        <div class='field-input-group'>
          <div class='field-input'>
            <label>User: </label>
            <@fields.user />
          </div>
          <div class='field-input'>
            <label>Company: </label>
            <@fields.company />
          </div>
          <div class='field-input'>
            <label>Website: </label>
            <@fields.website />
          </div>
          <div class='field-input'>
            <label>Lead Status: </label>
            <@fields.leadStatus />
          </div>
          <div class='field-input'>
            <label>Lead Owner: </label>
            <@fields.owner />
          </div>
          <div class='field-input-column description'>
            <label>Description: </label>
            <@fields.description />
          </div>
        </div>
      </section>

      <section>
        <div class='field-group-title'>Get In Touch</div>
        <div class='field-input-group'>
          <div class='field-input'>
            <label>Phone Number: </label>
            <@fields.phone />
          </div>
          <div class='field-input'>
            <label>Email: </label>
            <@fields.email />
          </div>
          <div class='field-input'>
            <label>Address Info: </label>
            <div class='address-info'>
              <@fields.addressInfo />
            </div>
          </div>
        </div>
      </section>

      <section>
        <div class='field-group-title'>Segment</div>
        <div class='field-input-group'>
          <div class='field-input'>
            <label>No. of Employees: </label>
            {{this.getFormattedNoOfEmployees}}
          </div>
          <div class='field-input'>
            <label>Annual Revenue: </label>
            <@fields.annualRevenue />
          </div>
          <div class='field-input'>
            <label>Lead Source: </label>
            <@fields.leadSource />
          </div>
          <div class='field-input'>
            <label>Industry: </label>
            <@fields.industry />
          </div>
        </div>
      </section>
    </CardContainer>

    <style>
      .container {
        padding: var(--boxel-sp-xl);
        display: grid;
        gap: var(--boxel-sp-lg);
        overflow: hidden;
      }
      section {
        overflow: overlay;
      }
      .description {
        text-align: justify;
      }
      .field-group-title {
        font-size: var(--boxel-font-size);
        font-weight: 800;
        margin-bottom: var(--boxel-sp-xs);
      }
      .field-input {
        display: flex;
        gap: var(--boxel-sp-sm);
        font-size: var(--boxel-font-size-sm);
        flex-wrap: wrap;
      }
      .field-input-group {
        display: flex;
        flex-direction: column;
        justify-content: space-evenly;
        gap: var(--boxel-sp);
        background-color: #fbfbfb;
        border: 1px solid var(--boxel-300);
        border-radius: var(--boxel-border-radius);
        padding: var(--boxel-sp);
      }
      .field-input-column {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        flex-wrap: wrap;
      }
      label {
        font-weight: 700;
      }
      .address-info {
        overflow: overlay;
      }
    </style>
  </template>
}

class ViewSecForLeadForm extends Component<typeof LeadForm> {
  <template>
    <CardContainer @displayBoundaries={{false}} class='container'>
      <section>
        <div class='field-group-title'>About</div>
        <div class='field-input-group'>
          <FieldContainer @tag='label' @label='User' @vertical={{true}}>
            <@fields.user />
          </FieldContainer>
          <FieldContainer @tag='label' @label='Company' @vertical={{true}}>
            <@fields.company />
          </FieldContainer>
          <FieldContainer @tag='label' @label='Website' @vertical={{true}}>
            <@fields.website />
          </FieldContainer>
          <FieldContainer @tag='label' @label='Description' @vertical={{true}}>
            <@fields.description />
          </FieldContainer>
          <FieldContainer @tag='label' @label='Lead Status' @vertical={{true}}>
            <@fields.leadStatus />
          </FieldContainer>
          <FieldContainer @tag='label' @label='Lead Owner' @vertical={{true}}>
            <@fields.owner />
          </FieldContainer>
        </div>
      </section>

      <section>
        <div class='field-group-title'>Get In Touch</div>
        <div class='field-input-group'>
          <FieldContainer @tag='label' @label='Phone' @vertical={{true}}>
            <@fields.phone />
          </FieldContainer>
          <FieldContainer @tag='label' @label='Email' @vertical={{true}}>
            <@fields.email />
          </FieldContainer>
          <FieldContainer @tag='label' @label='Address' @vertical={{true}}>
            <@fields.addressInfo />
          </FieldContainer>
        </div>
      </section>

      <section>
        <div class='field-group-title'>Segment</div>
        <div class='field-input-group'>
          <FieldContainer
            @tag='label'
            @label='No. of Employees'
            @vertical={{true}}
          >
            <@fields.noOfEmployees />
          </FieldContainer>
          <FieldContainer
            @tag='label'
            @label='Annual Revenue'
            @vertical={{true}}
          >
            <@fields.annualRevenue />
          </FieldContainer>
          <FieldContainer @tag='label' @label='Lead Source' @vertical={{true}}>
            <@fields.leadSource />
          </FieldContainer>
          <FieldContainer @tag='label' @label='Industry' @vertical={{true}}>
            <@fields.industry />
          </FieldContainer>
        </div>
      </section>
    </CardContainer>

    <style>
      .container {
        display: grid;
        gap: var(--boxel-sp-xl);
        overflow: hidden;
      }
      section {
        overflow: hidden;
      }
      .field-group-title {
        font-size: 1rem;
        font-weight: bold;
        margin-bottom: 0.75rem;
        text-decoration: underline;
        text-decoration-thickness: 3px;
        text-underline-offset: 3px;
        color: var(--boxel-dark-teal);
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

class EditSecFoLeadForm extends Component<typeof LeadForm> {
  /* Lead Status Options */
  get selectedLeadStatus() {
    return { name: this.args.model.leadStatus };
  }

  @tracked leadStatusOptions = [
    { name: 'New' },
    { name: 'Working' },
    { name: 'Nurturing' },
    { name: 'Unqualified' },
    { name: 'Qualified' },
  ] as Array<CategorySignature>;

  @action updateLeadStatus(type: { name: string }) {
    this.args.model.leadStatus = type.name;
  }

  /* No Of Employees */
  @action updateNoOfEmployees(val: number) {
    this.args.model.noOfEmployees = val;
  }

  get getFormattedNoOfEmployees() {
    if (!this.args.model.noOfEmployees) return null;
    return Math.round(this.args.model.noOfEmployees);
  }

  /* Lead Source Options */
  get selectedLeadSource() {
    return { name: this.args.model.leadSource };
  }

  @tracked leadSourceOptions = [
    { name: 'Advertisement' },
    { name: 'Employee Referral' },
    { name: 'External Referral' },
    { name: 'Partner' },
    { name: 'Public Relations' },
    { name: 'Seminar - Internal' },
    { name: 'Seminar - Partner' },
    { name: 'Trade Show' },
    { name: 'Web' },
    { name: 'Word of mouth' },
    { name: 'Other' },
  ] as Array<CategorySignature>;

  @action updateLeadSource(type: { name: string }) {
    this.args.model.leadSource = type.name;
  }

  /* Industry Options */
  get selectedIndustry() {
    return { name: this.args.model.industry };
  }

  @tracked industryOptions = [
    { name: 'Agriculture' },
    { name: 'Apparel' },
    { name: 'Banking' },
    { name: 'Biotechnology' },
    { name: 'Chemicals' },
    { name: 'Communications' },
    { name: 'Construction' },
    { name: 'Consulting' },
    { name: 'Education' },
    { name: 'Electronics' },
    { name: 'Energy' },
    { name: 'Engineering' },
    { name: 'Entertainment' },
    { name: 'Environmental' },
    { name: 'Finance' },
    { name: 'Food & Beverage' },
    { name: 'Government' },
    { name: 'Healthcare' },
    { name: 'Hospitality' },
    { name: 'Insurance' },
    { name: 'Machinery' },
    { name: 'Manufacturing' },
    { name: 'Media' },
    { name: 'Not For Profit' },
    { name: 'Recreation' },
    { name: 'Retail' },
    { name: 'Shipping' },
    { name: 'Technology' },
    { name: 'Telecommunications' },
    { name: 'Transportation' },
    { name: 'Utilities' },
    { name: 'Others' },
  ] as Array<CategorySignature>;

  @action updateIndustry(type: { name: string }) {
    this.args.model.industry = type.name;
  }

  <template>
    <CardContainer @displayBoundaries={{false}} class='container'>
      <FieldContainer @tag='label' @label='Title' @vertical={{true}}>
        <@fields.title />
      </FieldContainer>

      <FieldContainer @tag='label' @label='User' @vertical={{true}}>
        <@fields.user />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Company Name' @vertical={{true}}>
        <@fields.company />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Website' @vertical={{true}}>
        <@fields.website />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Description' @vertical={{true}}>
        <@fields.description />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Lead Status' @vertical={{true}}>
        <BoxelSelect
          @searchEnabled={{true}}
          @searchField='name'
          @selected={{this.selectedLeadStatus}}
          @onChange={{this.updateLeadStatus}}
          @options={{this.leadStatusOptions}}
          class='select'
          as |item|
        >
          <div>{{item.name}}</div>
        </BoxelSelect>
      </FieldContainer>

      <FieldContainer @tag='label' @label='Lead Owner' @vertical={{true}}>
        <@fields.owner />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Phone' @vertical={{true}}>
        <@fields.phone />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Email' @vertical={{true}}>
        <@fields.email />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Address Info' @vertical={{true}}>
        <@fields.addressInfo />
      </FieldContainer>

      <FieldContainer @tag='label' @label='No. of Employees' @vertical={{true}}>
        <BoxelInput
          @value={{this.args.model.noOfEmployees}}
          @onInput={{this.updateNoOfEmployees}}
        />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Annual Revenue' @vertical={{true}}>
        <@fields.annualRevenue />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Lead Source' @vertical={{true}}>
        <BoxelSelect
          @searchEnabled={{true}}
          @searchField='name'
          @selected={{this.selectedLeadSource}}
          @onChange={{this.updateLeadSource}}
          @options={{this.leadSourceOptions}}
          class='select'
          as |item|
        >
          <div>{{item.name}}</div>
        </BoxelSelect>
      </FieldContainer>

      <FieldContainer @tag='label' @label='Industry' @vertical={{true}}>
        <BoxelSelect
          @searchEnabled={{true}}
          @searchField='name'
          @selected={{this.selectedIndustry}}
          @onChange={{this.updateIndustry}}
          @options={{this.industryOptions}}
          class='select'
          as |item|
        >
          <div>{{item.name}}</div>
        </BoxelSelect>
      </FieldContainer>

    </CardContainer>

    <style>
      .container {
        padding: var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp);
      }
      .select {
        padding: var(--boxel-sp-xs);
        background-color: white;
      }
    </style>
  </template>
}

export class LeadForm extends CardDef {
  static displayName = 'Lead Form';
  @field title = contains(StringField, {
    computeVia: function (this: LeadForm) {
      const { salutation, firstName, lastName } = this.user;

      if (!salutation || !firstName || !lastName) return 'User Not Found';
      return `${salutation} ${firstName} ${lastName}`;
    },
  });
  @field user = contains(UserName, {
    description: `User's Full Name`,
  });
  @field company = linksTo(Company, {
    description: `User's Company Name`,
  });
  @field website = contains(StringField, {
    description: `User's Website`,
  });
  @field description = contains(MarkdownField, {
    description: `User's Description`,
  });
  @field leadStatus = contains(StringField, {
    description: `Lead Status`,
  });
  @field owner = linksTo(MatrixUser, {
    description: `Owner`,
  });
  @field phone = contains(StringField, {
    description: `User's phone number`,
  });
  @field email = contains(UserEmail, {
    description: `User's Email`,
  });
  @field addressInfo = contains(AddressInfo, {
    description: `User's AddressInfo`,
  });
  @field noOfEmployees = contains(NumberField, {
    description: `No Of Employees`,
  });
  @field annualRevenue = contains(CurrencyAmount, {
    description: `Annual Revenue`,
  });
  @field leadSource = contains(StringField, {
    description: `Lead Source`,
  });
  @field industry = contains(StringField, {
    description: `Industry`,
  });

  static isolated = IsolatedSecForLeadForm;
  static atom = ViewSecForLeadForm;
  static embedded = ViewSecForLeadForm;
  static edit = EditSecFoLeadForm;
}