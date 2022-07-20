import { assert } from '@ember/debug';
import { CopiedCSS } from '../utils/measurement';
import { formatTreeString, TreeNode } from '../utils/format-tree';
import Sprite from './sprite';
import Changeset from './changeset';

export interface Context {
  id: string | undefined;
  element: Element;
  currentBounds?: DOMRect;
  lastBounds?: DOMRect;
  isInitialRenderCompleted: boolean;
  isStable: boolean;
  captureSnapshot(opts?: {
    withAnimations: boolean;
    playAnimations: boolean;
  }): void;
  shouldAnimate(): boolean;
  hasOrphan(spriteOrElement: Sprite): boolean;
  removeOrphan(spriteOrElement: Sprite): void;
  appendOrphan(spriteOrElement: Sprite): void;
  clearOrphans(): void;
  args: {
    use?(changeset: Changeset): Promise<void>;
    id?: string;
  };
}

export interface SpriteStateTracker {
  id: string | null;
  role: string | null;
  element: Element;
  currentBounds?: DOMRect;
  lastBounds?: DOMRect;
  captureSnapshot(opts?: {
    withAnimations: boolean;
    playAnimations: boolean;
  }): void;
  lastComputedStyle: CopiedCSS | undefined;
  currentComputedStyle: CopiedCSS | undefined;
}

export interface GetDescendantNodesOptions {
  includeFreshlyRemoved: boolean;
  filter?(childNode: SpriteTreeNode): boolean;
}

type SpriteTreeModel = Context | SpriteStateTracker;

export enum SpriteTreeNodeType {
  Root,
  Context,
  Sprite,
}

export class SpriteTreeNode {
  contextModel: Context | undefined;
  spriteModel: SpriteStateTracker | undefined;

  parent: SpriteTreeNode | SpriteTree;
  children: Set<SpriteTreeNode> = new Set();
  freshlyRemovedChildren: Set<SpriteTreeNode> = new Set();

  get isContext() {
    return Boolean(this.contextModel);
  }

  get isSprite() {
    return Boolean(this.spriteModel);
  }

  constructor(
    model: Context,
    nodeType: SpriteTreeNodeType.Context,
    parentNode: SpriteTreeNode | SpriteTree
  );
  constructor(
    model: SpriteStateTracker,
    nodeType: SpriteTreeNodeType.Sprite,
    parentNode: SpriteTreeNode | SpriteTree
  );
  constructor(
    model: any,
    nodeType: SpriteTreeNodeType,
    parentNode: SpriteTreeNode | SpriteTree
  ) {
    if (nodeType === SpriteTreeNodeType.Context) {
      this.contextModel = model;
    } else if (nodeType === SpriteTreeNodeType.Sprite) {
      this.spriteModel = model;
    } else {
      throw new Error('Passed model is not a context or sprite');
    }

    this.parent = parentNode;
    parentNode.addChild(this);
  }

  get isRoot(): boolean {
    return this.parent instanceof SpriteTree;
  }

  get element(): Element {
    return (this.spriteModel?.element ?? this.contextModel?.element) as Element;
  }

  get ancestors(): SpriteTreeNode[] {
    let result: SpriteTreeNode[] = [];
    let node: SpriteTreeNode = this as SpriteTreeNode;
    while (node.parent) {
      if (node.parent instanceof SpriteTree) break;
      assert('if not the tree, it is a node', node instanceof SpriteTreeNode);
      result.push(node.parent);
      node = node.parent;
    }
    return result;
  }

  allChildSprites({ includeFreshlyRemoved = false }) {
    let result: SpriteStateTracker[] = [];

    for (let child of this.children) {
      if (child.isSprite) {
        result.push(child.spriteModel as SpriteStateTracker);
      }

      if (
        (child.isSprite ||
          (child.isContext &&
            !(
              child as {
                contextModel: Context;
              }
            ).contextModel.isStable)) &&
        child.children?.size
      ) {
        child
          .allChildSprites({ includeFreshlyRemoved })
          .forEach((c) => result.push(c));
      }
    }

    return result;
  }

  getDescendantNodes(
    opts: GetDescendantNodesOptions = {
      includeFreshlyRemoved: false,
      filter: (_childNode: SpriteTreeNode) => true,
    }
  ): SpriteTreeNode[] {
    if (!opts.filter) opts.filter = () => true;
    let result: SpriteTreeNode[] = [];
    let children = this.children;
    if (opts.includeFreshlyRemoved) {
      children = new Set([...children, ...this.freshlyRemovedChildren]);
    }
    for (let childNode of children) {
      result.push(childNode);
      if (!opts.filter(childNode)) continue;
      result = result.concat(childNode.getDescendantNodes(opts));
    }
    return result;
  }

