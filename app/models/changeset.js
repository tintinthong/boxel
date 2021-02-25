import { intersect } from 'macro-decorators';
import SpriteFactory from '../models/sprite-factory';
import { KEPT } from './sprite';

export default class Changeset {
  insertedSprites = new Set();
  removedSprites = new Set();
  keptSprites = new Set();
  sentSprites = new Set();
  receivedSprites = new Set();

  constructor(animationContext) {
    this.context = animationContext;
  }

  addInsertedAndReceivedSprites(freshlyAdded, farMatchCandidates) {
    let farSpritesArray = Array.from(farMatchCandidates);
    for (let spriteModifier of freshlyAdded) {
      let matchingFarSpriteModifier = farSpritesArray.find(
        (s) => s.id && s.id === spriteModifier.id
      );
      if (matchingFarSpriteModifier) {
        this.receivedSprites.add(
          SpriteFactory.createReceivedSprite(
            spriteModifier,
            matchingFarSpriteModifier
          )
        );
      } else {
        this.insertedSprites.add(
          SpriteFactory.createInsertedSprite(spriteModifier)
        );
      }
    }
  }

  addRemovedAndSentSprites(freshlyRemoved) {
    for (let spriteModifier of freshlyRemoved) {
      if (spriteModifier.farMatch) {
        this.sentSprites.add(SpriteFactory.createSentSprite(spriteModifier));
      } else {
        this.removedSprites.add(
          SpriteFactory.createRemovedSprite(spriteModifier)
        );
      }
    }
  }

  addKeptSprites(freshlyChanged) {
    for (let spriteModifier of freshlyChanged) {
      this.keptSprites.add(SpriteFactory.createKeptSprite(spriteModifier));
    }
  }

  finalizeSpriteCategories() {
    let insertedSpritesArr = [...this.insertedSprites];
    let removedSpritesArr = [...this.removedSprites];
    let insertedIds = insertedSpritesArr.map((s) => s.id);
    let removedIds = removedSpritesArr.map((s) => s.id);
    let intersectingIds = insertedIds.filter((x) => removedIds.includes(x));
    for (let intersectingId of intersectingIds) {
      let removedSprite = removedSpritesArr.find(
        (s) => s.id === intersectingId
      );
      let insertedSprite = insertedSpritesArr.find(
        (s) => s.id === intersectingId
      );
      this.insertedSprites.delete(insertedSprite);
      this.removedSprites.delete(removedSprite);
      insertedSprite.type = KEPT;
      insertedSprite.initialBounds = removedSprite.initialBounds;
      insertedSprite.counterpart = removedSprite;
      this.keptSprites.add(insertedSprite);
    }
  }
}
