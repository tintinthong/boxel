import MarkdownField from 'https://cardstack.com/base/markdown';
import {
  CardDef,
  FieldDef,
  contains,
  field,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import { Component } from 'https://cardstack.com/base/card-api';
import DateCard from 'https://cardstack.com/base/date';
import StringField from 'https://cardstack.com/base/string';
import {
  BoxelSelect,
  CardContainer,
  FieldContainer,
} from '@cardstack/boxel-ui/components';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { CrmAccount } from './crm/account';

interface SubjectSignature {
  name: string;
}

class EditSecForSubjectField extends Component<typeof SubjectField> {
  @tracked selectedSubject = {
    name: this.args.model.title || 'Select',
  };

  @tracked subjectPlaceholder = this.args.model.title || 'Select';

  @tracked subjectOptions = [
    { name: 'None' },
    { name: 'Email' },
    { name: 'Call' },
    { name: 'Send Letter' },
    { name: 'Send Quote' },
    { name: 'Other' },
  ] as Array<SubjectSignature>;

  @action updateSubject(type: { name: string }) {
    this.selectedSubject = type;
    this.args.model.title = type.name;
  }

  <template>
    <CardContainer @displayBoundaries={{false}} class='card-container'>

      <BoxelSelect
        @searchEnabled={{true}}
        @searchField='name'
        @placeholder={{this.subjectPlaceholder}}
        @selected={{this.selectedSubject}}
        @onChange={{this.updateSubject}}
        @options={{this.subjectOptions}}
        class='select'
        as |item|
      >
        <div>{{item.name}}</div>
      </BoxelSelect>

    </CardContainer>

    <style>
      .select {
        padding: var(--boxel-sp-xs);
        background-color: white;
      }
    </style>
  </template>
}

class EditSecForAccountField extends Component<typeof AccountField> {
  @tracked selectedAccount = {
    name: this.args.model.account || 'Select',
  };

  @tracked accountPlaceholder = this.args.model.account || 'Select';

  get getAccountsNames() {
    let allAccounts = this.args.model.accounts || [];
    return allAccounts.map((o) => ({ name: o.accountName }));
  }

  @action updateAccount(type: { name: string }) {
    this.selectedAccount = type;
    this.args.model.account = type.name;
  }

  <template>
    <CardContainer @displayBoundaries={{false}} class='card-container'>

      <BoxelSelect
        @placeholder={{this.accountPlaceholder}}
        @selected={{this.selectedAccount}}
        @onChange={{this.updateAccount}}
        @options={{this.getAccountsNames}}
        class='select'
        as |item|
      >
        <div>{{item.name}}</div>
      </BoxelSelect>

    </CardContainer>

    <style>
      .select {
        padding: var(--boxel-sp-xs);
        background-color: white;
      }
    </style>
  </template>
}

class EmbeddedSecForSubjectField extends Component<typeof SubjectField> {
  <template>
    <div class='subject'>{{this.args.model.title}}</div>

    <style>
      .subject {
        margin: 0px;
      }
    </style>
  </template>
}

class EmbeddedSecForAccountField extends Component<typeof AccountField> {
  <template>
    <CardContainer @displayBoundaries={{false}} class='card-container'>
      {{this.args.model.account}}
    </CardContainer>

    <style>
      .card-container {
        background: transparent;
      }
    </style>
  </template>
}

class IsolatedSecForTaskForm extends Component<typeof TaskForm> {
  <template>
    <CardContainer @displayBoundaries={{false}} class='card-container'>
      <FieldContainer @tag='label' @label='Subject' @vertical={{false}}>
        <@fields.subject /></FieldContainer>

      <FieldContainer @tag='label' @label='Due Date' @vertical={{false}}>
        <@fields.dueDate />
      </FieldContainer>

      <FieldContainer @tag='label' @label='Comments' @vertical={{false}}>
        <div class='comments-box'> <@fields.comments /></div>
      </FieldContainer>

      <FieldContainer @tag='label' @label='Related To' @vertical={{false}}>
        <@fields.relatedTo />
      </FieldContainer>
    </CardContainer>

    <style>
      .card-container {
        padding: var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp-lg);
      }

      .comments-box {
        padding: var(--boxel-sp-xs) var(--boxel-sp-lg);
        border: 1px solid var(--boxel-form-control-border-color);
        border-radius: var(--boxel-form-control-border-radius);
      }
    </style>
  </template>
}

class ViewSecForTaskForm extends Component<typeof TaskForm> {
  <template>
    <CardContainer @displayBoundaries={{true}} class='card-container'>

      <h2><@fields.subject.title /></h2>

      <div class='details-container'>
        <div class='details-heading'>Details</div>
        <div class='details-content'>
          <FieldContainer @tag='label' @label='Related To' @vertical={{false}}>
            <@fields.relatedTo.account />
          </FieldContainer>

          <FieldContainer @tag='label' @label='Due Date' @vertical={{false}}>
            <@fields.dueDate />
          </FieldContainer>
        </div>
      </div>
    </CardContainer>

    <style>
      .card-container {
        padding: var(--boxel-sp-lg);
        display: grid;
        background: white;
      }
      .details-container {
        background: #eeeeee20;
        border: 1px solid var(--boxel-form-control-border-color);
        margin-top: 2rem;
      }
      .details-container > * + * {
        border-top: 1px dashed var(--boxel-form-control-border-color);
        border-bottom-width: 0px;
      }
      .details-content {
        display: grid;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-sm) var(--boxel-sp-lg);
      }
      .details-heading {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      h2 {
        margin: 0px;
      }
    </style>
  </template>
}

class SubjectField extends FieldDef {
  @field title = contains(StringField, {
    description: `Selected Subject`,
  });

  static edit = EditSecForSubjectField;
  static embedded = EmbeddedSecForSubjectField;
}

class AccountField extends FieldDef {
  @field accounts = linksToMany(() => CrmAccount);
  @field account = contains(StringField);

  static edit = EditSecForAccountField;
  static embedded = EmbeddedSecForAccountField;
}

export class TaskForm extends CardDef {
  static displayName = 'Task Form';
  @field subject = contains(SubjectField);
  @field dueDate = contains(DateCard);
  @field comments = contains(MarkdownField);
  @field relatedTo = contains(AccountField);

  static isolated = IsolatedSecForTaskForm;
  static atom = ViewSecForTaskForm;
  static embedded = ViewSecForTaskForm;
}