  clearFreshlyRemovedChildren(): void {
    for (let rootNode of this.children) {
      rootNode.freshlyRemovedChildren.clear();
      rootNode.clearFreshlyRemovedChildren();
    }
  }

  addChild(childNode: SpriteTreeNode): void {
    this.children.add(childNode);
  }
  removeChild(childNode: SpriteTreeNode): void {
    this.children.delete(childNode);
    this.freshlyRemovedChildren.add(childNode);
  }

  toLoggableForm(isRemoved?: boolean): TreeNode {
    let text = '';
    if (this.isContext) {
      let contextId = (this as { contextModel: Context }).contextModel.id;
      text += `🥡${contextId ? ` ${contextId}` : ''} `;
    }
    if (this.isSprite) {
      let spriteId = (this as { spriteModel: SpriteStateTracker }).spriteModel
        .id;
      text += `🥠${spriteId ? ` ${spriteId}` : ''}`;
    }
    let extra = isRemoved ? '❌' : undefined;
    return {
      text,
      extra,
      children: Array.from(this.children)
        .map((v) => v.toLoggableForm(isRemoved))
        .concat(
          Array.from(this.freshlyRemovedChildren).map((v) =>
            v.toLoggableForm(true)
          )
        ),
    };
  }
}

export default class SpriteTree {
  contextModel = undefined;
  spriteModel = undefined;
  isContext = false;
  isSprite = false;

  nodesByElement = new WeakMap<Element, SpriteTreeNode>();
  rootNodes: Set<SpriteTreeNode> = new Set();
  _pendingAdditions: (
    | { item: Context; type: 'CONTEXT' }
    | { item: SpriteStateTracker; type: 'SPRITE' }
  )[] = [];
  freshlyRemovedToNode: WeakMap<SpriteStateTracker, SpriteTreeNode> =
    new WeakMap();

  addPendingAnimationContext(item: Context) {
    this._pendingAdditions.push({ item, type: 'CONTEXT' });
  }

  addPendingSpriteModifier(item: SpriteStateTracker) {
    this._pendingAdditions.push({ item, type: 'SPRITE' });
  }

  flushPendingAdditions() {
    // sort by document position because parents must always be added before children
    this._pendingAdditions.sort((a, b) => {
      let bitmask = a.item.element.compareDocumentPosition(b.item.element);

      assert(
        'Document position is not implementation-specific or disconnected',
        !(
          bitmask & Node.DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC ||
          bitmask & Node.DOCUMENT_POSITION_DISCONNECTED
        )
      );

      return bitmask & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
    });

    for (let v of this._pendingAdditions) {
      if (v.type === 'CONTEXT') {
        this.addAnimationContext(v.item);
      } else if (v.type === 'SPRITE') {
        this.addSpriteModifier(v.item);
      } else {
        throw new Error('unexpected pending addition');
      }
    }

    this._pendingAdditions = [];
  }

