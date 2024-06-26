import type { TemplateOnlyComponent } from '@ember/component/template-only';

import RouteTemplate from 'ember-route-template';

import CardPrerender from '@cardstack/host/components/card-prerender';

interface ApplicationRouteSignature {
  Args: {};
}

const ApplicationRouteComponent: TemplateOnlyComponent<ApplicationRouteSignature> =
  <template>
    {{outlet}}
    <CardPrerender />

    {{! this is a signal for the Realm DOM tests to know that app has loaded }}
    {{! template-lint-disable no-inline-styles }}
    <div data-test-boxel-root style='display: none;'></div>
  </template>;

export default RouteTemplate(ApplicationRouteComponent);
