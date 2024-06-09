import { expect, test } from '@playwright/test';
import { registerUser } from '../docker/synapse';
import {
  login,
  logout,
  createRoom,
  getRoomId,
  openRoom,
  assertMessages,
  writeMessage,
  sendMessage,
  testHost,
  reloadAndOpenAiAssistant,
  isInRoom,
  registerRealmUsers,
  selectCardFromCatalog,
  getRoomEvents,
  setupTwoStackItems,
} from '../helpers';
import {
  synapseStart,
  synapseStop,
  type SynapseInstance,
} from '../docker/synapse';

test.describe('Room messages', () => {
  let synapse: SynapseInstance;
  test.beforeEach(async () => {
    synapse = await synapseStart();
    await registerRealmUsers(synapse);
    await registerUser(synapse, 'user1', 'pass');
  });
  test.afterEach(async () => {
    await synapseStop(synapse.synapseId);
  });

  test(`it can send a message in a room`, async ({ page }) => {
    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);
    await expect(page.locator('[data-test-new-session]')).toHaveCount(1);
    await expect(page.locator('[data-test-message-field]')).toHaveValue('');

    await expect(page.locator('[data-test-send-message-btn]')).toBeDisabled();
    await assertMessages(page, []);

    await writeMessage(page, room1, 'Message 1');
    await page.locator('[data-test-send-message-btn]').click();

    await expect(page.locator('[data-test-message-field]')).toHaveValue('');
    await expect(page.locator('[data-test-new-session]')).toHaveCount(0);
    await assertMessages(page, [{ from: 'user1', message: 'Message 1' }]);

    let room2 = await createRoom(page);
    await openRoom(page, room1);

    await reloadAndOpenAiAssistant(page);
    await openRoom(page, room1);
    await assertMessages(page, [{ from: 'user1', message: 'Message 1' }]);

    await logout(page);
    await login(page, 'user1', 'pass');
    await openRoom(page, room1);
    await assertMessages(page, [{ from: 'user1', message: 'Message 1' }]);

    // make sure that room state doesn't leak
    await openRoom(page, room2);
    await isInRoom(page, room2);
    await assertMessages(page, []);

    await openRoom(page, room1);
    await assertMessages(page, [{ from: 'user1', message: 'Message 1' }]);
  });

  test(`it can load all events back to beginning of timeline for timelines that truncated`, async ({
    page,
  }) => {
    // generally the matrix server paginates after 10 messages
    const totalMessageCount = 20;

    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);

    for (let i = 1; i <= totalMessageCount; i++) {
      await sendMessage(page, room1, `message ${i}`);
    }
    await logout(page);

    await login(page, 'user1', 'pass');
    await openRoom(page, room1);

    await expect(page.locator('[data-test-message-idx]')).toHaveCount(
      totalMessageCount,
    );
  });

  test(`it can send a markdown message`, async ({ page }) => {
    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);
    await sendMessage(page, room1, 'message with _style_');
    await assertMessages(page, [
      {
        from: 'user1',
        message: 'message with style',
      },
    ]);
    await expect(
      page.locator(`[data-test-message-idx="0"] .content em`),
    ).toContainText('style');
  });

  test(`it can create a room specific pending message`, async ({ page }) => {
    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);
    await sendMessage(page, room1, 'Hello');
    let room2 = await createRoom(page);
    await openRoom(page, room1);

    await writeMessage(page, room1, 'room 1 message');
    await openRoom(page, room2);
    await expect(
      page.locator(`[data-test-message-field="${room2}"]`),
    ).toHaveValue('');

    await openRoom(page, room1);
    await expect(
      page.locator(`[data-test-message-field="${room1}"]`),
    ).toHaveValue('room 1 message');

    await openRoom(page, room2);
    await expect(
      page.locator(`[data-test-message-field="${room2}"]`),
    ).toHaveValue('');

    await writeMessage(page, room2, 'room 2 message');
    await openRoom(page, room1);
    await expect(
      page.locator(`[data-test-message-field="${room1}"]`),
    ).toHaveValue('room 1 message');
    await openRoom(page, room2);
    await expect(
      page.locator(`[data-test-message-field="${room2}"]`),
    ).toHaveValue('room 2 message');
  });

  test('can add a card to a markdown message', async ({ page }) => {
    const testCard = `${testHost}/hassan`;
    await login(page, 'user1', 'pass');
    await page.locator(`[data-test-room-settled]`).waitFor();

    await page.locator('[data-test-choose-card-btn]').click();
    await page
      .locator(
        `[data-test-realm="Test Workspace A"] [data-test-show-more-cards]`,
      )
      .click();
    await page.locator(`[data-test-select="${testCard}"]`).click();
    await page.locator('[data-test-card-catalog-go-button]').click();
    await expect(
      page.locator(`[data-test-attached-card="${testCard}"]`),
    ).toContainText('Hassan');

    await page.locator('[data-test-message-field]').fill('This is _my_ card');
    await page.locator('[data-test-send-message-btn]').click();

    await assertMessages(page, [
      {
        from: 'user1',
        message: 'This is my card',
        cards: [
          {
            id: testCard,
            title: 'Hassan',
            realmIconUrl: 'https://i.postimg.cc/d0B9qMvy/icon.png',
          },
        ],
      },
    ]);
    await expect(
      page.locator(`[data-test-message-idx="0"] .content em`),
    ).toContainText('my');
  });

  test('can add a card that is over 65K to a message (i.e. split card into multiple matrix events)', async ({
    page,
  }) => {
    const testCard = `${testHost}/big-card`; // this is a 153KB card
    await login(page, 'user1', 'pass');
    await page.locator(`[data-test-room-settled]`).waitFor();
    await page.locator('[data-test-choose-card-btn]').click();
    await page
      .locator(
        `[data-test-realm="Test Workspace A"] [data-test-show-more-cards]`,
      )
      .click();
    await page.locator(`[data-test-select="${testCard}"]`).click();
    await page.locator('[data-test-card-catalog-go-button]').click();
    await expect(
      page.locator(`[data-test-attached-card="${testCard}"]`),
    ).toContainText('Big Card');

    await page.locator('[data-test-message-field]').fill('This is a big card');
    await page.locator('[data-test-send-message-btn]').click();
    await assertMessages(page, [
      {
        from: 'user1',
        message: 'This is a big card',
        cards: [{ id: testCard, title: 'Big Card' }],
      },
    ]);

    // peek into the matrix events and confirm there are multiple card fragments
    let messages = await getRoomEvents();
    let cardFragments = messages.filter(
      (message) =>
        message.type === 'm.room.message' &&
        message.content?.msgtype === 'org.boxel.cardFragment',
    );
    expect(cardFragments.length).toStrictEqual(3);
    let lastFragment = messages.findIndex((m) => m === cardFragments[2]);
    let boxelMessage = messages[lastFragment + 1];
    let boxelMessageData = JSON.parse(boxelMessage.content.data);
    // the card fragment events need to come before the boxel message event they
    // are used in, and the boxel message should point to the first fragment
    expect(boxelMessageData.attachedCardsEventIds).toMatchObject([
      // card fragments are posted in reverse order so we can fashion the
      // nextFragment property, so the item at index #2 is the first fragment
      cardFragments[2].event_id,
    ]);
  });

  test('it can strip out base64 image fields from cards sent in messages', async ({
    page,
  }) => {
    const testCard = `${testHost}/mango-puppy`; // this is a 153KB card
    await login(page, 'user1', 'pass');
    await page.locator(`[data-test-room-settled]`).waitFor();
    await page.locator('[data-test-choose-card-btn]').click();

    await page
      .locator(
        `[data-test-realm="Test Workspace A"] [data-test-show-more-cards]`,
      )
      .click();
    await page.locator(`[data-test-select="${testCard}"]`).click();
    await page.locator('[data-test-card-catalog-go-button]').click();
    await expect(
      page.locator(`[data-test-attached-card="${testCard}"]`),
    ).toContainText('Mango the Puppy');

    await page
      .locator('[data-test-message-field]')
      .fill('This is a card without base64');
    await page.locator('[data-test-send-message-btn]').click();
    await assertMessages(page, [
      {
        from: 'user1',
        message: 'This is a card without base64',
        cards: [{ id: testCard, title: 'Mango the Puppy' }],
      },
    ]);

    let messages = await getRoomEvents();
    let message = messages[messages.length - 2];
    let messageData = JSON.parse(message.content.data);
    let serializeCard = JSON.parse(messageData.cardFragment);

    expect(serializeCard.data.attributes.name).toStrictEqual('Mango the Puppy');
    expect(serializeCard.data.attributes.picture).toBeUndefined();
  });

  test(`it does include patch tool in message event when top-most card is writable and context is shared`, async ({
    page,
  }) => {
    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);
    await page
      .locator(
        `[data-test-stack-card="${testHost}/index"] [data-test-cards-grid-item="${testHost}/mango"]`,
      )
      .click();
    await expect(
      page.locator(`[data-test-stack-card="${testHost}/mango"]`),
    ).toHaveCount(1);
    await sendMessage(page, room1, 'please change this card');
    let message = (await getRoomEvents()).pop()!;
    expect(message.content.msgtype).toStrictEqual('org.boxel.message');
    let boxelMessageData = JSON.parse(message.content.data);
    expect(boxelMessageData.context.tools).toMatchObject([
      {
        type: 'function',
        function: {
          name: 'patchCard',
          description:
            'Propose a patch to an existing card to change its contents. Any attributes specified will be fully replaced, return the minimum required to make the change. If a relationship field value is removed, set the self property of the specific item to null. When editing a relationship array, display the full array in the patch code. Ensure the description explains what change you are making.',
          parameters: {
            type: 'object',
            properties: {
              description: {
                type: 'string',
              },
              card_id: {
                type: 'string',
                const: `${testHost}/mango`,
              },
              attributes: {
                type: 'object',
                properties: {
                  firstName: {
                    type: 'string',
                  },
                  lastName: {
                    type: 'string',
                  },
                  email: {
                    type: 'string',
                  },
                  posts: {
                    type: 'number',
                  },
                  thumbnailURL: {
                    type: 'string',
                  },
                },
              },
            },
            required: ['card_id', 'attributes', 'description'],
          },
        },
      },
    ]);
  });

  test(`it does not include patch tool in message event for an open card that is not attached`, async ({
    page,
  }) => {
    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);
    await page
      .locator(
        `[data-test-stack-card="${testHost}/index"] [data-test-cards-grid-item="${testHost}/mango"]`,
      )
      .click();
    await expect(
      page.locator(`[data-test-stack-card="${testHost}/mango"]`),
    ).toHaveCount(1);
    await page
      .locator(
        `[data-test-attached-card="${testHost}/mango"] [data-test-remove-card-btn]`,
      )
      .click();
    await sendMessage(page, room1, 'please change this card');
    let message = (await getRoomEvents()).pop()!;
    expect(message.content.msgtype).toStrictEqual('org.boxel.message');
    let boxelMessageData = JSON.parse(message.content.data);
    expect(boxelMessageData.context.tools).toMatchObject([]);
  });

  test(`it does not include patch tool in message event when top-most card is read-only`, async ({
    page,
  }) => {
    // the base realm is a read-only realm
    await login(page, 'user1', 'pass', { url: `http://localhost:4201/base` });
    let room1 = await getRoomId(page);
    await page
      .locator(
        '[data-test-stack-card="https://cardstack.com/base/index"] [data-test-cards-grid-item="https://cardstack.com/base/fields/boolean-field"]',
      )
      .click();
    await expect(
      page.locator(
        '[data-test-stack-card="https://cardstack.com/base/fields/boolean-field"]',
      ),
    ).toHaveCount(1);
    await sendMessage(page, room1, 'please change this card');
    let message = (await getRoomEvents()).pop()!;
    expect(message.content.msgtype).toStrictEqual('org.boxel.message');
    let boxelMessageData = JSON.parse(message.content.data);
    expect(boxelMessageData.context.tools).toMatchObject([]);
  });

  test('can send only a card as a message', async ({ page }) => {
    const testCard = `${testHost}/hassan`;
    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);
    await sendMessage(page, room1, undefined, [testCard]);
    await assertMessages(page, [
      {
        from: 'user1',
        cards: [{ id: testCard, title: 'Hassan' }],
      },
    ]);
  });

  test('can send cards with types unsupported by matrix', async ({ page }) => {
    const testCard = `${testHost}/type-examples`;
    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);

    // Send a card that contains a type that matrix doesn't support
    await sendMessage(page, room1, undefined, [testCard]);
    await assertMessages(page, [
      {
        from: 'user1',
        cards: [{ id: testCard, title: 'Type Examples' }],
      },
    ]);
  });

  test('can remove a card from a pending message', async ({ page }) => {
    const testCard = `${testHost}/hassan`;
    const testCard2 = `${testHost}/mango`;
    await login(page, 'user1', 'pass');
    await page.locator(`[data-test-room-settled]`).waitFor();

    await selectCardFromCatalog(page, testCard);
    await selectCardFromCatalog(page, testCard2);
    await expect(
      page.locator(`[data-test-attached-card="${testCard}"]`),
    ).toContainText('Hassan');
    await expect(
      page.locator(`[data-test-attached-card="${testCard2}"]`),
    ).toContainText('Mango');

    await page
      .locator(
        `[data-test-attached-card="${testCard}"] [data-test-remove-card-btn]`,
      )
      .click();
    await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);

    await page.locator('[data-test-message-field]').fill('1 card');
    await page.locator('[data-test-send-message-btn]').click();

    await selectCardFromCatalog(page, testCard);
    await expect(
      page.locator(`[data-test-attached-card="${testCard}"]`),
    ).toContainText('Hassan');
    await page
      .locator(
        `[data-test-attached-card="${testCard}"] [data-test-remove-card-btn]`,
      )
      .click();
    await expect(
      page.locator(`[data-test-chat-input-area] [data-test-attached-card]`),
    ).toHaveCount(0);

    await page.locator('[data-test-message-field]').fill('no card');
    await page.locator('[data-test-send-message-btn]').click();

    await page.pause();

    await assertMessages(page, [
      {
        from: 'user1',
        message: '1 card',
        cards: [{ id: testCard2, title: 'Mango' }],
      },
      {
        from: 'user1',
        message: 'no card',
      },
    ]);
  });

  test('can render multiple cards in a room', async ({ page }) => {
    // the loader deadlocking issue would otherwise prevent this

    const testCard1 = `${testHost}/hassan`;
    const testCard2 = `${testHost}/mango`;
    const message1 = {
      from: 'user1',
      message: 'message 1',
      cards: [{ id: testCard1, title: 'Hassan' }],
    };
    const message2 = {
      from: 'user1',
      message: 'message 2',
      cards: [{ id: testCard2, title: 'Mango' }],
    };

    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);

    await sendMessage(page, room1, 'message 1', [testCard1]);
    await assertMessages(page, [message1]);

    await sendMessage(page, room1, 'message 2', [testCard2]);
    await assertMessages(page, [message1, message2]);

    await reloadAndOpenAiAssistant(page);
    await openRoom(page, room1);
    await assertMessages(page, [message1, message2]);

    await logout(page);
    await login(page, 'user1', 'pass');
    await openRoom(page, room1);
    await assertMessages(page, [message1, message2]);
  });

  test('can send multiple cards in a message', async ({ page }) => {
    const testCard1 = `${testHost}/hassan`;
    const testCard2 = `${testHost}/mango`;
    const message = {
      from: 'user1',
      message: 'message 1',
      cards: [
        { id: testCard1, title: 'Hassan' },
        { id: testCard2, title: 'Mango' },
      ],
    };

    await login(page, 'user1', 'pass');
    let room1 = await getRoomId(page);

    await selectCardFromCatalog(page, testCard1);
    await selectCardFromCatalog(page, testCard2);
    await sendMessage(page, room1, 'message 1');
    await assertMessages(page, [message]);

    await reloadAndOpenAiAssistant(page);
    await openRoom(page, room1);
    await assertMessages(page, [message]);

    await logout(page);
    await login(page, 'user1', 'pass');
    await openRoom(page, room1);
    await assertMessages(page, [message]);
  });

  test('attached cards are not duplicated', async ({ page }) => {
    const testCard1 = `${testHost}/hassan`;
    const testCard2 = `${testHost}/mango`;
    const testCard3 = `${testHost}/type-examples`;

    await login(page, 'user1', 'pass');
    await page.locator(`[data-test-room-settled]`).waitFor();

    await selectCardFromCatalog(page, testCard2);
    await selectCardFromCatalog(page, testCard1);
    await selectCardFromCatalog(page, testCard2);
    await selectCardFromCatalog(page, testCard3);
    await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(3);

    await page.locator('[data-test-send-message-btn]').click();
    await assertMessages(page, [
      {
        from: 'user1',
        cards: [
          { id: testCard2, title: 'Mango' },
          { id: testCard1, title: 'Hassan' },
          { id: testCard3, title: 'Type Examples' },
        ],
      },
    ]);
  });

  test('displays view all pill if attached card more than 4', async ({
    page,
  }) => {
    const testCard1 = `${testHost}/hassan`;
    const testCard2 = `${testHost}/mango`;
    const testCard3 = `${testHost}/type-examples`;
    const testCard4 = `${testHost}/fadhlan`;
    const testCard5 = `${testHost}/van-gogh`;

    await login(page, 'user1', 'pass');
    await page.locator(`[data-test-room-settled]`).waitFor();

    await selectCardFromCatalog(page, testCard1);
    await selectCardFromCatalog(page, testCard2);
    await selectCardFromCatalog(page, testCard3);
    await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(3);

    await selectCardFromCatalog(page, testCard4);
    await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(4);
    await expect(page.locator(`[data-test-view-all]`)).toHaveCount(0);

    await selectCardFromCatalog(page, testCard5);
    await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(3);
    await expect(page.locator(`[data-test-view-all]`)).toHaveCount(1);

    await page.locator('[data-test-view-all]').click();
    await expect(page.locator(`[data-test-view-all]`)).toHaveCount(0);
    await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(5);
  });

  test.describe('auto-attachment of cards in matrix room', () => {
    test.beforeEach(async ({ page }) => {
      await login(page, 'user1', 'pass');
      await getRoomId(page);
    });

    test('displays auto-attached card (1 stack)', async ({ page }) => {
      const testCard1 = `${testHost}/hassan`;
      await page
        .locator(
          `[data-test-stack-item-content] [data-test-cards-grid-item='${testCard1}']`,
        )
        .click();
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await page.locator(`[data-test-attached-card]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveText(
        'Topmost card is shared automatically',
      );
      await page.locator('[data-test-send-message-btn]').click();
      await assertMessages(page, [
        {
          from: 'user1',
          cards: [{ id: testCard1, title: 'Hassan' }],
        },
      ]);
    });
    test('manually attached card is not auto-attached', async ({ page }) => {
      const testCard1 = `${testHost}/hassan`;
      await selectCardFromCatalog(page, testCard1);
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await page.locator(`[data-test-attached-card]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveCount(0);
      await page.locator('[data-test-send-message-btn]').click();
      await assertMessages(page, [
        {
          from: 'user1',
          cards: [{ id: testCard1, title: 'Hassan' }],
        },
      ]);
    });

    test('manually attached card overwrites auto-attached card', async ({
      page,
    }) => {
      const testCard1 = `${testHost}/hassan`;
      await page
        .locator(
          `[data-test-stack-item-content] [data-test-cards-grid-item='${testCard1}']`,
        )
        .click();
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await page.locator(`[data-test-attached-card]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveText(
        'Topmost card is shared automatically',
      );
      await selectCardFromCatalog(page, testCard1);
      await page.locator(`[data-test-attached-card]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveCount(0);
      await page.locator('[data-test-send-message-btn]').click();
      await assertMessages(page, [
        {
          from: 'user1',
          cards: [{ id: testCard1, title: 'Hassan' }],
        },
      ]);
    });
    test('does not auto-attach index card', async ({ page }) => {
      const indexCard = `${testHost}/index`;
      await expect(
        page.locator(`[data-test-stack-card="${indexCard}"]`),
      ).toHaveCount(1); // The index card appears by default, we verify it exists here
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(0);
    });
    test('replaces auto-attached card when drilling down (1 stack)', async ({
      page,
    }) => {
      const testCard1 = `${testHost}/jersey`;
      const embeddedCard = `${testHost}/justin`;
      await page
        .locator(
          `[data-test-stack-item-content] [data-test-cards-grid-item='${testCard1}']`,
        )
        .click();
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await expect(
        page.locator(`[data-test-attached-card="${testCard1}"]`),
      ).toHaveCount(1);
      await page.locator('[data-test-card-format="embedded"]').click(); // click on embedded card
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await expect(
        page.locator(`[data-test-attached-card="${embeddedCard}"]`),
      ).toHaveCount(1);
      await page.locator('[data-test-send-message-btn]').click();
      await assertMessages(page, [
        {
          from: 'user1',
          cards: [{ id: embeddedCard, title: 'Justin T' }],
        },
      ]);
    });

    test('auto-attached card will get auto-remove when closing a stack', async ({
      page,
    }) => {
      const testCard1 = `${testHost}/hassan`;
      await page
        .locator(
          `[data-test-stack-item-content] [data-test-cards-grid-item='${testCard1}']`,
        )
        .click();
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await page.locator(`[data-test-attached-card]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveText(
        'Topmost card is shared automatically',
      );
      await page
        .locator(
          `[data-test-stack-card='${testCard1}'] [data-test-close-button]`,
        )
        .click();

      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(0);
    });

    test('can manually remove auto-attached card', async ({ page }) => {
      const testCard1 = `${testHost}/hassan`;
      await page
        .locator(
          `[data-test-stack-item-content] [data-test-cards-grid-item='${testCard1}']`,
        )
        .click();
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await page.locator(`[data-test-attached-card]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveText(
        'Topmost card is shared automatically',
      );
      await page
        .locator(
          `[data-test-attached-card='${testCard1}'] [data-test-remove-card-btn]`,
        )
        .click();
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(0);
      await expect(
        page.locator(`[data-test-stack-card='${testCard1}']`),
      ).toHaveCount(1); //card still on stack
    });

    test('re-opening previously removed auto-attached card will auto attach again', async ({
      page,
    }) => {
      const testCard1 = `${testHost}/hassan`;
      await page
        .locator(
          `[data-test-stack-item-content] [data-test-cards-grid-item='${testCard1}']`,
        )
        .click();
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await page.locator(`[data-test-attached-card]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveText(
        'Topmost card is shared automatically',
      );
      await page
        .locator(
          `[data-test-attached-card='${testCard1}'] [data-test-remove-card-btn]`,
        )
        .click();
      await page
        .locator(
          `[data-test-stack-card='${testCard1}'] [data-test-close-button]`,
        )
        .click();
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(0);
      await page
        .locator(
          `[data-test-stack-item-content] [data-test-cards-grid-item='${testCard1}']`,
        )
        .click();
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await page.locator(`[data-test-attached-card]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveText(
        'Topmost card is shared automatically',
      );
      await page.locator('[data-test-send-message-btn]').click();
      await assertMessages(page, [
        {
          from: 'user1',
          cards: [{ id: testCard1, title: 'Hassan' }],
        },
      ]);
    });

    test('(2 stack) displays both top cards as auto-attached ', async ({
      page,
    }) => {
      const testCard1 = `${testHost}/hassan`;
      const testCard2 = `${testHost}/mango`;
      await setupTwoStackItems(page, testCard1, testCard2);
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(2);
      await expect(
        page.locator(`[data-test-attached-card="${testCard1}"]`),
      ).toHaveCount(1);
      await expect(
        page.locator(`[data-test-attached-card="${testCard2}"]`),
      ).toHaveCount(1);
      await page.locator(`[data-test-attached-card="${testCard1}"]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveText(
        'Topmost card is shared automatically',
      );
      await page.locator(`[data-test-attached-card="${testCard2}"]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveText(
        'Topmost card is shared automatically',
      );
      await page.locator('[data-test-send-message-btn]').click();
      await assertMessages(page, [
        {
          from: 'user1',
          cards: [
            { id: testCard1, title: 'Hassan' },
            { id: testCard2, title: 'Mango' },
          ],
        },
      ]);
    });

    test('(2 stack) if both top cards are the same, only one auto-attached pill', async ({
      page,
    }) => {
      const testCard1 = `${testHost}/hassan`;
      await setupTwoStackItems(page, testCard1, testCard1);
      await expect(page.locator(`[data-test-attached-card]`)).toHaveCount(1);
      await expect(
        page.locator(`[data-test-attached-card="${testCard1}"]`),
      ).toHaveCount(1);
      await page.locator(`[data-test-attached-card="${testCard1}"]`).hover();
      await expect(page.locator(`[data-test-tooltip-content]`)).toHaveText(
        'Topmost card is shared automatically',
      );
      await page.locator('[data-test-send-message-btn]').click();
      await assertMessages(page, [
        {
          from: 'user1',
          cards: [{ id: testCard1, title: 'Hassan' }],
        },
      ]);
    });
  });

  test('it can send the prompts on new-session room as chat message on click', async ({
    page,
  }) => {
    const prompt = {
      from: 'user1',
      message: 'Do I have to use AI with Boxel?', // a prompt on new-session template
    };
    await login(page, 'user1', 'pass');
    await page.locator(`[data-test-room-settled]`).waitFor();

    await expect(page.locator(`[data-test-new-session]`)).toHaveCount(1);
    await expect(page.locator(`[data-test-prompt]`)).toHaveCount(3);

    await page.locator(`[data-test-prompt="1"]`).click();
    await expect(page.locator(`[data-test-new-session]`)).toHaveCount(0);
    await assertMessages(page, [prompt]);
  });

  test('sends message when no card open in the stack', async ({ page }) => {
    await login(page, 'user1', 'pass');
    await page
      .locator('[data-test-stack-card] [data-test-close-button]')
      .click();
    await page
      .locator('[data-test-message-field]')
      .fill('Sending message with no card open');
    await page.locator('[data-test-send-message-btn]').click();

    await assertMessages(page, [
      {
        from: 'user1',
        message: 'Sending message with no card open',
        cards: [],
      },
    ]);
  });

  test('attaches a card in a coversation multiple times', async ({ page }) => {
    const testCard = `${testHost}/hassan`;

    await login(page, 'user1', 'pass');
    await page.locator(`[data-test-room-settled]`).waitFor();

    for (let i = 1; i <= 3; i++) {
      await page.locator('[data-test-message-field]').fill(`Message - ${i}`);
      await selectCardFromCatalog(page, testCard);
      await page.locator('[data-test-send-message-btn]').click();
    }

    await assertMessages(page, [
      {
        from: 'user1',
        message: 'Message - 1',
        cards: [{ id: testCard, title: 'Hassan' }],
      },
      {
        from: 'user1',
        message: 'Message - 2',
        cards: [{ id: testCard, title: 'Hassan' }],
      },
      {
        from: 'user1',
        message: 'Message - 3',
        cards: [{ id: testCard, title: 'Hassan' }],
      },
    ]);

    // There should only be one card fragments event for multiple message events
    // if the card remains unchanged and is attached multiple times.
    let events = await getRoomEvents();
    let messageEvents = events.filter(
      (e) =>
        e.type === 'm.room.message' &&
        e.content.msgtype === 'org.boxel.message',
    );
    let cardFragmentEvents = events.filter(
      (e) =>
        e.type === 'm.room.message' &&
        e.content.msgtype === 'org.boxel.cardFragment' &&
        !e.content.data.nextFragment,
    );
    expect(messageEvents.length).toEqual(3);
    expect(cardFragmentEvents.length).toEqual(1);

    //Test the scenario where there is an update to the card
    await page
      .locator(
        `[data-test-stack-card="${testHost}/index"] [data-test-cards-grid-item="${testCard}"]`,
      )
      .click();
    await page
      .locator(`[data-test-stack-card="${testCard}"] [data-test-edit-button]`)
      .click();
    await page
      .locator('[data-test-field="firstName"] [data-test-boxel-input]')
      .fill('Updated Name');
    await page
      .locator(`[data-test-stack-card="${testCard}"] [data-test-edit-button]`)
      .click();

    await page
      .locator('[data-test-message-field]')
      .fill(`Message with updated card`);
    await page.locator('[data-test-send-message-btn]').click();

    await assertMessages(page, [
      {
        from: 'user1',
        message: 'Message - 1',
        cards: [{ id: testCard, title: 'Updated Name Abdel-Rahman' }],
      },
      {
        from: 'user1',
        message: 'Message - 2',
        cards: [{ id: testCard, title: 'Updated Name Abdel-Rahman' }],
      },
      {
        from: 'user1',
        message: 'Message - 3',
        cards: [{ id: testCard, title: 'Updated Name Abdel-Rahman' }],
      },
      {
        from: 'user1',
        message: 'Message with updated card',
        cards: [{ id: testCard, title: 'Updated Name Abdel-Rahman' }],
      },
    ]);

    // There must be a new card fragments event because the card has been updated.
    events = await getRoomEvents();
    messageEvents = events.filter(
      (e) =>
        e.type === 'm.room.message' &&
        e.content.msgtype === 'org.boxel.message',
    );
    cardFragmentEvents = events.filter(
      (e) =>
        e.type === 'm.room.message' &&
        e.content.msgtype === 'org.boxel.cardFragment' &&
        !e.content.data.nextFragment,
    );
    expect(messageEvents.length).toEqual(4);
    expect(cardFragmentEvents.length).toEqual(2);

    // Revert updates
    await page
      .locator(`[data-test-stack-card="${testCard}"] [data-test-edit-button]`)
      .click();
    await page
      .locator('[data-test-field="firstName"] [data-test-boxel-input]')
      .fill('Hassan');
    await page
      .locator(`[data-test-stack-card="${testCard}"] [data-test-edit-button]`)
      .click();
  });

  test('displays error message if message is too large', async ({ page }) => {
    await login(page, 'user1', 'pass');

    await page.locator('[data-test-message-field]').fill('a'.repeat(65000));
    await page.locator('[data-test-send-message-btn]').click();

    await expect(page.locator('[data-test-ai-assistant-message]')).toHaveCount(
      1,
    );
    await expect(page.locator('[data-test-card-error]')).toContainText(
      'Message is too large',
    );
    await expect(page.locator('[data-test-ai-bot-retry-button]')).toHaveCount(
      0,
    );
  });
});
