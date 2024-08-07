import { service } from '@ember/service';
import { cached } from '@glimmer/tracking';

import ignore, { type Ignore } from 'ignore';

import isEqual from 'lodash/isEqual';
import merge from 'lodash/merge';

import {
  baseRealm,
  logger,
  baseCardRef,
  isCardResource,
  internalKeyFor,
  trimExecutableExtension,
  hasExecutableExtension,
  SupportedMimeType,
  loadCard,
  identifyCard,
  moduleFrom,
  isCardDef,
  IndexUpdater,
  type Batch,
  type LooseCardResource,
  type InstanceEntry,
  type ErrorEntry,
  type CodeRef,
  type RealmInfo,
  type IndexResults,
  type SingleCardDocument,
  type CardResource,
  type Relationship,
  type TextFileRef,
} from '@cardstack/runtime-common';
import { Deferred } from '@cardstack/runtime-common/deferred';
import {
  CardError,
  isCardError,
  serializableError,
  type SerializedError,
} from '@cardstack/runtime-common/error';
import { RealmPaths, LocalPath } from '@cardstack/runtime-common/paths';
import { isIgnored } from '@cardstack/runtime-common/search-index';
import { type Reader, type Stats } from '@cardstack/runtime-common/worker';

import {
  CardDef,
  type IdentityContext as IdentityContextType,
} from 'https://cardstack.com/base/card-api';
import type * as CardAPI from 'https://cardstack.com/base/card-api';

import LoaderService from '../services/loader-service';
import { type RenderCard } from '../services/render-service';

import { getScopedCss } from './scoped-css';

const log = logger('current-run');

interface CardType {
  refURL: string;
  codeRef: CodeRef;
}
type TypesWithErrors =
  | {
      type: 'types';
      types: CardType[];
    }
  | {
      type: 'error';
      error: SerializedError;
    };

export class CurrentRun {
  #typesCache = new WeakMap<typeof CardDef, Promise<TypesWithErrors>>();
  #indexingInstances = new Map<string, Promise<void>>();
  #reader: Reader;
  #indexUpdater: IndexUpdater;
  #batch: Batch | undefined;
  #realmPaths: RealmPaths;
  #ignoreData: Record<string, string>;
  #renderCard: RenderCard;
  #realmURL: URL;
  #realmInfo?: RealmInfo;
  readonly stats: Stats = {
    instancesIndexed: 0,
    instanceErrors: 0,
    moduleErrors: 0,
  };
  @service declare loaderService: LoaderService;

  constructor({
    realmURL,
    reader,
    indexUpdater,
    ignoreData = {},
    renderCard,
  }: {
    realmURL: URL;
    reader: Reader;
    indexUpdater: IndexUpdater;
    ignoreData?: Record<string, string>;
    renderCard: RenderCard;
  }) {
    this.#indexUpdater = indexUpdater;
    this.#realmPaths = new RealmPaths(realmURL);
    this.#reader = reader;
    this.#realmURL = realmURL;
    this.#ignoreData = ignoreData;
    this.#renderCard = renderCard;
  }

