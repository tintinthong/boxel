import Service, { service } from '@ember/service';

import { buildWaiter } from '@ember/test-waiters';

import { cached } from '@glimmer/tracking';

import { restartableTask } from 'ember-concurrency';
import { TrackedMap } from 'tracked-built-ins';

import {
  RealmInfo,
  SupportedMimeType,
  RealmPaths,
} from '@cardstack/runtime-common';

import ENV from '@cardstack/host/config/environment';
import { getRealmSession } from '@cardstack/host/resources/realm-session';

import type CardService from '@cardstack/host/services/card-service';
import type LoaderService from '@cardstack/host/services/loader-service';

const waiter = buildWaiter('realm-info-service:waiter');
const { ownRealmURL } = ENV;

type RealmInfoWithPermissions = RealmInfo & {
  canRead: boolean;
  canWrite: boolean;
};

export default class RealmInfoService extends Service {
  @service declare loaderService: LoaderService;
  @service declare cardService: CardService;
  cachedRealmURLsForURL: Map<string, string> = new Map(); // Has the file url already been resolved to a realm url?
  cachedRealmInfos: TrackedMap<string, RealmInfoWithPermissions> =
    new TrackedMap(); // Has the realm url already been resolved to a realm info?
  cachedPublicReadableRealms: Map<string, boolean> = new Map();
  cachedFetchTasks: Map<string, Promise<Response>> = new Map();

  async fetchRealmURL(url: string): Promise<URL | undefined> {
    let realmURLString = this.getRealmURLFromCache(url);
    if (!realmURLString) {
      let response = await this.loaderService.loader.fetch(url, {
        method: 'HEAD',
      });
      realmURLString = response.headers.get('x-boxel-realm-url') ?? undefined;
    }
    let realmURL;
    if (realmURLString) {
      this.cachedRealmURLsForURL.set(url, realmURLString);
      realmURL = new URL(realmURLString);
    }

    return realmURL;
  }

  private getRealmURLFromCache(url: string) {
    let realmURLString = this.cachedRealmURLsForURL.get(url);
    if (!realmURLString) {
      realmURLString = Array.from(this.cachedRealmURLsForURL.values()).find(
        (realmURL) => url.includes(realmURL),
      );
    }
    return realmURLString;
  }

  async isPublicReadable(realmURL: URL): Promise<boolean> {
    let realmURLString = realmURL.href;
    if (this.cachedPublicReadableRealms.has(realmURLString)) {
      return this.cachedPublicReadableRealms.get(realmURLString)!;
    }
    let response = await this.loaderService.loader.fetch(realmURL, {
      method: 'HEAD',
    });
    let isPublicReadable = Boolean(
      response.headers.get('x-boxel-realm-public-readable'),
    );
    this.cachedPublicReadableRealms.set(realmURLString, isPublicReadable);

    return isPublicReadable;
  }

  // When realmUrl is provided, it will fetch realm info from that url, otherwise it will first
  // try to fetch the realm url from the file url
  async fetchRealmInfo(params: {
    realmURL?: URL;
    fileURL?: string;
  }): Promise<RealmInfo> {
    let { realmURL, fileURL } = params;
    if (!realmURL && !fileURL) {
      throw new Error("Must provide either 'realmUrl' or 'fileUrl'");
    }

    let token = waiter.beginAsync();
    try {
      let realmURLString = realmURL
        ? realmURL.href
        : (await this.fetchRealmURL(fileURL!))?.href;
      if (!realmURLString) {
        throw new Error(
          'Could not find realm URL in response headers (x-boxel-realm-url)',
        );
      }

      if (this.cachedRealmInfos.has(realmURLString)) {
        return this.cachedRealmInfos.get(realmURLString)!;
      } else {
        let realmInfoResponse = await this.cachedFetch(
          `${realmURLString}_info`,
          {
            headers: { Accept: SupportedMimeType.RealmInfo },
          },
        );

        //The usage of `clone()` is to avoid the `json already read` error.
        let realmInfo = (await realmInfoResponse.clone().json())?.data
          ?.attributes as RealmInfo;
        let realmSession = getRealmSession(this, {
          realmURL: () => new URL(realmURLString!),
        });
        await realmSession.loaded;
        this.cachedRealmInfos.set(realmURLString, {
          ...realmInfo,
          canRead: !!realmSession.canRead,
          canWrite: !!realmSession.canWrite,
        });
        return realmInfo;
      }
    } finally {
      waiter.endAsync(token);
    }
  }

  fetchAllKnownRealmInfos = restartableTask(async () => {
    let paths = this.cardService.realmURLs.map(
      (path) => new RealmPaths(new URL(path)).url,
    );
    let token = waiter.beginAsync();
    try {
      await Promise.all(
        paths.map(
          async (path) =>
            await this.fetchRealmInfo({ realmURL: new URL(path) }),
        ),
      );
    } finally {
      waiter.endAsync(token);
    }
  });

  // Currently the personal realm has not yet been implemented,
  // until then default to the realm serving the host app if it is writable,
  // otherwise default to the first writable realm lexically
  @cached
  get userDefaultRealm(): { path: string; info: RealmInfo } {
    let writeableRealms = [...this.cachedRealmInfos.entries()]
      .filter(([_, realmInfo]) => realmInfo.canWrite)
      .sort(([_a, a], [_b, b]) => a.name.localeCompare(b.name));
    let ownRealm = writeableRealms.find(([path]) => path === ownRealmURL);
    if (ownRealm) {
      let [path, info] = ownRealm;
      return { path, info };
    } else {
      let [path, info] = writeableRealms[0];
      return { path, info };
    }
  }

  private cachedFetch(url: string, init: RequestInit): Promise<Response> {
    let fetchTaskKey = url + init.method;
    let fetchTask = this.cachedFetchTasks.get(fetchTaskKey);
    if (fetchTask) {
      return fetchTask;
    }
    fetchTask = this.loaderService.loader.fetch(url, init);
    this.cachedFetchTasks.set(fetchTaskKey, fetchTask);
    return fetchTask;
  }
}
