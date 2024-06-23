import { concat, fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import { inject as service } from '@ember/service';
import { htmlSafe } from '@ember/template';
import { buildWaiter } from '@ember/test-waiters';
import { isTesting } from '@embroider/macros';
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';

import { dropTask, restartableTask, task, timeout } from 'ember-concurrency';
import perform from 'ember-concurrency/helpers/perform';

import { isEqual } from 'lodash';
import get from 'lodash/get';

import { TrackedWeakMap, TrackedSet } from 'tracked-built-ins';

import { cn, eq } from '@cardstack/boxel-ui/helpers';
import { IconPlus, Download } from '@cardstack/boxel-ui/icons';

import {
  Deferred,
  baseCardRef,
  chooseCard,
  codeRefWithAbsoluteURL,
  moduleFrom,
  RealmPaths,
  type Actions,
  type CodeRef,
  type LooseSingleCardDocument,
} from '@cardstack/runtime-common';

import { StackItem } from '@cardstack/host/lib/stack-item';

import { stackBackgroundsResource } from '@cardstack/host/resources/stack-backgrounds';

import type { CardDef, Format } from 'https://cardstack.com/base/card-api';

import CopyButton from './copy-button';
import DeleteModal from './delete-modal';
import OperatorModeStack from './stack';
import SubmodeLayout from './submode-layout';

import type CardService from '../../services/card-service';
import type OperatorModeStateService from '../../services/operator-mode-state-service';
import type RecentFilesService from '../../services/recent-files-service';
import type { Submode } from '../submode-switcher';

const waiter = buildWaiter('operator-mode:interact-submode-waiter');

export type Stack = StackItem[];

const SearchSheetTriggers = {
  DropCardToLeftNeighborStackButton: 'drop-card-to-left-neighbor-stack-button',
  DropCardToRightNeighborStackButton:
    'drop-card-to-right-neighbor-stack-button',
} as const;
type Values<T> = T[keyof T];
type SearchSheetTrigger = Values<typeof SearchSheetTriggers>;

const cardSelections = new TrackedWeakMap<StackItem, TrackedSet<CardDef>>();
const clearSelections = new WeakMap<StackItem, () => void>();
const stackItemScrollers = new WeakMap<
  StackItem,
  {
    stableScroll: (_changeSizeCallback: () => Promise<void>) => void;
    scrollIntoView: (_selector: string) => void;
  }
>();

interface NeighborStackTriggerButtonSignature {
  Element: HTMLButtonElement;
  Args: {
    triggerSide: SearchSheetTrigger;
    activeTrigger: SearchSheetTrigger | null;
    onTrigger: (triggerSide: SearchSheetTrigger) => void;
  };
}

class NeighborStackTriggerButton extends Component<NeighborStackTriggerButtonSignature> {
  get triggerSideClass() {
    switch (this.args.triggerSide) {
      case SearchSheetTriggers.DropCardToLeftNeighborStackButton:
        return 'add-card-to-neighbor-stack--left';
      case SearchSheetTriggers.DropCardToRightNeighborStackButton:
        return 'add-card-to-neighbor-stack--right';
      default:
        return undefined;
    }
  }

  <template>
    <button
      ...attributes
      class={{cn
        'add-card-to-neighbor-stack'
        this.triggerSideClass
        (if
          (eq @activeTrigger @triggerSide) 'add-card-to-neighbor-stack--active'
        )
      }}
      {{on 'click' (fn @onTrigger @triggerSide)}}
    >
      <Download width='19' height='19' />
    </button>
  </template>
}

interface Signature {
  Element: HTMLDivElement;
  Args: {
    write: (card: CardDef) => Promise<CardDef | undefined>;
  };
}

export default class InteractSubmode extends Component<Signature> {
  @service private declare cardService: CardService;
  @service private declare operatorModeStateService: OperatorModeStateService;
  @service private declare recentFilesService: RecentFilesService;

  @tracked private searchSheetTrigger: SearchSheetTrigger | null = null;
  @tracked private itemToDelete: CardDef | undefined = undefined;

  get stacks() {
    return this.operatorModeStateService.state?.stacks ?? [];
  }

  private get allStackItems() {
    return this.operatorModeStateService.state?.stacks.flat() ?? [];
  }

  // The public API is wrapped in a closure so that whatever calls its methods
  // in the context of operator-mode, the methods can be aware of which stack to deal with (via stackIndex), i.e.
  // to which stack the cards will be added to, or from which stack the cards will be removed from.
  private publicAPI(here: InteractSubmode, stackIndex: number): Actions {
    return {
      createCard: async (
        ref: CodeRef,
        relativeTo: URL | undefined,
        opts?: {
          realmURL?: URL;
          isLinkedCard?: boolean;
          doc?: LooseSingleCardDocument; // fill in card data with values
        },
      ): Promise<CardDef | undefined> => {
        let cardModule = new URL(moduleFrom(ref), relativeTo);
        // we make the code ref use an absolute URL for safety in
        // the case it's being created in a different realm than where the card
        // definition comes from
        if (
          opts?.realmURL &&
          !new RealmPaths(opts.realmURL).inRealm(cardModule)
        ) {
          ref = codeRefWithAbsoluteURL(ref, relativeTo);
        }
        let doc: LooseSingleCardDocument = opts?.doc ?? {
          data: {
            meta: {
              adoptsFrom: ref,
              ...(opts?.realmURL ? { realmURL: opts.realmURL.href } : {}),
            },
          },
        };
        let newCard = await here.cardService.createFromSerialized(
          doc.data,
          doc,
          relativeTo,
        );

        let newItem = new StackItem({
          owner: here,
          card: newCard,
          format: 'edit',
          request: new Deferred(),
          isLinkedCard: opts?.isLinkedCard,
          stackIndex,
        });

        // TODO: it is important saveModel happens after newItem because it
        // looks like perhaps there is a race condition (or something else) when a
        // new linked card is created, and when it is added to the stack and closed
        // - the parent card is not updated with the new linked card
        await here.cardService.saveModel(here, newCard);

        await newItem.ready();
        here.addToStack(newItem);
        return await newItem.request?.promise;
      },
      viewCard: async (
        card: CardDef,
        format: Format = 'isolated',
      ): Promise<void> => {
        let newItem = new StackItem({
          owner: here,
          card,
          format,
          stackIndex,
        });
        await newItem.ready();
        here.addToStack(newItem);
      },
      editCard(card: CardDef): void {
        let item = here.findCardInStack(card, stackIndex);
        here.operatorModeStateService.replaceItemInStack(
          item,
          item.clone({
            request: new Deferred(),
            format: 'edit',
          }),
        );
      },
      saveCard(card: CardDef, dismissItem: boolean): void {
        let item = here.findCardInStack(card, stackIndex);
        here.save.perform(item, dismissItem);
      },
      delete: (card: CardDef | URL | string): void => {
        if (!card || card instanceof URL || typeof card === 'string') {
          throw new Error(`bug: delete called with invalid card "${card}"`);
        }
        if (!here.itemToDelete) {
          here.itemToDelete = card;
          return;
        }
        here.delete.perform(card);
      },
      doWithStableScroll: async (
        card: CardDef,
        changeSizeCallback: () => Promise<void>,
      ): Promise<void> => {
        let stackItem: StackItem | undefined;
        for (let stack of here.stacks) {
          stackItem = stack.find((item: StackItem) => item.card === card);
          if (stackItem) {
            let doWithStableScroll =
              stackItemScrollers.get(stackItem)?.stableScroll;
            if (doWithStableScroll) {
              doWithStableScroll(changeSizeCallback); // this is perform()ed in the component
              return;
            }
          }
        }
        await changeSizeCallback();
      },
      changeSubmode: (url: URL, submode: Submode = 'code'): void => {
        here.operatorModeStateService.updateCodePath(url);
        here.operatorModeStateService.updateSubmode(submode);
      },
    };
  }
  stackBackgroundsState = stackBackgroundsResource(this);

  private get backgroundImageStyle() {
    // only return a background image when both stacks originate from the same realm
    // otherwise we delegate to each stack to handle this
    let { hasDifferingBackgroundURLs } = this.stackBackgroundsState;
    if (this.stackBackgroundsState.backgroundImageURLs.length === 0) {
      return false;
    }
    if (!hasDifferingBackgroundURLs) {
      return htmlSafe(
        `background-image: url(${this.stackBackgroundsState.backgroundImageURLs[0]});`,
      );
    }
    return false;
  }

  private findCardInStack(card: CardDef, stackIndex: number): StackItem {
    let item = this.stacks[stackIndex].find((item: StackItem) =>
      card.id ? item.card.id === card.id : isEqual(item.card, card),
    );
    if (!item) {
      throw new Error(`Could not find card ${card.id} in stack ${stackIndex}`);
    }
    return item;
  }

  private addCard = restartableTask(async () => {
    let type = baseCardRef;
    let chosenCard: CardDef | undefined = await chooseCard({
      filter: { type },
    });

    if (chosenCard) {
      // This is called when there are no cards in the stack left, so we can assume the stackIndex is 0
      this.publicAPI(this, 0).viewCard(chosenCard, 'isolated');
    }
  });

  private close = task(async (item: StackItem) => {
    let { card, request } = item;
    // close the item first so user doesn't have to wait for the save to complete
    this.operatorModeStateService.trimItemsFromStack(item);

    // only save when closing a stack item in edit mode. there should be no unsaved
    // changes in isolated mode because they were saved when user toggled between
    // edit and isolated formats
    if (item.format === 'edit') {
      let updatedCard = await this.args.write(card);
      request?.fulfill(updatedCard);
    }
  });

  private save = task(async (item: StackItem, dismissStackItem: boolean) => {
    let { request } = item;
    let updatedCard = await this.args.write(item.card);

    if (updatedCard) {
      request?.fulfill(updatedCard);
      if (!dismissStackItem) {
        return;
      }
      this.operatorModeStateService.replaceItemInStack(
        item,
        item.clone({
          request,
          format: 'isolated',
        }),
      );
    }
  });

  @action private onCancelDelete() {
    this.itemToDelete = undefined;
  }

  // dropTask will ignore any subsequent delete requests until the one in progress is done
  private delete = dropTask(async (card: CardDef) => {
    if (!card?.id) {
      // the card isn't actually saved yet, so do nothing
      return;
    }

    for (let stack of this.stacks) {
      // remove all selections for the deleted card
      for (let item of stack) {
        let selections = cardSelections.get(item);
        if (!selections) {
          continue;
        }
        let removedCard = [...selections].find((c) => c.id === card.id);
        if (removedCard) {
          selections.delete(removedCard);
        }
      }
    }
    await this.withTestWaiters(async () => {
      await this.operatorModeStateService.deleteCard(card);
      await timeout(500); // task running message can be displayed long enough for the user to read it
    });

    this.itemToDelete = undefined;
  });

  private async withTestWaiters<T>(cb: () => Promise<T>) {
    let token = waiter.beginAsync();
    try {
      let result = await cb();
      // only do this in test env--this makes sure that we also wait for any
      // interior card instance async as part of our ember-test-waiters
      if (isTesting()) {
        await this.cardService.cardsSettled();
      }
      return result;
    } finally {
      waiter.endAsync(token);
    }
  }

  // dropTask will ignore any subsequent copy requests until the one in progress is done
  private copy = dropTask(
    async (
      sources: CardDef[],
      sourceItem: StackItem,
      destinationItem: StackItem,
    ) => {
      await this.withTestWaiters(async () => {
        let destinationRealmURL = await this.cardService.getRealmURL(
          destinationItem.card,
        );
        let realmURL = destinationRealmURL;
        sources.sort((a, b) => a.title.localeCompare(b.title));
        let scrollToCard: CardDef | undefined;
        for (let [index, card] of sources.entries()) {
          let newCard = await this.cardService.copyCard(card, realmURL);
          if (index === 0) {
            scrollToCard = newCard; // we scroll to the first card lexically by title
          }
        }
        let clearSelection = clearSelections.get(sourceItem);
        if (typeof clearSelection === 'function') {
          clearSelection();
        }
        cardSelections.delete(sourceItem);
        let scroller = stackItemScrollers.get(destinationItem);
        if (scrollToCard) {
          // Currently the destination item is always a cards-grid, so we use that
          // fact to be able to scroll to the newly copied item
          scroller?.scrollIntoView(
            `[data-stack-card="${destinationItem.card.id}"] [data-cards-grid-item="${scrollToCard.id}"]`,
          );
        }
      });
    },
  );
  @action private addToStack(item: StackItem) {
    this.operatorModeStateService.addItemToStack(item);
  }

  @action
  private onSelectedCards(selectedCards: CardDef[], stackItem: StackItem) {
    let selected = cardSelections.get(stackItem);
    if (!selected) {
      selected = new TrackedSet([]);
      cardSelections.set(stackItem, selected);
    }
    selected.clear();
    for (let card of selectedCards) {
      selected.add(card);
    }
  }

  private get selectedCards() {
    return this.operatorModeStateService
      .topMostStackItems()
      .map((i) => [...(cardSelections.get(i) ?? [])]);
  }

  private setupStackItem = (
    item: StackItem,
    doClearSelections: () => void,
    doWithStableScroll: (changeSizeCallback: () => Promise<void>) => void,
    doScrollIntoView: (selector: string) => void,
  ) => {
    clearSelections.set(item, doClearSelections);
    stackItemScrollers.set(item, {
      stableScroll: doWithStableScroll,
      scrollIntoView: doScrollIntoView,
    });
  };

  // This determines whether we show the left and right button that trigger the search sheet whose card selection will go to the left or right stack
  // (there is a single stack with at least one card in it)
  private get canCreateNeighborStack() {
    return this.allStackItems.length > 0 && this.stacks.length === 1;
  }

  private openSelectedSearchResultInStack = restartableTask(
    async (card: CardDef) => {
      let searchSheetTrigger = this.searchSheetTrigger; // Will be set by showSearchWithTrigger

      // In case the left button was clicked, whatever is currently in stack with index 0 will be moved to stack with index 1,
      // and the card will be added to stack with index 0. shiftStack executes this logic.
      if (
        searchSheetTrigger ===
        SearchSheetTriggers.DropCardToLeftNeighborStackButton
      ) {
        for (
          let stackIndex = this.stacks.length - 1;
          stackIndex >= 0;
          stackIndex--
        ) {
          this.operatorModeStateService.shiftStack(
            this.stacks[stackIndex],
            stackIndex + 1,
          );
        }
        this.publicAPI(this, 0).viewCard(card, 'isolated');

        // In case the right button was clicked, the card will be added to stack with index 1.
      } else if (
        searchSheetTrigger ===
        SearchSheetTriggers.DropCardToRightNeighborStackButton
      ) {
        this.publicAPI(this, this.stacks.length).viewCard(card, 'isolated');
      } else {
        // In case, that the search was accessed directly without clicking right and left buttons,
        // the rightmost stack will be REPLACED by the selection
        let numberOfStacks = this.operatorModeStateService.numberOfStacks();
        let stackIndex = numberOfStacks - 1;
        let stack: Stack | undefined;

        if (
          numberOfStacks === 0 ||
          this.operatorModeStateService.stackIsEmpty(stackIndex)
        ) {
          this.publicAPI(this, 0).viewCard(card, 'isolated');
        } else {
          stack = this.operatorModeStateService.rightMostStack();
          if (stack) {
            let bottomMostItem = stack[0];
            if (bottomMostItem) {
              let stackItem = new StackItem({
                owner: this,
                card,
                format: 'isolated',
                stackIndex,
              });
              await stackItem.ready();
              this.operatorModeStateService.clearStackAndAdd(
                stackIndex,
                stackItem,
              );
            }
          }
        }
      }
    },
  );

  @action private clearSearchSheetTrigger() {
    this.searchSheetTrigger = null;
  }

  @action private showSearchWithTrigger(
    openSearchCallback: () => void,
    searchSheetTrigger: SearchSheetTrigger,
  ) {
    if (
      searchSheetTrigger ==
        SearchSheetTriggers.DropCardToLeftNeighborStackButton ||
      searchSheetTrigger ==
        SearchSheetTriggers.DropCardToRightNeighborStackButton
    ) {
      this.searchSheetTrigger = searchSheetTrigger;
    }
    openSearchCallback();
  }

  <template>
    <SubmodeLayout
      @onSearchSheetClosed={{this.clearSearchSheetTrigger}}
      @onCardSelectFromSearch={{perform this.openSelectedSearchResultInStack}}
      as |openSearch|
    >
      <div class='operator-mode__main' style={{this.backgroundImageStyle}}>
        {{#if (eq this.allStackItems.length 0)}}
          <div class='no-cards' data-test-empty-stack>
            <p class='add-card-title'>
              Add a card to get started
            </p>

            <button
              class='add-card-button'
              {{on 'click' (fn (perform this.addCard))}}
              data-test-add-card-button
            >
              <IconPlus width='36px' height='36px' />
            </button>
          </div>
        {{else}}
          {{#each this.stacks as |stack stackIndex|}}
            {{#let
              (get
                this.stackBackgroundsState.differingBackgroundImageURLs
                stackIndex
              )
              as |backgroundImageURLSpecificToThisStack|
            }}
              <OperatorModeStack
                data-test-operator-mode-stack={{stackIndex}}
                class={{cn
                  'operator-mode-stack'
                  (if backgroundImageURLSpecificToThisStack 'with-bg-image')
                }}
                style={{if
                  backgroundImageURLSpecificToThisStack
                  (htmlSafe
                    (concat
                      'background-image: url('
                      backgroundImageURLSpecificToThisStack
                      ')'
                    )
                  )
                }}
                @stackItems={{stack}}
                @stackIndex={{stackIndex}}
                @publicAPI={{this.publicAPI this stackIndex}}
                @close={{perform this.close}}
                @onSelectedCards={{this.onSelectedCards}}
                @setupStackItem={{this.setupStackItem}}
              />
            {{/let}}
          {{/each}}

          <CopyButton
            @selectedCards={{this.selectedCards}}
            @copy={{fn (perform this.copy)}}
            @isCopying={{this.copy.isRunning}}
          />
        {{/if}}

        {{#if this.canCreateNeighborStack}}
          <NeighborStackTriggerButton
            data-test-add-card-left-stack
            @triggerSide={{SearchSheetTriggers.DropCardToLeftNeighborStackButton}}
            @activeTrigger={{this.searchSheetTrigger}}
            @onTrigger={{fn this.showSearchWithTrigger openSearch}}
          />
          <NeighborStackTriggerButton
            data-test-add-card-right-stack
            @triggerSide={{SearchSheetTriggers.DropCardToRightNeighborStackButton}}
            @activeTrigger={{this.searchSheetTrigger}}
            @onTrigger={{fn this.showSearchWithTrigger openSearch}}
          />
        {{/if}}
        {{#if this.itemToDelete}}
          <DeleteModal
            @itemToDelete={{this.itemToDelete}}
            @onConfirm={{get (this.publicAPI this 0) 'delete'}}
            @onCancel={{this.onCancelDelete}}
            @isDeleteRunning={{this.delete.isRunning}}
          />
        {{/if}}
      </div>
    </SubmodeLayout>

    <style>
      .operator-mode__main {
        display: flex;
        justify-content: center;
        align-items: center;
        position: relative;
        background-position: center;
        background-size: cover;
        height: 100%;
      }
      .no-cards {
        height: calc(100% -var(--search-sheet-closed-height));
        width: 100%;
        max-width: 50rem;
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: center;
      }
      .add-card-title {
        color: var(--boxel-light);
        font: var(--boxel-font-lg);
      }
      .add-card-button {
        --icon-color: var(--boxel-light);
        height: 350px;
        width: 200px;
        vertical-align: middle;
        background-color: var(--boxel-highlight);
        border: none;
        border-radius: var(--boxel-border-radius);
      }
      .add-card-button:hover {
        background-color: var(--boxel-highlight-hover);
      }
      .add-card-to-neighbor-stack {
        --icon-color: var(--boxel-highlight-hover);
        position: absolute;
        width: var(--container-button-size);
        height: var(--container-button-size);
        padding: 0;
        border-radius: 50%;
        background-color: var(--boxel-light-100);
        border-color: transparent;
        box-shadow: var(--boxel-deep-box-shadow);
      }
      .add-card-to-neighbor-stack:hover,
      .add-card-to-neighbor-stack--active {
        --icon-color: var(--boxel-highlight);
        background-color: var(--boxel-light);
      }
      .add-card-to-neighbor-stack--left {
        left: var(--boxel-sp);
      }
      .add-card-to-neighbor-stack--right {
        right: var(--boxel-sp);
      }
    </style>
  </template>
}
