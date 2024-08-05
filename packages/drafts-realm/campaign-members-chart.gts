import { ContactForm } from './contact-form';
import { LeadForm } from './lead-form';
import {
  Component,
  CardDef,
  FieldDef,
  field,
  contains,
  StringField,
  linksTo,
  containsMany,
} from 'https://cardstack.com/base/card-api';

import {
  FieldContainer,
  BoxelSelect,
  BoxelInput,
} from '@cardstack/boxel-ui/components';
import { action } from '@ember/object';

class ContactMembersFieldEdit extends Component<typeof ContactMembersField> {
  get selectedResponseStatus() {
    return {
      name: this.args.model.responseStatus,
    };
  }
  @action updateResponseStatus(type: { name: string }) {
    this.args.model.responseStatus = type.name;
  }

  private responseStatuses = [{ name: 'Sent' }, { name: 'Responded' }];

  <template>
    <@fields.contactForm />
    <FieldContainer
      @label='Response Status'
      data-test-field='contact-form-response-status'
      class='field'
      @vertical={{true}}
    >
      <BoxelSelect
        @placeholder={{'Select Status'}}
        @selected={{this.selectedResponseStatus}}
        @onChange={{this.updateResponseStatus}}
        @options={{this.responseStatuses}}
        @dropdownClass='boxel-select-contact-form-response-status'
        as |item|
      >
        <div>{{item.name}}</div>
      </BoxelSelect>
    </FieldContainer>
  </template>
}

class ContactMembersField extends FieldDef {
  static displayName = 'ContactMember';
  @field contactForm = linksTo(ContactForm);
  @field responseStatus = contains(StringField);

  static edit = ContactMembersFieldEdit;
}

class LeadMembersFieldEdit extends Component<typeof LeadMembersField> {
  get selectedResponseStatus() {
    return {
      name: this.args.model.responseStatus,
    };
  }
  @action updateResponseStatus(type: { name: string }) {
    this.args.model.responseStatus = type.name;
  }

  private responseStatuses = [{ name: 'Sent' }, { name: 'Responded' }];

  <template>
    <@fields.leadForm />
    <FieldContainer
      @label='Response Status'
      data-test-field='lead-form-response-status'
      class='field'
      @vertical={{true}}
    >
      <BoxelSelect
        @placeholder={{'Select Status'}}
        @selected={{this.selectedResponseStatus}}
        @onChange={{this.updateResponseStatus}}
        @options={{this.responseStatuses}}
        @dropdownClass='boxel-select-lead-form-response-status'
        as |item|
      >
        <div>{{item.name}}</div>
      </BoxelSelect>
    </FieldContainer>
  </template>
}

class LeadMembersField extends FieldDef {
  static displayName = 'LeadMember';
  @field leadForm = linksTo(LeadForm);
  @field responseStatus = contains(StringField);

  static edit = LeadMembersFieldEdit;
}

class Isolated extends Component<typeof CampaignMembersChart> {
  get numberSent() {
    let { model } = this.args;
    const contactMembers =
      model.contactMembers?.filter(
        (contactMember) => contactMember.responseStatus === 'Sent',
      ) || [];
    const leadMembers =
      model.leadMembers?.filter(
        (leadMember) => leadMember.responseStatus === 'Sent',
      ) || [];
    return contactMembers.length + leadMembers.length;
  }

  get numberResponsed() {
    let { model } = this.args;
    const contactMembers =
      model.contactMembers?.filter(
        (contactMember) => contactMember.responseStatus === 'Responded',
      ) || [];
    const leadMembers =
      model.leadMembers?.filter(
        (leadMember) => leadMember.responseStatus === 'Responded',
      ) || [];
    return contactMembers.length + leadMembers.length;
  }

  <template>
    <div class='campaign-form-isolated'>
      <FieldContainer @label='Name' class='field'>
        {{@model.name}}
      </FieldContainer>
      <FieldContainer @label='Sent' class='field'>
        {{this.numberSent}}
      </FieldContainer>
      <FieldContainer @label='Responded' class='field'>
        {{this.numberResponsed}}
      </FieldContainer>
    </div>
    <style>
      .campaign-members-chart-isolated {
        display: grid;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-xl);
      }
    </style>
  </template>
}

class Embedded extends Component<typeof CampaignMembersChart> {
  <template>
    {{@model.name}}
  </template>
}

class Edit extends Component<typeof CampaignMembersChart> {
  get selectedChartType() {
    return {
      name: this.args.model.chartType,
    };
  }

  @action updateName(inputText: string) {
    this.args.model.name = inputText;
  }

  @action updateChartType(type: { name: string }) {
    this.args.model.chartType = type.name;
  }

  private campaignChartTypes = [
    { name: 'Donut' },
    { name: 'Vertical Bar' },
    { name: 'Horizontal Bar' },
  ];

  <template>
    <div class='campaign-members-chart-edit'>
      <FieldContainer
        @label='Campaign Name'
        data-test-field='name'
        @tag='label'
        class='field'
      >
        <BoxelInput
          @value={{this.args.model.name}}
          @onInput={{this.updateName}}
          maxlength='255'
        />
      </FieldContainer>

      <FieldContainer
        @label='Chart Type'
        data-test-field='chart-type'
        class='field'
      >
        <BoxelSelect
          @placeholder={{'Select Type'}}
          @selected={{this.selectedChartType}}
          @onChange={{this.updateChartType}}
          @options={{this.campaignChartTypes}}
          @dropdownClass='boxel-select-campaign-chart-type'
          as |item|
        >
          <div>{{item.name}}</div>
        </BoxelSelect>
      </FieldContainer>
      <FieldContainer
        @label='Contact Members'
        data-test-field='contact-members'
        class='field'
      >
        <@fields.contactMembers />
      </FieldContainer>
      <FieldContainer
        @label='Lead Members'
        data-test-field='lead-members'
        class='field'
      >
        <@fields.leadMembers />
      </FieldContainer>
    </div>
    <style>
      .campaign-members-chart-edit {
        display: grid;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-xl);
      }
    </style>
  </template>
}

export class CampaignMembersChart extends CardDef {
  static displayName = 'CampaignMembersChart';

  @field name = contains(StringField);
  @field chartType = contains(StringField);
  @field contactMembers = containsMany(ContactMembersField);
  @field leadMembers = containsMany(LeadMembersField);

  static isolated = Isolated;
  static embedded = Embedded;
  static atom = Embedded;
  static edit = Edit;
}