  addAnimationContext(context: Context): SpriteTreeNode {
    let existingNode = this.lookupNodeByElement(context.element);

    if (existingNode) {
      assert(
        'Cannot add an AnimationContext which was already added',
        !existingNode.isContext
      );

      existingNode.contextModel = context;
      return existingNode;
    } else {
      let parentNode = this.findParentNode(context.element);
      let node = new SpriteTreeNode(
        context,
        SpriteTreeNodeType.Context,
        parentNode || this
      );
      this.nodesByElement.set(context.element, node);
      return node;
    }
  }
  removeAnimationContext(context: Context): void {
    let node = this.lookupNodeByElement(context.element);
    if (node) {
      node.parent?.removeChild(node);
      if (node.isSprite) {
        // TODO: we might need to do some cleanup? This is currently a WeakMap but..
        // situation where this matters is SpriteModifier hanging around when it should be removed
        this.freshlyRemovedToNode.set(
          (node as { spriteModel: SpriteStateTracker }).spriteModel,
          node
        );
      }
      this.nodesByElement.delete(context.element);
    }
  }
  addSpriteModifier(spriteModifier: SpriteStateTracker): SpriteTreeNode {
    let resultNode: SpriteTreeNode;
    let existingNode = this.lookupNodeByElement(spriteModifier.element);
    if (existingNode) {
      assert(
        'Cannot add a SpriteModel which was already added',
        !existingNode.isSprite
      );

      existingNode.spriteModel = spriteModifier;
      resultNode = existingNode;
    } else {
      let parentNode = this.findParentNode(spriteModifier.element);
      let node = new SpriteTreeNode(
        spriteModifier,
        SpriteTreeNodeType.Sprite,
        parentNode || this
      );
      this.nodesByElement.set(spriteModifier.element, node);
      resultNode = node;
    }

    if (!resultNode.parent.isContext) {
      console.error(
        `Sprite "${spriteModifier.id}" cannot have another Sprite as a direct parent. An extra AnimationContext will need to be added.`
      );
    }

    return resultNode;
  }
  removeSpriteModifier(spriteModifer: SpriteStateTracker): void {
    let node = this.lookupNodeByElement(spriteModifer.element);
    if (node) {
      node.parent?.removeChild(node);
      if (node.isSprite) {
        // TODO: we might need to do some cleanup? This is currently a WeakMap but..
        // situation where this matters is SpriteModifier hanging around when it should be removed
        this.freshlyRemovedToNode.set(
          (node as { spriteModel: SpriteStateTracker }).spriteModel,
          node
        );
      }
      this.nodesByElement.delete(spriteModifer.element);
    }
  }
  lookupNodeByElement(element: Element): SpriteTreeNode | undefined {
    return this.nodesByElement.get(element);
  }
  descendantsOf(
    model: SpriteTreeModel,
    opts: GetDescendantNodesOptions = { includeFreshlyRemoved: false }
  ): SpriteTreeModel[] {
    let node = this.lookupNodeByElement(model.element);
    if (node) {
      return node.getDescendantNodes(opts).reduce((result, n) => {
        if (n.contextModel) {
          result.push(n.contextModel);
        }
        if (n.spriteModel) {
          result.push(n.spriteModel);
        }
        return result;
      }, [] as SpriteTreeModel[]);
    } else {
      return [];
    }
  }

  getContextRunList(requestedContexts: Set<Context>): Context[] {
    let result: Context[] = [];
    for (let context of requestedContexts) {
      if (result.indexOf(context) !== -1) continue;
      result.unshift(context);
      let node = this.lookupNodeByElement(context.element);
      let ancestor = node && node.parent;
      while (ancestor) {
        if (ancestor.isContext) {
          if (result.indexOf(ancestor.contextModel as Context) === -1) {
            result.push(ancestor.contextModel as Context);
          }
        }
        ancestor = (ancestor as SpriteTreeNode).parent;
      }
    }
    return result;
  }

  clearFreshlyRemovedChildren(): void {
    for (let rootNode of this.rootNodes) {
      rootNode.freshlyRemovedChildren.clear();
      rootNode.clearFreshlyRemovedChildren();
    }
  }

  addChild(rootNode: SpriteTreeNode): void {
    for (let existingRootNode of this.rootNodes) {
      if (rootNode.element.contains(existingRootNode.element)) {
        this.removeChild(existingRootNode);
        existingRootNode.parent = rootNode;
        rootNode.addChild(existingRootNode);
      }
    }
    this.rootNodes.add(rootNode);
  }
  removeChild(rootNode: SpriteTreeNode): void {
    this.rootNodes.delete(rootNode);
  }

  private findParentNode(element: Element) {
    while (element.parentElement) {
      let node = this.lookupNodeByElement(element.parentElement);
      if (node) {
        return node;
      }
      element = element.parentElement;
    }
    return null;
  }

  findStableSharedAncestor(
    spriteA: SpriteStateTracker,
    spriteB: SpriteStateTracker
  ) {
    let ancestorsOfKeptSprite = this.nodesByElement
      .get(spriteA.element)
      ?.ancestors.filter((v) => v.contextModel?.isStable);
    let ancestorsOfCounterpartSprite = this.freshlyRemovedToNode
      .get(spriteB)
      ?.ancestors.filter((v) => v.contextModel?.isStable);

    return ancestorsOfKeptSprite?.find((v) =>
      ancestorsOfCounterpartSprite?.includes(v)
    )?.contextModel;
  }

  log() {
    console.log(
      formatTreeString({
        text: 'ROOT',
        children: Array.from(this.rootNodes).map((v) => v.toLoggableForm()),
      })
    );
  }
}