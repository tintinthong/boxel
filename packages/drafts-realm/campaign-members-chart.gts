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
import GlimmerComponent from '@glimmer/component';
import { action } from '@ember/object';

// @ts-ignore
import * as d3 from 'https://cdn.jsdelivr.net/npm/d3@7.9.0/+esm';

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

interface DonutChartSignature {
  Args: {
    numberSent: number;
    numberResponsed: number;
  };
  Element: HTMLElement;
}

class DonutChart extends GlimmerComponent<DonutChartSignature> {
  get displayDonut() {
    if (typeof document === 'undefined') {
      return;
    }

    const data = [
      { name: 'Sent', value: this.args.numberSent },
      { name: 'Responded', value: this.args.numberResponsed },
    ];

    const width = 200;
    const height = 200;
    const radius = Math.min(width, height) / 2;

    const color = d3.scaleOrdinal(d3.schemeCategory10);

    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', width.toString());
    svg.setAttribute('height', height.toString());

    const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    g.setAttribute('transform', `translate(${width / 2}, ${height / 2})`);

    svg.appendChild(g);

    // Add middle text
    const middleText = document.createElementNS(
      'http://www.w3.org/2000/svg',
      'text',
    );
    middleText.setAttribute('text-anchor', 'middle');
    middleText.setAttribute('dy', '.35em');
    middleText.setAttribute('font-size', '20px');
    middleText.textContent = (
      this.args.numberSent + this.args.numberResponsed
    ).toString();
    g.appendChild(middleText);

    const tooltip = d3
      .select('.donut-chart')
      .append('div')
      .attr('class', 'tooltip')
      .style('opacity', 0);

    const arc = d3
      .arc()
      .innerRadius(radius - 50)
      .outerRadius(radius);

    const pie = d3.pie().value((d: { value: any }) => d.value);

    const arcs = d3
      .select(g)
      .selectAll('.arc')
      .data(pie(data))
      .enter()
      .append('g')
      .attr('class', 'arc');

    arcs
      .append('path')
      .attr('d', arc)
      .style('fill', (d: any) => color(d.data.name))
      .on('mouseover', function (event, d) {
        d3.select(this).style('opacity', 0.7);
        tooltip
          .style('opacity', 1)
          .html(
            `<div><strong>Status</strong><br>${d.data.name}<br>---<br>Number of members: ${d.data.value}</div>`,
          )
          .style('top', event.pageY - 10 + 'px')
          .style('left', event.pageX + 10 + 'px');
      })
      .on('mouseout', function (event, d) {
        d3.select(this).style('opacity', 1);
        tooltip.style('opacity', 0);
      });

    arcs
      .append('text')
      .attr('transform', (d: any) => 'translate(' + arc.centroid(d) + ')')
      .attr('dy', '.35em')
      .style('text-anchor', 'middle')
      .text((d: any) => d.data.value);

    return svg;
  }

  <template>
    <div class='donut-chart-container'>
      <h4>Number of Members</h4>
      <div class='donut-chart'>
        {{this.displayDonut}}
      </div>
    </div>
    <style>
      .donut-chart-container {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        align-items: center;
      }
      .donut-chart-container .donut-chart div.tooltip {
        position: absolute;
        text-align: center;
        padding: 0.5rem;
        background: #ffffff;
        color: #313639;
        border: 1px solid #313639;
        border-radius: 8px;
        pointer-events: none;
        font-size: 1.3rem;
      }
    </style>
  </template>
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

  get chartType() {
    return this.args.model.chartType;
  }

  get isChartTypeDonut() {
    return this.chartType === 'Donut';
  }

  <template>
    <div class='campaign-members-chart-isolated'>
      <FieldContainer @label='Name' class='field'>
        {{@model.name}}
      </FieldContainer>
      {{#if this.isChartTypeDonut}}
        <DonutChart
          @numberSent={{this.numberSent}}
          @numberResponsed={{this.numberResponsed}}
        />
      {{/if}}
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