  static async fromScratch(current: CurrentRun): Promise<IndexResults> {
    await current.whileIndexing(async () => {
      let start = Date.now();
      log.debug(`starting from scratch indexing`);
      current.#batch = await current.#indexUpdater.createBatch(
        current.realmURL,
      );
      await current.batch.makeNewGeneration();
      await current.visitDirectory(current.realmURL);
      await current.batch.done();
      log.debug(`completed from scratch indexing in ${Date.now() - start}ms`);
    });
    let { stats, ignoreData } = current;
    return { invalidations: [], stats, ignoreData };
  }

  static async incremental(
    current: CurrentRun,
    {
      url,
      operation,
    }: {
      url: URL;
      operation: 'update' | 'delete';
    },
  ): Promise<IndexResults> {
    let start = Date.now();
    log.debug(`starting from incremental indexing for ${url.href}`);

    current.#batch = await current.#indexUpdater.createBatch(current.realmURL);
    let invalidations = (await current.batch.invalidate(url)).map(
      (href) => new URL(href),
    );

    await current.whileIndexing(async () => {
      for (let invalidation of invalidations) {
        if (operation === 'delete' && invalidation.href === url.href) {
          // file is deleted, there is nothing to visit
        } else {
          await current.tryToVisit(invalidation);
        }
      }

      await current.batch.done();

      log.debug(
        `completed incremental indexing for ${url.href} in ${
          Date.now() - start
        }ms`,
      );
    });
    return {
      invalidations: [...invalidations].map((url) => url.href),
      ignoreData: current.#ignoreData,
      stats: current.stats,
    };
  }

  private async tryToVisit(url: URL) {
    try {
      await this.visitFile(url);
    } catch (err: any) {
      if (isCardError(err) && err.status === 404) {
        log.info(`tried to visit file ${url.href}, but it no longer exists`);
      } else {
        throw err;
      }
    }
  }

  private async whileIndexing(doIndexing: () => Promise<void>) {
    this.loaderService.setIsIndexing(true);
    await doIndexing();
    this.loaderService.setIsIndexing(false);
  }

  private get batch() {
    if (!this.#batch) {
      throw new Error('Batch is missing');
    }
    return this.#batch;
  }

  get ignoreData() {
    return this.#ignoreData;
  }

  get realmURL() {
    return this.#realmURL;
  }

  @cached
  private get ignoreMap() {
    let ignoreMap = new Map<string, Ignore>();
    for (let [url, contents] of Object.entries(this.#ignoreData)) {
      ignoreMap.set(url, ignore().add(contents));
    }
    return ignoreMap;
  }

  private async visitDirectory(url: URL): Promise<void> {
    let ignorePatterns = await this.#reader.readFileAsText(
      this.#realmPaths.local(new URL('.gitignore', url)),
    );
    if (ignorePatterns && ignorePatterns.content) {
      this.ignoreMap.set(url.href, ignore().add(ignorePatterns.content));
      this.#ignoreData[url.href] = ignorePatterns.content;
    }

    for await (let { path: innerPath, kind } of this.#reader.readdir(
      this.#realmPaths.local(url),
    )) {
      let innerURL = this.#realmPaths.fileURL(innerPath);
      if (isIgnored(this.#realmURL, this.ignoreMap, innerURL)) {
        continue;
      }
      if (kind === 'file') {
        await this.visitFile(innerURL, undefined);
      } else {
        let directoryURL = this.#realmPaths.directoryURL(innerPath);
        await this.visitDirectory(directoryURL);
      }
    }
  }

  private async visitFile(
    url: URL,
    identityContext?: IdentityContextType,
  ): Promise<void> {
    if (isIgnored(this.#realmURL, this.ignoreMap, url)) {
      return;
    }
    let start = Date.now();
    log.debug(`begin visiting file ${url.href}`);
    let localPath = this.#realmPaths.local(url);

    let fileRef = await this.#reader.readFileAsText(localPath);
    if (!fileRef) {
      let error = new CardError(`missing file ${url.href}`, { status: 404 });
      error.deps = [url.href];
      throw error;
    }
    let { content, lastModified } = fileRef;
    if (hasExecutableExtension(url.href)) {
      await this.indexModule(url, fileRef);
    } else {
      if (!identityContext) {
        let api = await this.loaderService.loader.import<typeof CardAPI>(
          `${baseRealm.url}card-api`,
        );
        let { IdentityContext } = api;
        identityContext = new IdentityContext();
      }

      if (url.href.endsWith('.json')) {
        let resource;

        try {
          let { data } = JSON.parse(content);
          resource = data;
        } catch (e) {
          log.warn(`unable to parse ${url.href} as card JSON`);
        }

        if (resource && isCardResource(resource)) {
          await this.indexCard({
            path: localPath,
            source: content,
            lastModified,
            resource,
            identityContext,
          });
        }
      }
    }
    log.debug(`completed visiting file ${url.href} in ${Date.now() - start}ms`);
  }

  private async indexModule(url: URL, ref: TextFileRef): Promise<void> {
    let module: Record<string, unknown>;
    try {
      module = await this.loaderService.loader.import(url.href);
    } catch (err: any) {
      this.stats.moduleErrors++;
      log.warn(
        `encountered error loading module "${url.href}": ${err.message}`,
      );
      let deps = await (
        await this.loaderService.loader.getConsumedModules(url.href)
      ).filter((u) => u !== url.href);
      await this.batch.updateEntry(new URL(url), {
        type: 'error',
        error: {
          status: 500,
          detail: `encountered error loading module "${url.href}": ${err.message}`,
          additionalErrors: null,
          deps,
        },
      });
      return;
    }

    if (module) {
      for (let exportName of Object.keys(module)) {
        module[exportName]; // we do this so that we can allow code ref identifies to be wired up in the loader
      }
    }
    if (ref.isShimmed) {
      log.debug(`skipping indexing of shimmed module ${url.href}`);
      return;
    }
    let consumes = (
      await this.loaderService.loader.getConsumedModules(url.href)
    ).filter((u) => u !== url.href);
    let deps = consumes.map((d) => trimExecutableExtension(new URL(d)).href);
    await this.batch.updateEntry(url, {
      type: 'module',
      source: ref.content,
      lastModified: ref.lastModified,
      deps: new Set(deps),
    });

    let request = await this.loaderService.loader.fetch(url.href);
    let transpiledSrc = await request.text();
    let css = getScopedCss(transpiledSrc);
    if (css) {
      await this.batch.updateEntry(url, {
        type: 'css',
        source: css,
        lastModified: ref.lastModified,
        deps: new Set(deps),
      });
    }
  }

  private async indexCard({
    path,
    source,
    lastModified,
    resource,
    identityContext,
  }: {
    path: LocalPath;
    source: string;
    lastModified: number;
    resource: LooseCardResource;
    identityContext: IdentityContextType;
  }): Promise<void> {
    let fileURL = this.#realmPaths.fileURL(path).href;
    let indexingInstance = this.#indexingInstances.get(fileURL);
    if (indexingInstance) {
      return await indexingInstance;
    }
    let deferred = new Deferred<void>();
    this.#indexingInstances.set(fileURL, deferred.promise);
    let instanceURL = new URL(
      this.#realmPaths.fileURL(path).href.replace(/\.json$/, ''),
    );
    let moduleURL = new URL(
      moduleFrom(resource.meta.adoptsFrom),
      new URL(path, this.#realmURL),
    ).href;
    let typesMaybeError: TypesWithErrors | undefined;
    let uncaughtError: Error | undefined;
    let doc: SingleCardDocument | undefined;
    let searchData: Record<string, any> | undefined;
    let cardType: typeof CardDef | undefined;
    let isolatedHtml: string | undefined;
    let atomHtml: string | undefined;
    let adjustedResource: CardResource | undefined;
    try {
      let api = await this.loaderService.loader.import<typeof CardAPI>(
        `${baseRealm.url}card-api`,
      );

      if (!this.#realmInfo) {
        let realmInfoResponse = await this.loaderService.loader.fetch(
          `${this.realmURL}_info`,
          { headers: { Accept: SupportedMimeType.RealmInfo } },
        );
        this.#realmInfo = (await realmInfoResponse.json())?.data?.attributes;
      }

      adjustedResource = {
        ...resource,
        ...{ id: instanceURL.href, type: 'card' },
      };
      //Realm info may be used by a card to render field values.
      //Example: catalog-entry-card
      merge(adjustedResource, {
        meta: {
          realmInfo: this.#realmInfo,
          realmURL: this.realmURL,
        },
      });
      let card = await api.createFromSerialized<typeof CardDef>(
        adjustedResource,
        { data: adjustedResource },
        new URL(fileURL),
        {
          identityContext,
        },
      );
      isolatedHtml = sanitizeHTML(
        await this.#renderCard({
          card,
          format: 'isolated',
          visit: this.visitFile.bind(this),
          identityContext,
          realmPath: this.#realmPaths,
        }),
      );
      atomHtml = sanitizeHTML(
        await this.#renderCard({
          card,
          format: 'atom',
          visit: this.visitFile.bind(this),
          identityContext,
          realmPath: this.#realmPaths,
        }),
      );
      cardType = Reflect.getPrototypeOf(card)?.constructor as typeof CardDef;
      let data = api.serializeCard(card, { includeComputeds: true });
      // prepare the document for index serialization
      Object.values(data.data.relationships ?? {}).forEach(
        (rel) => delete (rel as Relationship).data,
      );
      //Add again realm info and realm URL here
      //since we won't get it from serializeCard.
      doc = merge(data, {
        data: {
          id: instanceURL.href,
          meta: {
            lastModified: lastModified,
            realmInfo: this.#realmInfo,
            realmURL: this.realmURL.href,
          },
        },
      }) as SingleCardDocument;
      searchData = await api.searchDoc(card);

      if (!searchData) {
        throw new Error(
          `bug: could not derive search doc for instance ${instanceURL.href}`,
        );
      }

      // Add a "pseudo field" to the search doc for the card type. We use the
      // "_" prefix to make a decent attempt to not pollute the userland
      // namespace for cards
      if (cardType.displayName === 'Card') {
        searchData._cardType = cardType.name;
      } else {
        searchData._cardType = cardType.displayName;
      }
    } catch (err: any) {
      uncaughtError = err;
    }
    // if we already encountered an uncaught error then no need to deal with this
    if (!uncaughtError && cardType) {
      typesMaybeError = await this.getTypes(cardType);
    }
    let embeddedHtml: Record<string, string> | undefined;
    if (adjustedResource && typesMaybeError?.type === 'types') {
      embeddedHtml = await this.buildEmbeddedHtml(
        adjustedResource,
        typesMaybeError.types,
        identityContext,
      );
    }
    if (searchData && doc && typesMaybeError?.type === 'types') {
      await this.updateEntry(instanceURL, {
        type: 'instance',
        source,
        resource: doc.data,
        searchData,
        isolatedHtml,
        atomHtml,
        embeddedHtml,
        lastModified,
        types: typesMaybeError.types.map(({ refURL }) => refURL),
        deps: new Set([
          moduleURL,
          ...(await this.loaderService.loader.getConsumedModules(moduleURL)),
        ]),
      });
    } else if (uncaughtError || typesMaybeError?.type === 'error') {
      let error: ErrorEntry;
      if (uncaughtError) {
        error = {
          type: 'error',
          error:
            uncaughtError instanceof CardError
              ? serializableError(uncaughtError)
              : { detail: `${uncaughtError.message}` },
        };
        error.error.deps = [
          moduleURL,
          ...(uncaughtError instanceof CardError
            ? uncaughtError.deps ?? []
            : []),
        ];
      } else if (typesMaybeError?.type === 'error') {
        error = { type: 'error', error: typesMaybeError.error };
      } else {
        let err = new Error(`bug: should never get here`);
        deferred.reject(err);
        throw err;
      }
      log.warn(
        `encountered error indexing card instance ${path}: ${error.error.detail}`,
      );
      await this.updateEntry(instanceURL, error);
    }
    deferred.fulfill();
  }

  private async buildEmbeddedHtml(
    resource: CardResource,
    types: CardType[],
    identityContext: IdentityContextType,
  ): Promise<{ [refURL: string]: string }> {
    let api = await this.loaderService.loader.import<typeof CardAPI>(
      `${baseRealm.url}card-api`,
    );
    let result: { [refURL: string]: string } = {};
    for (let { codeRef, refURL } of types) {
      // we need to remove ourselves from the identity context so that we don't
      // revive a cached instance with the original card class
      let clonedIdentities = new Map([...identityContext.identities]);
      clonedIdentities.delete(resource.id);
      let modifiedContext = { identities: clonedIdentities };

      let resourceForType = merge(resource, { meta: { adoptsFrom: codeRef } });
      let card = await api.createFromSerialized<typeof CardDef>(
        resourceForType,
        { data: resourceForType },
        new URL(resource.id),
        {
          identityContext: modifiedContext,
        },
      );
      let embeddedHtml = sanitizeHTML(
        await this.#renderCard({
          card,
          format: 'embedded',
          visit: this.visitFile.bind(this),
          identityContext: modifiedContext,
          realmPath: this.#realmPaths,
        }),
      );

      result[refURL] = embeddedHtml;
    }
    return result;
  }

  private async updateEntry(
    instanceURL: URL,
    entry: InstanceEntry | ErrorEntry,
  ) {
    await this.batch.updateEntry(assertURLEndsWithJSON(instanceURL), entry);
    if (entry.type === 'instance') {
      this.stats.instancesIndexed++;
    } else {
      this.stats.instanceErrors++;
    }
  }

  private async getTypes(card: typeof CardDef): Promise<TypesWithErrors> {
    let cached = this.#typesCache.get(card);
    if (cached) {
      return await cached;
    }
    let ref = identifyCard(card);
    if (!ref) {
      throw new Error(`could not identify card ${card.name}`);
    }
    let deferred = new Deferred<TypesWithErrors>();
    this.#typesCache.set(card, deferred.promise);
    let types: CardType[] = [];
    let fullRef: CodeRef = ref;
    while (fullRef) {
      let loadedCard: typeof CardAPI.CardDef,
        loadedCardRef: CodeRef | undefined;
      try {
        let maybeCard = await loadCard(fullRef, {
          loader: this.loaderService.loader,
        });
        if (!isCardDef(maybeCard)) {
          throw new Error(
            `The definition at ${JSON.stringify(fullRef)} is not a CardDef`,
          );
        }
        loadedCard = maybeCard;
        loadedCardRef = identifyCard(loadedCard);
        if (!loadedCardRef) {
          throw new Error(`could not identify card ${loadedCard.name}`);
        }
      } catch (error) {
        return { type: 'error', error: serializableError(error) };
      }

      types.push({
        refURL: internalKeyFor(loadedCardRef, undefined),
        codeRef: loadedCardRef,
      });
      if (!isEqual(loadedCardRef, baseCardRef)) {
        fullRef = {
          type: 'ancestorOf',
          card: loadedCardRef,
        };
      } else {
        break;
      }
    }
    let result: TypesWithErrors = { type: 'types', types };
    deferred.fulfill(result);
    return result;
  }
}

function sanitizeHTML(html: string): string {
  // currently this only involves removing auto-generated ember ID's
  return html.replace(/\s+id="ember[0-9]+"/g, '');
}

function assertURLEndsWithJSON(url: URL): URL {
  if (!url.href.endsWith('.json')) {
    return new URL(`${url}.json`);
  }
  return url;
}
