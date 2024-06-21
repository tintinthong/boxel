import type Owner from '@ember/owner';
import { service } from '@ember/service';
import Component from '@glimmer/component';

import { BoxelDropdown, Button, Menu } from '@cardstack/boxel-ui/components';
import { MenuItem, cssVar } from '@cardstack/boxel-ui/helpers';
import { DropdownArrowDown } from '@cardstack/boxel-ui/icons';

import { type RealmInfo, RealmPaths } from '@cardstack/runtime-common';

import RealmIcon from './operator-mode/realm-icon';

import type RealmInfoService from '../services/realm-info-service';

export interface RealmDropdownItem extends RealmInfo {
  path: string;
}

interface Signature {
  Args: {
    onSelect: (item: RealmDropdownItem) => void;
    selectedRealmURL: URL | undefined;
    disabled?: boolean;
    contentClass?: string;
    dropdownWidth?: string;
  };
  Element: HTMLElement;
}

export default class RealmDropdown extends Component<Signature> {
  <template>
    <BoxelDropdown
      @contentClass={{@contentClass}}
      data-test-load-realms-loaded={{this.loaded}}
    >
      <:trigger as |bindings|>
        <Button
          class='realm-dropdown-trigger'
          @kind='secondary-light'
          @size='small'
          @disabled={{@disabled}}
          style={{if
            @dropdownWidth
            (cssVar realm-dropdown-width=@dropdownWidth)
          }}
          {{bindings}}
          data-test-realm-dropdown-trigger
          data-test-realm-name={{this.selectedRealm.name}}
          ...attributes
        >
          {{#if this.selectedRealm}}
            <RealmIcon
              class='icon'
              width='20'
              height='20'
              @realmIconURL={{this.selectedRealm.iconURL}}
              @realmName={{this.selectedRealm.name}}
            />
            <div class='selected-item' data-test-selected-realm>
              {{this.selectedRealm.name}}
            </div>
          {{else}}
            Select a workspace
          {{/if}}
          <DropdownArrowDown class='arrow-icon' width='18px' height='18px' />
        </Button>
      </:trigger>
      <:content as |dd|>
        <Menu
          class='realm-dropdown-menu'
          style={{if
            @dropdownWidth
            (cssVar realm-dropdown-width=@dropdownWidth)
          }}
          @items={{this.menuItems}}
          @closeMenu={{dd.close}}
          data-test-realm-dropdown-menu
        />
      </:content>
    </BoxelDropdown>
    <style>
      .realm-dropdown-trigger {
        width: var(--realm-dropdown-width, auto);
        display: flex;
        justify-content: flex-start;
        gap: var(--boxel-sp-xxxs);
        padding: var(--boxel-sp-xxxs);
        border-radius: var(--boxel-border-radius);
      }
      .arrow-icon {
        --icon-color: var(--boxel-highlight);
        margin-left: auto;
        padding-right: var(--boxel-sp-xxxs);
      }
      .realm-dropdown-trigger[aria-expanded='true'] .arrow-icon {
        transform: scaleY(-1);
      }
      .selected-item {
        text-overflow: ellipsis;
        overflow: hidden;
        white-space: nowrap;
      }
      .realm-dropdown-menu {
        --boxel-menu-item-content-padding: var(--boxel-sp-xs);
        width: var(--realm-dropdown-width, auto);
      }
    </style>
  </template>

  defaultRealmIcon = '/default-realm-icon.png';
  @service declare realmInfoService: RealmInfoService;

  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    this.realmInfoService.fetchAllKnownRealmInfos.perform();
  }

  get loaded() {
    return this.realmInfoService.fetchAllKnownRealmInfos.isIdle;
  }

  get realms(): RealmDropdownItem[] {
    let items: RealmDropdownItem[] | [] = [];
    for (let [
      path,
      realmInfo,
    ] of this.realmInfoService.cachedRealmInfos.entries()) {
      if (!realmInfo.canWrite) {
        continue;
      }
      let item: RealmDropdownItem = {
        path,
        ...realmInfo,
        iconURL: realmInfo.iconURL ?? this.defaultRealmIcon,
      };
      items = [item, ...items];
    }
    items.sort((a, b) => a.name.localeCompare(b.name));
    return items;
  }

  get menuItems(): MenuItem[] {
    return this.realms.map(
      (realm) =>
        new MenuItem(realm.name, 'action', {
          action: () => this.args.onSelect(realm),
          selected: realm.name === this.selectedRealm?.name,
          iconURL: realm.iconURL ?? undefined,
        }),
    );
  }

  get selectedRealm(): RealmDropdownItem | undefined {
    let selectedRealm: RealmDropdownItem | undefined;
    if (this.args.selectedRealmURL) {
      selectedRealm = this.realms.find(
        (realm) =>
          realm.path === new RealmPaths(this.args.selectedRealmURL!).url,
      );
    }
    if (selectedRealm) {
      return selectedRealm;
    }

    return this.realms.find(
      (realm) => realm.path === this.realmInfoService.userDefaultRealm.path,
    );
  }
}
